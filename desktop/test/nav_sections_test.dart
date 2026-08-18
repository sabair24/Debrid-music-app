/// The seven sections, and the promise that a phone and a window show the same seven.
///
/// [NavSections.items] is read by three navigations now — the pill strip, the phone's bottom bar
/// and the “Meer” sheet — and the last two are a SELECTION over the first. A selection can go
/// wrong in exactly two ways: a section that appears in neither half, and one that appears in
/// both. Neither shows up in a screenshot; both are one line of arithmetic here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';

void main() {
  final ids = NavSections.items.map((e) => e.$1).toList();

  test('elke sectie heeft een eigen id', () {
    expect(ids.toSet().length, ids.length,
        reason: 'twee secties met hetzelfde id: de ene is onbereikbaar');
  });

  test('de balk onderaan draagt alleen secties die bestaan', () {
    for (final id in NavSections.phonePrimary) {
      expect(ids, contains(id), reason: 'id $id staat op de balk maar niet in items');
    }
    expect(NavSections.phonePrimary.toSet().length, NavSections.phonePrimary.length,
        reason: 'dezelfde sectie twee keer op de balk');
  });

  test('“Meer” is precies wat de balk niet draagt', () {
    final more = NavSections.phoneMore.map((e) => e.$1).toSet();
    final bar = NavSections.phonePrimary.toSet();

    expect(more.intersection(bar), isEmpty, reason: 'een sectie op de balk én in het vel');
    expect(more.union(bar), ids.toSet(), reason: 'een sectie die nergens te bereiken is');
  });

  test('elke sectie heeft een naam, en een naam die op de balk past', () {
    for (final (id, label) in NavSections.items) {
      expect(NavSections.labelOf(id), label);
      expect(NavSections.shortLabelOf(id), isNotEmpty);
    }
    // An id that is not a section falls back rather than throwing: the section name is drawn on
    // every frame of the top bar, and a crash there takes the whole app with it.
    expect(NavSections.labelOf(-1), 'Start');
  });

  test('elke sectie heeft een eigen icoon', () {
    for (final id in ids) {
      expect(sectionIcon(id), isNot(Icons.circle_outlined),
          reason: 'sectie $id valt terug op het plaatsvervangende icoon');
    }
    final icons = ids.map(sectionIcon).toSet();
    expect(icons.length, ids.length, reason: 'twee secties met hetzelfde icoon');
  });
}
