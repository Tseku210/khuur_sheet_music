import 'package:khuur_score_layout/src/bar_layout.dart';
import 'package:khuur_score_layout/src/bar_space.dart';
import 'package:khuur_score_layout/src/breaking.dart';
import 'package:khuur_score_layout/src/drawable.dart';
import 'package:khuur_score_layout/src/glyphs.dart';
import 'package:khuur_score_layout/src/spacing.dart';
import 'package:khuur_score_layout/src/style.dart';
import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';

import 'breaking_test.dart' show barsOf, breaksOf, layoutsOf, startsOf;
import 'support/bars.dart' show after;
import 'support/fake_measurer.dart';

/// The glyphs bar [bar] of [score] draws, each with its x centre in a frame
/// at its natural width, and that frame's slice xs.
({List<(Glyph, double)> glyphs, List<double> xs}) drawn(Score score, int bar) {
  final layout = layoutBar(
    score.measureView(score.measures[bar].id),
    EngravingStyle.standard,
    const FakeMeasurer(),
  );
  final xs = sliceXs(layout.slices, 1, 0);
  final frame = BarFrame(left: 0, xs: xs, tops: const [0]);
  return (
    glyphs: [
      for (final item in layout.items)
        if (frame.place(item) case final GlyphDraw glyph)
          (glyph.glyph, (glyph.bounds.left + glyph.bounds.right) / 2),
    ],
    xs: xs,
  );
}

Score repeated(List<int> counts, int bar, int bars) => after(barsOf(counts), [
  SetMeasureRepeat(barsOf(counts).measures[bar].id, bars: bars),
]);

void main() {
  test('a one-bar repeat draws its sign centred in the bar, not a rest', () {
    final (:glyphs, :xs) = drawn(repeated([4, 4], 1, 1), 1);

    expect(glyphs, hasLength(1));
    expect(glyphs.single.$1, Glyph.repeat1Bar);
    expect(glyphs.single.$2, closeTo((xs.first + xs.last) / 2, 1e-9));
  });

  test('a two-bar repeat draws its sign once, centred on the barline '
      'between its bars', () {
    final score = repeated([4, 4, 4, 4], 2, 2);
    final first = drawn(score, 2);
    final second = drawn(score, 3);

    expect(first.glyphs.single.$1, Glyph.repeat2Bars);
    expect(first.glyphs.single.$2, closeTo(first.xs.last, 1e-9));
    expect(second.glyphs, isEmpty);
  });

  test('a bar under a sign does not fold into a multi-measure rest', () {
    final score = repeated([0, 0, 0], 1, 1);
    const folding = EngravingStyle(multiMeasureRests: true);

    final units = foldBars(layoutsOf(score, style: folding), folding);

    expect(units.map((unit) => unit.bars.length), [1, 1, 1]);
  });

  test('a system never ends between the two bars of a two-bar repeat', () {
    final score = repeated([4, 4, 4, 4, 4, 4, 4, 4], 4, 2);
    final bars = layoutsOf(score);
    final plain = layoutsOf(barsOf([4, 4, 4, 4, 4, 4, 4, 4]));
    var splits = 0;
    for (var width = 20.0; width < 200; width += 0.5) {
      expect(
        startsOf(breaksOf(bars, width)),
        isNot(contains(5)),
        reason: 'width $width',
      );
      if (startsOf(breaksOf(plain, width)).contains(5)) {
        splits++;
      }
    }
    expect(splits, isPositive, reason: 'some width splits bars 4 and 5');
  });

  test('breaking resumed after an edit next to a two-bar repeat equals a '
      'fresh break', () {
    Score build(List<int> counts) {
      final score = barsOf(counts, staves: 2);
      return after(score, [
        SetMeasureRepeat(
          score.measures[3].id,
          bars: 2,
          staff: score.staves.first.id,
        ),
      ]);
    }

    final before = layoutsOf(build([4, 4, 4, 4, 8, 4, 4, 4]));
    final edited = layoutsOf(build([4, 4, 4, 4, 1, 4, 4, 4]));
    for (var width = 20.0; width < 200; width += 0.25) {
      expect(
        startsOf(breaksOf(edited, width, previous: breaksOf(before, width))),
        startsOf(breaksOf(edited, width)),
        reason: 'width $width',
      );
    }
  });
}
