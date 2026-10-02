import 'package:score_layout/src/bar_layout.dart';
import 'package:score_layout/src/bar_space.dart';
import 'package:score_layout/src/beams.dart';
import 'package:score_layout/src/chords.dart';
import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/spacing.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/bars.dart';
import 'support/fake_measurer.dart';

const EngravingStyle style = EngravingStyle.standard;

BarLayout layoutOf(MeasureView view) =>
    layoutBar(view, style, const FakeMeasurer());

BarFrame frameOf(BarLayout layout, double stretch) =>
    BarFrame(left: 0, xs: sliceXs(layout.slices, stretch, 0), tops: const [0]);

List<Drawable> drawn(BarLayout layout, double stretch, {int beam = 0}) =>
    placeBeam(layout.beams[beam], frameOf(layout, stretch), style);

Iterable<LineDraw> stemsIn(Iterable<Drawable> drawables) =>
    drawables.whereType<LineDraw>();

List<PolygonDraw> beamsIn(Iterable<Drawable> drawables) =>
    drawables.whereType<PolygonDraw>().toList();

/// The y of the outer edge of [beam] at [x].
double edgeAt(PolygonDraw beam, double x) {
  final from = beam.points[0];
  final to = beam.points[1];
  return from.y + (to.y - from.y) * (x - from.x) / (to.x - from.x);
}

void main() {
  final font = style.font;
  final halfStem = font.defaults.stemThickness / 2;
  final hook = font[Glyph.noteheadBlack].box.width;
  final level = font.defaults.beamThickness + font.defaults.beamSpacing;

  group('beamStemSides', () {
    Map<EventId, StemSide> sidesOf(MeasureView view) {
      final staff = view.staves.first;
      return beamStemSides(staff.voices.first, staff);
    }

    test('a group takes the side most of its chords want', () {
      final up = sidesOf(
        barOf([
          chordOf(1, 'C4', value: eighth),
          chordOf(2, 'C4', value: eighth),
          chordOf(3, 'C4', value: eighth),
          chordOf(4, 'C5', value: eighth),
        ]),
      );
      final down = sidesOf(
        barOf([
          chordOf(1, 'C5', value: eighth),
          chordOf(2, 'C5', value: eighth),
          chordOf(3, 'C5', value: eighth),
          chordOf(4, 'C4', value: eighth),
        ]),
      );

      expect(up.values, everyElement(StemSide.up));
      expect(up.keys, hasLength(4));
      expect(down.values, everyElement(StemSide.down));
    });

    test('a tie goes to the chord farthest from the middle line', () {
      final sides = sidesOf(
        barOf([
          chordOf(1, 'C4', value: eighth),
          chordOf(2, 'C4', value: eighth),
          chordOf(3, 'C5', value: eighth),
          chordOf(4, 'C5', value: eighth),
        ]),
      );

      expect(sides.values, everyElement(StemSide.up));
    });

    test('an unbeamed chord is not in the map', () {
      final sides = sidesOf(
        barOf([
          chordOf(1, 'C4'),
          chordOf(2, 'C4', value: eighth),
          chordOf(3, 'C4', value: eighth),
          chordOf(4, 'C4', value: half),
        ]),
      );

      expect(sides.keys, [const EventId(2), const EventId(3)]);
    });
  });

  group('planBeam', () {
    test('the beam clears the tremolo strokes of a beamed chord', () {
      final layout = layoutOf(
        barOf([
          chordOf(1, 'C4', value: sixteenth, tremolo: 3),
          chordOf(2, 'C4', value: sixteenth),
          chordOf(3, 'C4', value: eighth),
        ]),
      );
      final strokes = layout.items
          .map((i) => i.drawable)
          .whereType<GlyphDraw>()
          .singleWhere((g) => g.glyph == Glyph.tremolo3);
      final beams = beamsIn(drawn(layout, 1));

      expect(beams, hasLength(2));
      for (final beam in beams) {
        expect(
          beam.bounds.bottom,
          lessThanOrEqualTo(strokes.bounds.top - 0.5 + 1e-9),
        );
      }
    });

    test('the beam follows the far heads, capped at half a space', () {
      final rising = layoutOf(
        barOf([
          chordOf(1, 'C4', value: eighth),
          chordOf(2, 'D4', value: eighth),
          chordOf(3, 'E4', value: eighth),
          chordOf(4, 'F4', value: eighth),
        ]),
      ).beams.single;
      final falling = layoutOf(
        barOf([
          chordOf(1, 'F4', value: eighth),
          chordOf(2, 'E4', value: eighth),
          chordOf(3, 'D4', value: eighth),
          chordOf(4, 'C4', value: eighth),
        ]),
      ).beams.single;
      final level = layoutOf(
        barOf([
          chordOf(1, 'G4', value: eighth),
          chordOf(2, 'G4', value: eighth),
        ]),
      ).beams.single;

      expect(rising.stem, StemSide.up);
      expect(rising.first.dy - rising.last.dy, closeTo(0.5, 1e-9));
      expect(falling.last.dy - falling.first.dy, closeTo(0.5, 1e-9));
      expect(level.first.dy, level.last.dy);
    });

    test('the beam is flat when an inner head goes beyond both ends', () {
      final plan = layoutOf(
        barOf([
          chordOf(1, 'C4', value: eighth),
          chordOf(2, 'A4', value: eighth),
          chordOf(3, 'A4', value: eighth),
          chordOf(4, 'D4', value: eighth),
        ]),
      ).beams.single;

      expect(plan.first.dy, plan.last.dy);
      expect(plan.first.dy, closeTo(yOfStep(3) - stemLength, 1e-9));
    });

    test('an end stem is at least the stem length plus half a space per extra level', () {
      final eighths = layoutOf(
        barOf([
          chordOf(1, 'C5', value: eighth),
          chordOf(2, 'C5', value: eighth),
        ]),
      ).beams.single;
      final sixteenths = layoutOf(
        barOf([
          chordOf(1, 'C5', value: sixteenth),
          chordOf(2, 'C5', value: sixteenth),
          chordOf(3, 'C5', value: sixteenth),
          chordOf(4, 'C5', value: sixteenth),
        ]),
      ).beams.single;

      expect(eighths.stem, StemSide.down);
      expect(eighths.first.dy, closeTo(yOfStep(5) + stemLength, 1e-9));
      expect(sixteenths.first.dy, closeTo(yOfStep(5) + stemLength + 0.5, 1e-9));
    });

    test('every stem is at least the stem length when the ends are not the highest', () {
      final layout = layoutOf(
        barOf([
          chordOf(1, 'C4', value: eighth),
          chordOf(2, 'F4', value: eighth),
          chordOf(3, 'F4', value: eighth),
          chordOf(4, 'F4', value: eighth),
        ]),
      );
      final stems = stemsIn(drawn(layout, 1)).toList();
      final heads = [yOfStep(-2), yOfStep(1), yOfStep(1), yOfStep(1)];

      for (final (i, stem) in stems.indexed) {
        expect(
          heads[i] - stem.to.y,
          greaterThanOrEqualTo(stemLength - 1e-9),
        );
      }
      expect(heads[1] - stems[1].to.y, greaterThan(stemLength));
    });

    test('a beam end inside the staff moves outward onto a line position', () {
      final up = layoutOf(
        barOf([
          chordOf(1, 'C4', value: eighth),
          chordOf(2, 'F4', value: eighth),
          chordOf(3, 'F4', value: eighth),
          chordOf(4, 'F4', value: eighth),
        ]),
      ).beams.single;
      final down = layoutOf(
        barOf([
          chordOf(1, 'A5', value: eighth),
          chordOf(2, 'G5', value: eighth),
          chordOf(3, 'G5', value: eighth),
          chordOf(4, 'G5', value: eighth),
        ]),
      ).beams.single;

      expect(up.first.dy, 0);
      expect(up.last.dy, closeTo(-0.5, 1e-9));
      expect(down.first.dy, 3);
      expect(down.last.dy, 3.5);
    });

    test('the boxes cover the beam and its stems at stretch 1', () {
      final layout = layoutOf(
        barOf([
          chordOf(1, 'C4', value: eighth),
          chordOf(2, 'D4', value: eighth),
          chordOf(3, 'E4', value: eighth),
          chordOf(4, 'F4', value: eighth),
        ]),
      );
      final drawables = drawn(layout, 1);
      final box = drawables.map((d) => d.bounds).reduce((a, b) => a.union(b));

      final planned = layout.beams.single.boxes.reduce((a, b) => a.union(b));

      expect(planned.left, closeTo(box.left, 1e-9));
      expect(planned.top, closeTo(box.top, 1e-9));
      expect(planned.right, closeTo(box.right, 1e-9));
      expect(planned.bottom, closeTo(box.bottom, 1e-9));
      expect(box.bottom, greaterThan(yOfStep(-2) - 0.5));
    });

    test('the beam belongs to the group\'s first event', () {
      final view = barOf([
        chordOf(1, 'C4', value: eighth),
        chordOf(2, 'D4', value: eighth),
      ]);
      final plan = layoutOf(view).beams.single;

      expect(
        plan.owner,
        ElementOwner(view.staves.first.voices.first.events.first.ref),
      );
      expect(
        drawn(layoutOf(view), 1).map((d) => d.owner),
        everyElement(plan.owner),
      );
    });
  });

  group('placeBeam', () {
    final view = barOf([
      chordOf(1, 'C4', value: eighth),
      chordOf(2, 'E4', value: eighth),
      chordOf(3, 'G4', value: eighth),
      chordOf(4, 'B4', value: eighth),
      chordOf(5, 'C5', value: sixteenth),
      chordOf(6, 'D5', value: eighth),
      chordOf(7, 'E5', value: sixteenth),
      chordOf(8, 'F5'),
    ]);
    final layout = layoutOf(view);

    test('every stem ends on its beam at stretches 1, 2 and 3', () {
      for (final beam in [0, 1]) {
        for (final stretch in [1.0, 2.0, 3.0]) {
          final drawables = drawn(layout, stretch, beam: beam);
          final primary = beamsIn(drawables).first;
          final stems = stemsIn(drawables).toList();

          expect(stems, hasLength(beam == 0 ? 4 : 3));
          for (final stem in stems) {
            expect(stem.to.y, closeTo(edgeAt(primary, stem.to.x), 1e-9));
            expect(
              stem.to.x,
              inInclusiveRange(primary.points[0].x, primary.points[1].x),
            );
          }
        }
      }
    });

    test('a stretch spreads the stems and keeps both end heights', () {
      final narrow = stemsIn(drawn(layout, 1)).toList();
      final wide = stemsIn(drawn(layout, 3)).toList();

      expect(
        wide.last.to.x - wide.first.to.x,
        greaterThan(narrow.last.to.x - narrow.first.to.x),
      );
      expect(wide.first.to.y, narrow.first.to.y);
      expect(wide.last.to.y, narrow.last.to.y);
    });

    test('every stem starts inside its head', () {
      final frame = frameOf(layout, 2);
      final heads = {
        for (final item in layout.items)
          if (item.drawable case GlyphDraw(
            owner: ElementOwner(ref: NoteRef(:final event)),
          ))
            event.id: frame.place(item).bounds,
      };
      final stems = stemsIn(drawn(layout, 2)).toList();

      for (final (i, id) in [1, 2, 3, 4].indexed) {
        final head = heads[EventId(id)]!;
        expect(head.contains(stems[i].from), isTrue);
      }
    });

    test('the primary beam spans the stems and secondary beams and hooks follow the joins', () {
      final drawables = drawn(layout, 1, beam: 1);
      final stems = stemsIn(drawables).toList();
      final beams = beamsIn(drawables);
      final x0 = stems[0].to.x;
      final x2 = stems[2].to.x;

      expect(layout.beams[1].joins, [
        [BeamJoin.begin, BeamJoin.forwardHook],
        [BeamJoin.continued],
        [BeamJoin.end, BeamJoin.backwardHook],
      ]);
      expect(beams, hasLength(3));
      expect(beams[0].points[0].x, closeTo(x0 - halfStem, 1e-9));
      expect(beams[0].points[1].x, closeTo(x2 + halfStem, 1e-9));
      expect(beams[1].points[0].x, closeTo(x0 - halfStem, 1e-9));
      expect(beams[1].points[1].x, closeTo(x0 + hook, 1e-9));
      expect(beams[2].points[0].x, closeTo(x2 - hook, 1e-9));
      expect(beams[2].points[1].x, closeTo(x2 + halfStem, 1e-9));
      expect(layout.beams[1].stem, StemSide.down);
      expect(
        beams[1].points[0].y,
        closeTo(edgeAt(beams[0], x0 - halfStem) - level, 1e-9),
      );
      expect(
        beams[2].points[1].y,
        closeTo(edgeAt(beams[0], x2 + halfStem) - level, 1e-9),
      );
    });

    test('a beam is as thick as the font says, inward from its outer edge', () {
      final beams = beamsIn(drawn(layout, 1));
      final outer = beams.first.points[0].y;
      final inner = beams.first.points[3].y;

      expect(layout.beams[0].stem, StemSide.up);
      expect(inner - outer, closeTo(font.defaults.beamThickness, 1e-9));
    });

    test('four sixteenths share two full beams', () {
      final drawables = drawn(
        layoutOf(
          barOf([
            chordOf(1, 'C5', value: sixteenth),
            chordOf(2, 'D5', value: sixteenth),
            chordOf(3, 'E5', value: sixteenth),
            chordOf(4, 'F5', value: sixteenth),
          ]),
        ),
        1,
      );
      final beams = beamsIn(drawables);
      final stems = stemsIn(drawables).toList();

      expect(beams, hasLength(2));
      for (final beam in beams) {
        expect(beam.points[0].x, closeTo(stems.first.to.x - halfStem, 1e-9));
        expect(beam.points[1].x, closeTo(stems.last.to.x + halfStem, 1e-9));
      }
    });
  });
}
