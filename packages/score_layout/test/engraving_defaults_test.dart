import 'package:score_layout/score_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/support.dart';
import 'support/engraving_defaults.dart';
import 'support/fake_measurer.dart';
import 'support/role_scores.dart';

/// The kind of mark each default sets, for every default the engine reads.
const Map<String, InkRole> sets = {
  'barlineSeparation': InkRole.barline,
  'beamSpacing': InkRole.beam,
  'beamThickness': InkRole.beam,
  'dashedBarlineThickness': InkRole.barline,
  'hairpinThickness': InkRole.hairpin,
  'legerLineExtension': InkRole.ledgerLine,
  'legerLineThickness': InkRole.ledgerLine,
  'lyricLineThickness': InkRole.lyric,
  'octaveLineThickness': InkRole.octaveLine,
  'pedalLineThickness': InkRole.pedal,
  'repeatBarlineDotSeparation': InkRole.barline,
  'repeatEndingLineThickness': InkRole.volta,
  'slurEndpointThickness': InkRole.slur,
  'slurMidpointThickness': InkRole.slur,
  'staffLineThickness': InkRole.staffLine,
  'stemThickness': InkRole.stem,
  'textEnclosureThickness': InkRole.rehearsal,
  'thickBarlineThickness': InkRole.barline,
  'thinBarlineThickness': InkRole.barline,
  'tieEndpointThickness': InkRole.tie,
  'tieMidpointThickness': InkRole.tie,
  'tupletBracketThickness': InkRole.tuplet,
};

/// The defaults of [sets] that a line or a curve does not carry as its own
/// thickness. They move or size what is drawn.
const Set<String> shaping = {
  'barlineSeparation',
  'beamSpacing',
  'beamThickness',
  'legerLineExtension',
  'repeatBarlineDotSeparation',
  'textEnclosureThickness',
};

/// The defaults a line of each kind may take its thickness from. A kind
/// that draws a line has a row here or is in [unruled].
const Map<InkRole, List<String>> lineThickness = {
  InkRole.staffLine: ['staffLineThickness'],
  InkRole.barline: [
    'thinBarlineThickness',
    'thickBarlineThickness',
    'dashedBarlineThickness',
  ],
  InkRole.stem: ['stemThickness'],
  InkRole.flag: ['stemThickness'],
  InkRole.ledgerLine: ['legerLineThickness'],
  InkRole.tuplet: ['tupletBracketThickness'],
  InkRole.hairpin: ['hairpinThickness'],
  InkRole.octaveLine: ['octaveLineThickness'],
  InkRole.tempo: ['octaveLineThickness'],
  InkRole.pedal: ['pedalLineThickness'],
  InkRole.glissando: ['stemThickness'],
  InkRole.volta: ['repeatEndingLineThickness'],
  InkRole.lyric: ['lyricLineThickness'],
};

/// The defaults of the ends and of the middle of a curve of each kind.
const Map<InkRole, (String, String)> curveThickness = {
  InkRole.tie: ('tieEndpointThickness', 'tieMidpointThickness'),
  InkRole.slur: ('slurEndpointThickness', 'slurMidpointThickness'),
};

/// The bar of a rest of several bars is as thick as a glyph of the font,
/// and no default says how thick.
const Set<InkRole> unruled = {InkRole.rest};

/// The defaults the engine draws nothing with.
const Set<String> unread = {
  'arrowShaftThickness',
  'bracketThickness',
  'dashedBarlineDashLength',
  'dashedBarlineGapLength',
  'hBarThickness',
  'subBracketThickness',
};

/// Two bars with a dashed barline between them, which no score of
/// [roleSheets] has.
Score dashedScore() => changeBar(
  blankScore(),
  0,
  (column) => column.copyWith(barline: Barline.dashed),
);

/// Everything the sheets of [roleSheets] and [dashedScore] draw with
/// [defaults], each in its own style.
List<Drawable> drawnWith(EngravingDefaults defaults) => [
  for (final (score, style) in [
    ...roleSheets,
    (dashedScore(), EngravingStyle.standard),
  ])
    ...drawnBy(
      SheetLayout(
        score,
        width: 300,
        text: const FakeMeasurer(),
        style: style.copyWith(
          font: SmuflFont.bravura.copyWith(defaults: defaults),
        ),
      ),
    ),
];

List<Drawable> drawnBy(SheetLayout layout) => [
  ...layout.header,
  for (var i = 0; i < layout.systemCount; i++) ...[
    ...layout.systemAt(i).drawables,
    ?layout.labelOf(i),
  ],
];

Iterable<double> thicknessesOf(Drawable drawable) => switch (drawable) {
  LineDraw(:final thickness) => [thickness],
  CurveDraw(:final endThickness, :final midThickness) => [
    endThickness,
    midThickness,
  ],
  _ => const [],
};

void main() {
  final defaults = SmuflFont.bravura.defaults;
  // No default of Bravura has this value.
  const value = 0.37;
  late final plain = drawnWith(defaults);

  test('every default is one the engine reads or one it does not', () {
    expect(sets.keys.toSet().intersection(unread), isEmpty);
    expect({...sets.keys, ...unread}, engravingDefaultNames.toSet());
    expect(sets.keys, containsAll(shaping));
  });

  test('a default the engine reads changes the marks of its kind, and a '
      'thickness is the thickness of their lines', () {
    for (final MapEntry(key: name, value: role) in sets.entries) {
      final changed = drawnWith(withDefault[name]!(defaults, value));
      Set<Drawable> ofRole(List<Drawable> all) => {
        for (final drawable in all)
          if (drawable.ink == role) drawable,
      };

      final fresh = ofRole(changed).difference(ofRole(plain));
      expect(fresh, isNotEmpty, reason: '$name changes a mark of $role');
      if (!shaping.contains(name)) {
        expect(
          fresh.expand(thicknessesOf),
          contains(value),
          reason: '$name is the thickness of a line of $role',
        );
      }
    }
  });

  test('every line and every curve is as thick as a default of its kind '
      'says, at full size or at the size of a grace note', () {
    // A value of its own for every default, so that a thickness names the
    // default it came from.
    final own = {
      for (final (i, name) in engravingDefaultNames.indexed)
        name: 0.2 + i / 100,
    };
    final distinct = own.entries.fold(
      defaults,
      (defaults, entry) => withDefault[entry.key]!(defaults, entry.value),
    );
    final sizes = [1.0, EngravingStyle.standard.graceScale];
    bool isOf(double thickness, String name, double size) =>
        (thickness - own[name]! * size).abs() < 1e-9;
    final used = <String>{};

    for (final drawable in drawnWith(distinct)) {
      final role = drawable.ink;
      if (unruled.contains(role)) {
        continue;
      }
      switch (drawable) {
        case LineDraw(:final thickness):
          final from = [
            for (final name in lineThickness[role] ?? const <String>[])
              if (sizes.any((size) => isOf(thickness, name, size))) name,
          ];
          expect(
            from,
            hasLength(1),
            reason: 'a line of $role is $thickness thick',
          );
          used.addAll(from);
        case CurveDraw(:final endThickness, :final midThickness):
          final (ends, middle) = curveThickness[role]!;
          expect(
            sizes.any(
              (size) =>
                  isOf(endThickness, ends, size) &&
                  isOf(midThickness, middle, size),
            ),
            isTrue,
            reason:
                'a curve of $role is $endThickness thick at its ends and '
                '$midThickness in the middle',
          );
          used.addAll([ends, middle]);
        default:
      }
    }

    expect(used, {
      for (final names in lineThickness.values) ...names,
      for (final (ends, middle) in curveThickness.values) ...[ends, middle],
    });
    expect(used, sets.keys.toSet().difference(shaping));
  });

  test('a default under zero, or one that is no finite number, is refused, '
      'and zero is taken', () {
    for (final MapEntry(key: name, value: change) in withDefault.entries) {
      for (final value in [-0.01, double.nan, double.infinity]) {
        expect(
          () => change(defaults, value),
          throwsA(isA<AssertionError>()),
          reason: '$name of $value',
        );
      }
      expect(change(defaults, 0), isNot(defaults), reason: '$name of 0');
    }
  });

  test('a default the engine does not read changes nothing', () {
    for (final name in unread) {
      expect(
        drawnWith(withDefault[name]!(defaults, value)),
        plain,
        reason: name,
      );
    }
  });
}
