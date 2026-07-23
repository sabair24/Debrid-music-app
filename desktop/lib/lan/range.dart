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

/// Send [file] to [response], honouring the request's `Range` header.
///
/// Range support is not a nicety here. Seeking inside a track needs it, Sonos and other UPnP
/// renderers probe with a range before they will play anything, and AVFoundation on the Apple
/// clients uses it to start playback without pulling a 200 MB hi-res file first.
Future<void> serveFile(
  HttpRequest request,
  File file, {
  required String contentType,
}) async {
  final total = await file.length();
  final res = request.response;
  res.headers
    ..set(HttpHeaders.acceptRangesHeader, 'bytes')
    ..set(HttpHeaders.contentTypeHeader, contentType)
    // Big and immutable: the bytes of a track never change under the same id.
    ..set(HttpHeaders.cacheControlHeader, 'private, max-age=86400');

  final range = parseRange(request.headers.value(HttpHeaders.rangeHeader), total);

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

  try {
    await res.addStream(file.openRead(start, end + 1));
  } on Exception {
    // The client hung up mid-track — normal when you skip to the next song. Nothing to report.
  }
  await res.close();
}
