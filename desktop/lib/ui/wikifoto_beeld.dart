/// Een foto uit Wikipedia naast een hoofdstuk van de biografie, met wat erbij hoort: het onderschrift
/// en wie hem maakte onder welke licentie. Zie `wikifotos.dart`.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../artwork.dart' show decodeWidth;
import '../overblok.dart' show kSectiefoto;
import '../wikifotos.dart';
import 'kleuren.dart';
import 'maten.dart';
import 'typografie.dart';

class WikiFotoBeeld extends StatefulWidget {
  const WikiFotoBeeld({super.key, required this.foto, this.dienst});

  final WikiFoto foto;

  /// Waar de bytes vandaan komen. Een toets zet hier een nep neer.
  final WikiFotoService? dienst;

  @override
  State<WikiFotoBeeld> createState() => _WikiFotoBeeldState();
}

class _WikiFotoBeeldState extends State<WikiFotoBeeld> {
  Uint8List? _bytes;
  bool _mislukt = false;

  @override
  void initState() {
    super.initState();
    _laad();
  }

  @override
  void didUpdateWidget(WikiFotoBeeld oud) {
    super.didUpdateWidget(oud);
    if (oud.foto.url != widget.foto.url) _laad();
  }

  Future<void> _laad() async {
    final url = widget.foto.url;
    final b = await (widget.dienst ?? WikiFotoService()).bytes(widget.foto);
    if (!mounted || url != widget.foto.url) return;
    setState(() {
      _bytes = b;
      _mislukt = b == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Lukt het niet, dan niets — geen leeg vak naast de tekst, dat leest als een storing.
    if (_mislukt) return const SizedBox.shrink();
    final b = _bytes;
    final onderschrift = widget.foto.onderschrift;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(kHoek8),
          child: b == null
              ? AspectRatio(aspectRatio: 4 / 3, child: ColoredBox(color: kLijnZacht))
              : Image.memory(b,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  cacheWidth: decodeWidth(kSectiefoto),
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
        if (onderschrift.isNotEmpty) ...[
          const SizedBox(height: kRuimte6),
          Text(onderschrift,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: kTekstKlein.copyWith(color: kTekst.withValues(alpha: .8), height: 1.4)),
        ],
        const SizedBox(height: kRuimte4),
        // Maker en licentie: Wikimedia-foto's zijn vrij onder voorwaarden, en dit is de voorwaarde.
        Text(widget.foto.vermelding,
            maxLines: 2, overflow: TextOverflow.ellipsis, style: kLabel.copyWith(fontWeight: FontWeight.w400)),
      ],
    );
  }
}
