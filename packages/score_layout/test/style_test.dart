import 'package:score_layout/score_layout.dart';
import 'package:test/test.dart';

/// Values built from an argument, so two calls give two objects and a
/// `const` does not make them one.
SpacingPolicy policyOf(double ratio) => SpacingPolicy(ratio: ratio, barPad: 2);

TextSpec specOf(double size) =>
    TextSpec(size: size, bold: true, family: 'Serif');

void main() {
  test('a copy of a style has the given part replaced and every other as it '
      'was', () {
    final renamed = SmuflFont(
      family: 'Other',
      glyphs: SmuflFont.bravura.glyphs,
      defaults: SmuflFont.bravura.defaults,
    );
    // No part of the standard style is in this one, so a part that a copy
    // drops shows as a default.
    final base = EngravingStyle(
      font: renamed,
      spacing: policyOf(1.5),
      text: {TextRole.lyric: specOf(3)},
      graceScale: 0.5,
      staffGap: 5,
      lyricGap: 1,
      systemGap: 7,
      multiMeasureRests: true,
      meterEverySystem: true,
      courtesySignatures: false,
      justifyLastSystemFrom: 0.5,
      barNumbers: false,
      quarterTones: QuarterToneGlyphs.gouldArrows,
      stringNumbers: StringNumbers.roman,
      chordSymbols: ChordSymbolSpelling.written,
    );
    const standard = EngravingStyle.standard;
    final parts = <String, (Object? Function(EngravingStyle), EngravingStyle)>{
      'font': ((s) => s.font, base.copyWith(font: standard.font)),
      'spacing': (
        (s) => s.spacing,
        base.copyWith(spacing: standard.spacing),
      ),
      'text': ((s) => s.text, base.copyWith(text: standard.text)),
      'graceScale': (
        (s) => s.graceScale,
        base.copyWith(graceScale: standard.graceScale),
      ),
      'staffGap': (
        (s) => s.staffGap,
        base.copyWith(staffGap: standard.staffGap),
      ),
      'lyricGap': (
        (s) => s.lyricGap,
        base.copyWith(lyricGap: standard.lyricGap),
      ),
      'systemGap': (
        (s) => s.systemGap,
        base.copyWith(systemGap: standard.systemGap),
      ),
      'multiMeasureRests': (
        (s) => s.multiMeasureRests,
        base.copyWith(multiMeasureRests: standard.multiMeasureRests),
      ),
      'meterEverySystem': (
        (s) => s.meterEverySystem,
        base.copyWith(meterEverySystem: standard.meterEverySystem),
      ),
      'courtesySignatures': (
        (s) => s.courtesySignatures,
        base.copyWith(courtesySignatures: standard.courtesySignatures),
      ),
      'justifyLastSystemFrom': (
        (s) => s.justifyLastSystemFrom,
        base.copyWith(
          justifyLastSystemFrom: standard.justifyLastSystemFrom,
        ),
      ),
      'barNumbers': (
        (s) => s.barNumbers,
        base.copyWith(barNumbers: standard.barNumbers),
      ),
      'quarterTones': (
        (s) => s.quarterTones,
        base.copyWith(quarterTones: standard.quarterTones),
      ),
      'stringNumbers': (
        (s) => s.stringNumbers,
        base.copyWith(stringNumbers: standard.stringNumbers),
      ),
      'chordSymbols': (
        (s) => s.chordSymbols,
        base.copyWith(chordSymbols: standard.chordSymbols),
      ),
    };

    expect(base.copyWith(), base);
    for (final MapEntry(key: part, value: (read, copy)) in parts.entries) {
      expect(read(copy), read(standard), reason: 'the $part of the copy');
      expect(read(copy), isNot(read(base)), reason: 'the $part of the base');
      for (final MapEntry(key: other, value: (readOther, _)) in parts.entries) {
        if (other != part) {
          expect(
            readOther(copy),
            readOther(base),
            reason: 'the $other of a copy with another $part',
          );
        }
      }
    }
  });

  test('a style with one field changed is another style, and one with every '
      'field equal is the same', () {
    final renamed = SmuflFont(
      family: 'Other',
      glyphs: SmuflFont.bravura.glyphs,
      defaults: SmuflFont.bravura.defaults,
    );
    final changed = <String, EngravingStyle>{
      'font': EngravingStyle(font: renamed),
      'spacing': const EngravingStyle(spacing: SpacingPolicy(ratio: 1.5)),
      'text': const EngravingStyle(
        text: {TextRole.lyric: TextSpec(size: 3)},
      ),
      'text of another role': const EngravingStyle(
        text: {TextRole.partName: TextSpec(size: 3)},
      ),
      'graceScale': const EngravingStyle(graceScale: 0.5),
      'staffGap': const EngravingStyle(staffGap: 5),
      'lyricGap': const EngravingStyle(lyricGap: 1),
      'systemGap': const EngravingStyle(systemGap: 7),
      'multiMeasureRests': const EngravingStyle(multiMeasureRests: true),
      'meterEverySystem': const EngravingStyle(meterEverySystem: true),
      'courtesySignatures': const EngravingStyle(courtesySignatures: false),
      'justifyLastSystemFrom': const EngravingStyle(justifyLastSystemFrom: 0.5),
      'barNumbers': const EngravingStyle(barNumbers: false),
      'quarterTones': const EngravingStyle(
        quarterTones: QuarterToneGlyphs.gouldArrows,
      ),
      'stringNumbers': const EngravingStyle(stringNumbers: StringNumbers.roman),
      'chordSymbols': const EngravingStyle(
        chordSymbols: ChordSymbolSpelling.written,
      ),
    };

    for (final MapEntry(key: field, value: style) in changed.entries) {
      expect(style, isNot(EngravingStyle.standard), reason: field);
    }
    expect(changed['text'], isNot(changed['text of another role']));

    EngravingStyle styleOf(double staffGap) => EngravingStyle(
      font: renamed,
      spacing: policyOf(1.5),
      text: {TextRole.lyric: specOf(3)},
      staffGap: staffGap,
      barNumbers: false,
    );
    final first = styleOf(5);
    final second = styleOf(5);
    expect(identical(first, second), isFalse);
    expect(identical(first.text, second.text), isFalse);
    expect(second, first);
    expect(second.hashCode, first.hashCode);
  });

  test('a spacing policy with one field changed is another policy', () {
    const changed = <String, SpacingPolicy>{
      'quarterSpace': SpacingPolicy(quarterSpace: 4),
      'ratio': SpacingPolicy(ratio: 1.5),
      'minGap': SpacingPolicy(minGap: 0.5),
      'barPad': SpacingPolicy(barPad: 2),
      'restRunWidth': SpacingPolicy(restRunWidth: 10),
    };

    for (final MapEntry(key: field, value: policy) in changed.entries) {
      expect(policy, isNot(const SpacingPolicy()), reason: field);
    }
    final first = policyOf(1.5);
    final second = policyOf(1.5);
    expect(identical(first, second), isFalse);
    expect(second, first);
    expect(second.hashCode, first.hashCode);
  });

  test('a text spec with one field changed is another spec', () {
    const spec = TextSpec(size: 2);
    const changed = <String, TextSpec>{
      'size': TextSpec(size: 3),
      'italic': TextSpec(size: 2, italic: true),
      'bold': TextSpec(size: 2, bold: true),
      'family': TextSpec(size: 2, family: 'Serif'),
    };

    for (final MapEntry(key: field, value: other) in changed.entries) {
      expect(other, isNot(spec), reason: field);
    }
    final first = specOf(2);
    final second = specOf(2);
    expect(identical(first, second), isFalse);
    expect(second, first);
    expect(second.hashCode, first.hashCode);
  });

  test('a text extent with one measure changed is another extent', () {
    TextExtent extentOf(double width) =>
        TextExtent(width: width, ascent: 2, descent: 1);
    const changed = <String, TextExtent>{
      'width': TextExtent(width: 4, ascent: 2, descent: 1),
      'ascent': TextExtent(width: 3, ascent: 3, descent: 1),
      'descent': TextExtent(width: 3, ascent: 2, descent: 2),
    };

    for (final MapEntry(key: field, value: other) in changed.entries) {
      expect(other, isNot(extentOf(3)), reason: field);
    }
    expect(identical(extentOf(3), extentOf(3)), isFalse);
    expect(extentOf(3), extentOf(3));
    expect(extentOf(3).hashCode, extentOf(3).hashCode);
  });
}
