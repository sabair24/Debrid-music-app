import 'dart:io';

/// A resolved byte range, inclusive at both ends — the same convention HTTP uses.
class ByteRange {
  final int start;
  final int end;
  const ByteRange(this.start, this.end);

  int get length => end - start + 1;

  @override
  String toString() => 'bytes $start-$end';

  @override
  bool operator ==(Object other) =>
      other is ByteRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Parse a `Range:` header against a file of [total] bytes.
///
/// Returns null when there is no usable range (no header, a form we don't serve, or a syntax
/// error) — the caller then sends the whole file, which is what RFC 9110 asks for. Returns a
/// zero-length marker via [rangeNotSatisfiable] when the range is syntactically fine but starts
/// past the end, which must be answered with 416 rather than silently with the whole file.
///
/// Only single ranges. Multipart ranges exist, but no audio client sends them and answering one
/// badly is worse than not offering it: we simply fall back to the whole file.
ByteRange? parseRange(String? header, int total) {
  if (header == null || total <= 0) return null;
  final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (m == null) return null;
  final rawStart = m.group(1)!;
  final rawEnd = m.group(2)!;
  if (rawStart.isEmpty && rawEnd.isEmpty) return null;

  int start;
  int end;
  if (rawStart.isEmpty) {
    // "bytes=-500" — the LAST 500 bytes. Renderers use this to read a trailing tag block.
    final n = int.parse(rawEnd);
    if (n <= 0) return rangeNotSatisfiable;
    start = n >= total ? 0 : total - n;
    end = total - 1;
  } else {
    start = int.parse(rawStart);
    end = rawEnd.isEmpty ? total - 1 : int.parse(rawEnd);
    if (start >= total) return rangeNotSatisfiable;
    if (end >= total) end = total - 1;
    if (end < start) return rangeNotSatisfiable;
  }
  return ByteRange(start, end);
}

/// Sentinel for "syntactically valid, but not satisfiable" → answer 416.
const ByteRange rangeNotSatisfiable = ByteRange(-1, -1);

/// Of een `If-Range` nog klopt met wat hier ligt: een merkteken moet exact gelijk zijn (een zwak
/// merkteken `W/` telt nooit, RFC 9110 13.1.5), een datum moet tot op de seconde gelijk zijn.
bool ifRangeKlopt(String ifRange, String etag, DateTime gewijzigd) {
  final v = ifRange.trim();
  if (v.startsWith('"') || v.startsWith('W/')) return v == etag;
  try {
    final d = HttpDate.parse(v);
    return d.millisecondsSinceEpoch ~/ 1000 == gewijzigd.millisecondsSinceEpoch ~/ 1000;
  } catch (_) {
    return false;
  }
}

/// Send [file] to [response], honouring the request's `Range` header.
///
/// Range support is not a nicety here. Seeking inside a track needs it, Sonos and other UPnP
/// renderers probe with a range before they will play anything, and AVFoundation on the Apple
/// clients uses it to start playback without pulling a 200 MB hi-res file first.
Future<void> serveFile(
  HttpRequest request,
  File file, {
  required String contentType,
  String? merk,
  void Function(int bytes)? verstuurd,
}) async {
  final stat = await file.stat();
  final total = stat.size;
  final res = request.response;
  // **Een merkteken en een datum, voor wie halverwege opnieuw vraagt.** De doorgever op de telefoon
  // (`doorgever.dart`) hervat een nummer na een netwerkwissel met `If-Range`: klopt het merkteken
  // niet meer, dan komt hier het hele bestand terug (200) in plaats van het stuk, en weet hij dat
  // het nummer op de pc veranderde terwijl het speelde — anders plakte hij twee verschillende
  // bestanden aan elkaar. [merk]: wat het merkteken draagt; standaard het tijdstip van het bestand,
  // voor een omgezette stroom de bron plus het recept (de naam in de cache).
  final etag = '"${merk ?? stat.modified.microsecondsSinceEpoch.toRadixString(16)}-${total.toRadixString(16)}"';
  res.headers
    ..set(HttpHeaders.acceptRangesHeader, 'bytes')
    ..set(HttpHeaders.contentTypeHeader, contentType)
    ..set(HttpHeaders.etagHeader, etag)
    ..set(HttpHeaders.lastModifiedHeader, HttpDate.format(stat.modified))
    // Big and immutable: the bytes of a track never change under the same id.
    ..set(HttpHeaders.cacheControlHeader, 'private, max-age=86400');

  var gevraagd = request.headers.value(HttpHeaders.rangeHeader);
  final ifRange = request.headers.value(HttpHeaders.ifRangeHeader);
  if (gevraagd != null && ifRange != null && !ifRangeKlopt(ifRange, etag, stat.modified)) gevraagd = null;
  final range = parseRange(gevraagd, total);

  if (range == rangeNotSatisfiable) {
    res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
    res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
    await res.close();
    return;
  }

  final start = range?.start ?? 0;
  final end = range?.end ?? (total - 1);
  res.statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent;
  res.headers.contentLength = end - start + 1;
  if (range != null) {
    res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
  }

  // A HEAD is how a renderer asks "how big is it, and can you do ranges?" before committing.
  // Answer the headers and stop — writing the body to a HEAD confuses picky clients.
  if (request.method == 'HEAD') {
    await res.close();
    return;
  }

  // Wat er werkelijk de deur uit ging (dataverbruik, lan/verzendteller.dart): ook bij een speler die halverwege afhaakt.
  var weg = 0;
  try {
    await res.addStream(verstuurd == null
        ? file.openRead(start, end + 1)
        : file.openRead(start, end + 1).map((d) {
            weg += d.length;
            return d;
          }));
  } on Exception {
    // The client hung up mid-track — normal when you skip to the next song. Nothing to report.
  }
  await res.close();
  verstuurd?.call(weg);
}
