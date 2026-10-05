import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/hit.dart';
import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/support.dart' show hidePart;
import 'support/bars.dart';
import 'support/fake_measurer.dart';

SheetLayout sheetOf(Score score, {double width = 120}) =>
    SheetLayout(score, width: width, text: const FakeMeasurer());

/// Six bars on a treble and a bass staff, in three systems of two bars.
Score threeSystems() => after(beatsScore(6, clefs: [Clef.treble, Clef.bass]), [
  const SetBreak(MeasureId(3002), LayoutBreak.system),
  const SetBreak(MeasureId(3004), LayoutBreak.system),
]);

VoicePoint cursorAt(int bar, Moment offset, {int staff = 0}) => VoicePoint(
  staff: staffId(staff),
  voice: VoiceSlot.one,
  at: ScorePoint(barId(bar), offset),
);

RangeSelection rangeOf(
  ScorePoint from,
  ScorePoint to, {
  int top = 0,
  int bottom = 1,
}) => RangeSelection(
  from: from,
  to: to,
  top: staffId(top),
  bottom: staffId(bottom),
);

/// The box [index]'s system draws [ref] in, in sheet space.
Box headBox(SheetLayout layout, int index, EventRef ref) => layout
    .systemAt(index)
    .boundsOf(ElementOwner(ref))!
    .shift(
      0,
      layout.tops[index],
    );

double xOf(SheetLayout layout, int index, ScorePoint point) =>
    layout.systemAt(index).barOf(point.measure)!.time.xAt(point.offset);

/// Sides equal within a rounding error. The playhead's offset comes back
/// through seconds, and sheet space adds a system's top to its y.
void expectBox(Box? actual, Box expected) {
  expect(actual, isNotNull);
  expect(actual!.left, closeTo(expected.left, 1e-9));
  expect(actual.top, closeTo(expected.top, 1e-9));
  expect(actual.right, closeTo(expected.right, 1e-9));
  expect(actual.bottom, closeTo(expected.bottom, 1e-9));
}

/// The heads, the ledger lines, the stems and the flags [layout] draws on
/// system [index].
List<Drawable> notesOf(SheetLayout layout, int index) => [
  for (final drawable in layout.systemAt(index).drawables)
    if (drawable.ink
        case InkRole.notehead ||
            InkRole.ledgerLine ||
            InkRole.stem ||
            InkRole.flag)
      drawable,
];

/// Matches a drawable of [drawable]'s kind and ink at its place, whoever
/// owns it. A place is equal within a rounding error, since a system adds
/// its bar's x to a chord's own.
Matcher inkOf(Drawable drawable) {
  Matcher near(double value) => closeTo(value, 1e-9);
  return switch (drawable) {
    GlyphDraw(:final glyph, :final origin, :final bounds, :final ink) =>
      isA<GlyphDraw>()
          .having((d) => (d.glyph, d.ink, d.scale), 'glyph', (glyph, ink, 1.0))
          .having((d) => d.origin.x, 'x', near(origin.x))
          .having((d) => d.origin.y, 'y', near(origin.y))
          .having((d) => d.bounds.left, 'left', near(bounds.left))
          .having((d) => d.bounds.top, 'top', near(bounds.top))
          .having((d) => d.bounds.right, 'right', near(bounds.right))
          .having((d) => d.bounds.bottom, 'bottom', near(bounds.bottom)),
    LineDraw(:final from, :final to, :final thickness, :final ink) =>
      isA<LineDraw>()
          .having((d) => (d.ink, d.dash), 'ink', (ink, LineDash.solid))
          .having((d) => d.from.x, 'from x', near(from.x))
          .having((d) => d.from.y, 'from y', near(from.y))
          .having((d) => d.to.x, 'to x', near(to.x))
          .having((d) => d.to.y, 'to y', near(to.y))
          .having((d) => d.thickness, 'thickness', near(thickness)),
    _ => throw ArgumentError.value(
      drawable,
      'drawable',
      'Not a glyph or a line',
    ),
  };
}

NotePreview previewAt(
  int bar,
  Moment offset,
  int step, {
  int staff = 0,
  DurationBase base = DurationBase.quarter,
  NoteHead head = NoteHead.normal,
}) => NotePreview(
  staff: staffId(staff),
  at: ScorePoint(barId(bar), offset),
  staffStep: step,
  base: base,
  head: head,
);

void main() {
  group('a note preview', () {
    // On a treble staff the bottom line, step 0, is E4. A stem never ends
    // short of the middle line, so the stems of G3 and D6 are longer.
    for (final (pitch, step, value, ledgers, stem, flag) in const [
      ('G3', -5, NoteValue.quarter, 2, 'up', false),
      ('C4', -2, NoteValue.half, 1, 'up', false),
      ('D4', -1, NoteValue.eighth, 0, 'up', true),
      ('A4', 3, NoteValue.sixteenth, 0, 'up', true),
      ('B4', 4, NoteValue.whole, 0, null, false),
      ('B4', 4, NoteValue.quarter, 0, 'down', false),
      ('G5', 9, NoteValue.eighth, 0, 'down', true),
      ('A5', 10, NoteValue.half, 1, 'down', false),
      ('D6', 13, NoteValue.quarter, 2, 'down', false),
      ('D6', 13, NoteValue.whole, 2, null, false),
    ]) {
      test('draws the ${value.base.name} note that stands alone at $pitch: '
          'its head, its $ledgers ledger lines, '
          '${stem == null ? 'no stem' : 'its stem $stem'} and '
          '${flag ? 'its flag' : 'no flag'}', () {
        final layout = sheetOf(
          scoreOf([
            [
              staffOf([chordOf(1, pitch, value: value)]),
            ],
          ]),
        );
        final drawn = notesOf(layout, 0);
        Iterable<Drawable> of(InkRole ink) => drawn.where((d) => d.ink == ink);
        final head = of(InkRole.notehead).single;
        expect(of(InkRole.ledgerLine), hasLength(ledgers));
        expect(of(InkRole.flag), hasLength(flag ? 1 : 0));
        expect(
          [
            for (final line in of(InkRole.stem))
              line.bounds.top < head.bounds.top ? 'up' : 'down',
          ],
          [?stem],
        );

        expect(
          layout.previewIn(
            0,
            previewAt(0, Moment.zero, step, base: value.base),
          ),
          unorderedMatches(drawn.map(inkOf)),
        );
      });
    }

    test('between two notes has its head at the caret, on its step, and '
        'draws the head first', () {
      final layout = sheetOf(beatsScore(1));
      final staff = layout.systemAt(0).staves.single;

      final head = layout.previewIn(0, previewAt(0, at(3, 8), 6)).first;

      expect(
        (head as GlyphDraw).origin,
        SpPoint(
          layout.caretIn(0, cursorAt(0, at(3, 8)))!.left,
          staff.top + yOfStep(6),
        ),
      );
      expect(head.glyph, Glyph.noteheadBlack);
    });

    test('of a head of another kind draws that head, as a note of that '
        'kind is drawn', () {
      final layout = sheetOf(
        scoreOf([
          [
            staffOf([
              ChordEvent(
                id: const EventId(1),
                value: NoteValue.half,
                notes: Seq([
                  PitchedNote(
                    id: const NoteId(10),
                    pitch: Pitch.parse('B4'),
                    head: NoteHead.diamond,
                  ),
                ]),
              ),
            ]),
          ],
        ]),
      );

      expect(
        layout.previewIn(
          0,
          previewAt(
            0,
            Moment.zero,
            4,
            base: DurationBase.half,
            head: NoteHead.diamond,
          ),
        ),
        unorderedMatches(notesOf(layout, 0).map(inkOf)),
      );
    });

    test('tells where it is drawn in sheet space, which is the box of a '
        'note of its value at its place with its stem and its ledger lines, '
        'and nowhere on a hidden staff or in a bar the score lacks', () {
      final score = threeSystems();
      final layout = sheetOf(score);
      // Beat 2 of bar 3 on the bass staff, where B4 is three lines over it.
      final preview = previewAt(3, at(1, 4), 16, staff: 1);
      final note = eventRef(622, bar: 3);
      final head = NoteRef(note, const NoteId(6220));
      expect(
        layout.boundsOf(note)!.height,
        greaterThan(layout.boundsOf(head)!.height + 3),
      );

      expectBox(layout.boundsOfPreview(preview), layout.boundsOf(note)!);
      expect(sheetOf(hidePart(score, 1)).boundsOfPreview(preview), isNull);
      expect(layout.boundsOfPreview(previewAt(9, Moment.zero, 4)), isNull);
    });

    test('is drawn on the system of its bar alone, and not on a hidden '
        'staff or for a bar the score lacks', () {
      final score = threeSystems();
      final layout = sheetOf(score);
      final preview = previewAt(3, Moment.zero, 4, staff: 1);

      expect(
        [for (var i = 0; i < 3; i++) layout.previewIn(i, preview).isNotEmpty],
        [false, true, false],
      );
      expect(sheetOf(hidePart(score, 1)).previewIn(1, preview), isEmpty);
      expect(layout.previewIn(1, previewAt(9, Moment.zero, 4)), isEmpty);
    });

    test('has no ledger lines on a staff of one line', () {
      final layout = sheetOf(
        scoreOf([
          [
            staffOf([chordOf(1, 'B4')], lines: 1),
          ],
        ]),
      );

      expect(
        layout
            .previewIn(0, previewAt(0, Moment.zero, 12))
            .where((drawable) => drawable.ink == InkRole.ledgerLine),
        isEmpty,
      );
    });

    test('of a hit is a note at the hit, and equals one of the same '
        'place and head', () {
      final hit = SheetHit(
        staff: staffId(1),
        voice: VoiceSlot.two,
        at: ScorePoint(barId(2), at(1, 4)),
        staffStep: -3,
      );

      final preview = NotePreview.at(hit, base: DurationBase.half);

      expect(
        preview,
        previewAt(2, at(1, 4), -3, staff: 1, base: DurationBase.half),
      );
      expect(
        NotePreview.at(hit, head: NoteHead.cross),
        previewAt(2, at(1, 4), -3, staff: 1, head: NoteHead.cross),
      );
      expect(
        preview.hashCode,
        previewAt(2, at(1, 4), -3, staff: 1, base: DurationBase.half).hashCode,
      );
      for (final other in [
        previewAt(2, at(1, 4), -3, base: DurationBase.half),
        previewAt(1, at(1, 4), -3, staff: 1, base: DurationBase.half),
        previewAt(2, at(1, 2), -3, staff: 1, base: DurationBase.half),
        previewAt(2, at(1, 4), -2, staff: 1, base: DurationBase.half),
        previewAt(2, at(1, 4), -3, staff: 1),
        previewAt(
          2,
          at(1, 4),
          -3,
          staff: 1,
          base: DurationBase.half,
          head: NoteHead.cross,
        ),
      ]) {
        expect(preview, isNot(other));
      }
    });
  });

  group('overlays need no layout', () {
    late Score score;
    late SheetLayout layout;
    late PlaybackScript script;

    setUp(() {
      score = threeSystems();
      layout = sheetOf(score);
      script = PlaybackCompiler().compile(score);
      expect(layout.systemCount, 3);
      expect(layout.firstBarOf(1), barId(2));
      expect(layout.firstBarOf(2), barId(4));
    });

    test('caretOf, selectionBoxes and playheadAt return boxes for a cursor, '
        'an item selection and a range whose to is a bar end, and leave the '
        'layout identical', () {
      final before = [
        for (var i = 0; i < layout.systemCount; i++) layout.systemAt(i),
      ];
      final bassTop = layout.systemAt(1).staffOf(staffId(1))!.top;

      final caret = layout.caretOf(cursorAt(3, at(1, 4), staff: 1));
      expectBox(
        caret,
        Box(
          xOf(layout, 1, ScorePoint(barId(3), at(1, 4))),
          layout.tops[1] + bassTop,
          xOf(layout, 1, ScorePoint(barId(3), at(1, 4))),
          layout.tops[1] + bassTop + staffHeight,
        ),
      );

      final item = eventRef(602, bar: 3);
      expect(layout.selectionBoxes(ItemSelection(Seq([item]))), [
        headBox(layout, 1, item),
      ]);

      final range = rangeOf(
        ScorePoint(barId(2), at(1, 4)),
        ScorePoint(barId(3), at(1, 1)),
      );
      final boxes = layout.selectionBoxes(range);
      final end = layout.systemAt(1).barOf(barId(3))!;
      expectBox(
        boxes.single,
        Box(
          xOf(layout, 1, range.from),
          layout.tops[1] + layout.systemAt(1).staves.first.top,
          end.time.xAt(at(1, 1)),
          layout.tops[1] + bassTop + staffHeight,
        ),
      );
      expect(boxes.single.right, end.time.stops.last.$2);
      expect(boxes.single.right, lessThanOrEqualTo(end.right));

      final played = ScorePoint(barId(3), at(1, 2));
      final playhead = layout.playheadAt(
        script.pointAt(script.secondsAt(played)!)!,
      );
      expectBox(
        playhead,
        Box(
          xOf(layout, 1, played),
          layout.tops[1],
          xOf(layout, 1, played),
          layout.tops[1] + layout.heightOf(1),
        ),
      );

      for (final (i, system) in before.indexed) {
        expect(identical(layout.systemAt(i), system), isTrue);
      }
      expect(identical(layout.update(score), layout), isTrue);
    });

    test('a range across a system break gives one box per system', () {
      final range = rangeOf(
        ScorePoint(barId(1), at(1, 4)),
        ScorePoint(barId(5), at(1, 2)),
      );
      final boxes = layout.selectionBoxes(range);
      expect(boxes, hasLength(3));
      for (final (i, box) in boxes.indexed) {
        final system = layout.systemAt(i);
        expect(
          box.top,
          closeTo(layout.tops[i] + system.staves.first.top, 1e-9),
        );
        expect(
          box.bottom,
          closeTo(layout.tops[i] + system.staves.last.top + staffHeight, 1e-9),
        );
        expectBox(
          layout.selectionIn(i, range).single,
          box.shift(0, -layout.tops[i]),
        );
      }
      expect(boxes[0].left, xOf(layout, 0, range.from));
      expect(boxes[0].right, layout.systemAt(0).bars.last.right);
      for (final i in [1, 2]) {
        final first = layout.systemAt(i).bars.first;
        expect(boxes[i].left, first.time.xAt(Moment.zero));
        expect(boxes[i].left, greaterThan(first.left + 2));
      }
      expect(boxes[1].right, layout.systemAt(1).bars.last.right);
      expect(boxes[2].right, xOf(layout, 2, range.to));
    });

    test('a range over one staff alone spans only that staff', () {
      for (final staff in [0, 1]) {
        final range = rangeOf(
          ScorePoint(barId(0), Moment.zero),
          ScorePoint(barId(1), at(1, 1)),
          top: staff,
          bottom: staff,
        );
        final top = layout.systemAt(0).staffOf(staffId(staff))!.top;
        final box = layout.selectionBoxes(range).single;
        expect(box.top, closeTo(layout.tops[0] + top, 1e-9));
        expect(box.bottom, closeTo(layout.tops[0] + top + staffHeight, 1e-9));
      }
    });

    test('a sounding ref on a hidden staff gives no box', () {
      final hidden = hidePart(score, 1);
      final layout = sheetOf(hidden);
      final ref = eventRef(21);
      expect(
        PlaybackCompiler().compile(hidden).notesBetween(0, 0.01),
        contains(predicate<PlaybackNote>((note) => note.source == ref)),
      );
      expect(layout.systemOfRef(ref), 0);
      expect(layout.boundsOf(ref), isNull);
      expect(layout.selectionBoxes(ItemSelection(Seq([ref]))), isEmpty);
      expect(layout.caretOf(cursorAt(0, Moment.zero, staff: 1)), isNull);
      expect(
        layout.selectionBoxes(
          rangeOf(
            ScorePoint(barId(0), Moment.zero),
            ScorePoint(barId(1), at(1, 1)),
            top: 1,
          ),
        ),
        isEmpty,
      );
    });

    test('a range whose to is offset 0 of the first bar of the next system '
        'gives no box on that system', () {
      final range = rangeOf(
        ScorePoint(barId(0), Moment.zero),
        ScorePoint(barId(2), Moment.zero),
      );
      expect(layout.selectionIn(1, range), isEmpty);
      final box = layout.selectionBoxes(range).single;
      expect(box.left, xOf(layout, 0, range.from));
      expect(box.right, layout.systemAt(0).bars.last.right);
      expect(
        box.top,
        closeTo(layout.tops[0] + layout.systemAt(0).staves.first.top, 1e-9),
      );
    });

    test('a range whose to is offset 0 of a later bar of the same system '
        'ends where the bar before ends, short of the later bar\'s clef and '
        'key change', () {
      final keyed = sheetOf(
        after(threeSystems(), [
          SetKey(from: barId(1), key: const KeySignature(2)),
          SetClef(
            staff: staffId(0),
            at: ScorePoint(barId(1), Moment.zero),
            clef: Clef.alto,
          ),
        ]),
      );
      final from = ScorePoint(barId(0), Moment.zero);
      final box = keyed
          .selectionBoxes(rangeOf(from, ScorePoint(barId(1), Moment.zero)))
          .single;
      final signs = keyed
          .systemAt(0)
          .drawables
          .whereType<GlyphDraw>()
          .where(
            (d) =>
                d.owner == null &&
                (d.glyph == Glyph.accidentalSharp ||
                    d.glyph == Glyph.cClefChange),
          );
      expect(signs.map((d) => d.glyph), contains(Glyph.cClefChange));
      expect(signs.map((d) => d.glyph), contains(Glyph.accidentalSharp));
      for (final sign in signs) {
        expect(box.right, lessThanOrEqualTo(sign.bounds.left));
      }
      expect(
        box,
        keyed
            .selectionBoxes(rangeOf(from, ScorePoint(barId(0), at(1, 1))))
            .single,
      );
    });

    test('a range whose to is offset 0 of a later bar of the next system '
        'gives that system a box ending at that bar\'s start', () {
      final range = rangeOf(
        ScorePoint(barId(0), Moment.zero),
        ScorePoint(barId(3), Moment.zero),
      );
      final boxes = layout.selectionBoxes(range);
      expect(boxes, hasLength(2));
      expect(
        boxes[1].left,
        layout.systemAt(1).bars.first.time.xAt(Moment.zero),
      );
      expect(boxes[1].right, xOf(layout, 1, ScorePoint(barId(2), at(1, 1))));
    });

    test('a range that holds nothing gives no box, at the start of a bar '
        'too, and neither does one that ends before it starts', () {
      for (final point in [
        ScorePoint(barId(0), Moment.zero),
        ScorePoint(barId(0), at(1, 4)),
        ScorePoint(barId(1), Moment.zero),
        ScorePoint(barId(2), Moment.zero),
        ScorePoint(barId(3), Moment.zero),
      ]) {
        expect(
          layout.selectionBoxes(rangeOf(point, point)),
          isEmpty,
          reason: 'from and to at $point',
        );
      }
      expect(
        layout.selectionBoxes(
          rangeOf(
            ScorePoint(barId(1), at(1, 2)),
            ScorePoint(barId(1), at(1, 4)),
          ),
        ),
        isEmpty,
      );
    });

    test('a ref made before SetMeter moved its event to another bar, on '
        'another system, still gives the event\'s box', () {
      final old = eventRef(204, bar: 1);
      final rebarred = after(beatsScore(4), [
        const SetMeter(from: MeasureId(3000), meter: Meter.threeFour),
      ]);
      final layout = sheetOf(rebarred, width: 40);
      final found = rebarred.lookup(old)!;
      expect(found.ref.measure, isNot(old.measure));
      final index = layout.systemOfRef(old)!;
      expect(index, layout.systemOf(found.ref.measure));
      expect(index, isNot(layout.systemOf(old.measure)));
      expect(layout.boundsOf(old), headBox(layout, index, found.ref));
      expect(layout.boundsOf(found.ref), layout.boundsOf(old));
      expect(layout.selectionBoxes(ItemSelection(Seq([old]))), [
        layout.boundsOf(old),
      ]);
    });

    test(
      'a cursor, an event or a playhead on a bar not in the score gives '
      'no box, and an event still in the score is found from a stale bar',
      () {
        const gone = MeasureId(3999);
        expect(
          layout.caretOf(
            VoicePoint(
              staff: staffId(0),
              voice: VoiceSlot.one,
              at: const ScorePoint(gone, Moment.zero),
            ),
          ),
          isNull,
        );
        expect(
          layout.boundsOf(
            const EventRef(
              measure: gone,
              staff: StaffId(2000),
              id: EventId(999),
            ),
          ),
          isNull,
        );
        expect(
          layout.boundsOf(
            const EventRef(measure: gone, staff: StaffId(2000), id: EventId(1)),
          ),
          layout.boundsOf(eventRef(1)),
        );
        expect(
          layout.playheadAt(
            const PlaybackPoint(
              bar: PlayedBar(measure: gone, pass: 1, start: 0, end: 1),
              offset: 0,
            ),
          ),
          isNull,
        );
      },
    );
  });

  group('the playhead', () {
    test('moves right within a system except at the repeat\'s jump, and '
        'lands on each note\'s x at that note\'s second', () {
      final score = after(beatsScore(6), [
        const SetRepeatStart(MeasureId(3000), start: true),
        const SetRepeatEnd(MeasureId(3002), RepeatEnd()),
        const SetBreak(MeasureId(3003), LayoutBreak.system),
      ]);
      final layout = sheetOf(score);
      expect(layout.systemCount, 2);
      final script = PlaybackCompiler().compile(score);

      var leftward = 0;
      final visited = <int>{};
      (int, double)? previous;
      for (var ms = 0; ms < script.totalSeconds * 1000; ms += 10) {
        final point = script.pointAt(ms / 1000)!;
        final box = layout.playheadAt(point)!;
        final index = layout.systemOf(point.bar.measure)!;
        visited.add(index);
        expect(box.left, box.right);
        expect(box.top, layout.tops[index]);
        expect(box.bottom, layout.tops[index] + layout.heightOf(index));
        if (previous case (final lastIndex, final lastX)
            when lastIndex == index) {
          if (box.left < lastX) {
            leftward++;
            expect(point.bar.pass, 2);
            expect(point.bar.measure, barId(0));
          }
        }
        previous = (index, box.left);
      }
      expect(visited, {0, 1});
      expect(leftward, 1);

      final notes = script.notesBetween(0, script.totalSeconds).toList();
      expect(notes, hasLength(36));
      for (final note in notes) {
        final timed = score.lookup(note.source)!;
        final index = layout.systemOf(timed.ref.measure)!;
        final box = layout.playheadAt(script.pointAt(note.start)!)!;
        expect(
          box.left,
          closeTo(
            xOf(layout, index, ScorePoint(timed.ref.measure, timed.onset)),
            1e-6,
          ),
        );
      }
    });
  });
}
