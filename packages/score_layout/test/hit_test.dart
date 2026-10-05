import 'package:score_layout/src/drawable.dart';
import 'package:score_layout/src/geometry.dart';
import 'package:score_layout/src/glyphs.dart';
import 'package:score_layout/src/hit.dart';
import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/style.dart';
import 'package:score_layout/src/system_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import '../../score_model/test/support.dart' show hidePart;
import 'support/bars.dart';
import 'support/fake_measurer.dart';

const EngravingStyle style = EngravingStyle.standard;

SheetLayout sheetOf(Score score, {double width = 120}) =>
    SheetLayout(score, width: width, text: const FakeMeasurer());

/// The one-staff, one-bar sheet of [one] and [two], wide enough that no two
/// onsets of a bar come within two spaces of each other.
SheetLayout barSheet(List<VoiceItem> one, {List<VoiceItem> two = const []}) =>
    sheetOf(
      scoreOf([
        [staffOf(one, two: two)],
      ]),
    );

NoteRef noteRef(int event, {int bar = 0}) =>
    NoteRef(eventRef(event, bar: bar), NoteId(event * 10));

SpPoint centreOf(Box box) =>
    SpPoint((box.left + box.right) / 2, (box.top + box.bottom) / 2);

/// The notehead [owner] draws in [system].
GlyphDraw headOf(SystemLayout system, Owner owner) =>
    system.drawables.whereType<GlyphDraw>().singleWhere(
      (draw) => draw.owner == owner && draw.glyph.name.startsWith('notehead'),
    );

SpPoint sheetPoint(SheetLayout layout, int system, SpPoint local) =>
    local.shift(0, layout.tops[system]);

/// A kind of single staff the hit round trip runs on.
typedef StaffKind = ({String name, Clef clef, int lines, Instrument kit});

/// A kit with a drum at every step from -6 to 14, so that each step of a
/// percussion staff has a tone to draw and to enter.
final Instrument fullKit = Instrument(
  key: 'kit',
  program: 0,
  bank: 128,
  clef: Clef.percussion,
  drums: [
    for (var step = -6; step <= 14; step++)
      DrumSound(
        name: 'd$step',
        position: Clef.percussion.naturalAt(step),
        midiKey: 41 + step,
      ),
  ],
);

final List<StaffKind> kinds = [
  (name: 'treble', clef: Clef.treble, lines: 5, kit: piano),
  (name: 'bass', clef: Clef.bass, lines: 5, kit: piano),
  (name: 'alto', clef: Clef.alto, lines: 5, kit: piano),
  (name: 'percussion', clef: Clef.percussion, lines: 5, kit: fullKit),
  (name: 'one-line percussion', clef: Clef.percussion, lines: 1, kit: fullKit),
];

const List<int> steps = [
  -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, //
  5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
];

ChordEvent noteAt(StaffKind kind, int step, int id) => ChordEvent(
  id: EventId(id),
  value: NoteValue.quarter,
  notes: Seq([
    if (kind.kit.isPercussion)
      DrumNote(id: NoteId(id * 10), drum: Drum('d$step'))
    else
      PitchedNote(id: NoteId(id * 10), pitch: kind.clef.naturalAt(step)),
  ]),
);

/// Three systems of six bars, each system holding a quarter on every step
/// from -6 to 14 and three more on step 4, on one [kind] staff.
SheetLayout ladder(StaffKind kind) {
  final laddered = [...steps, 4, 4, 4];
  final score = scoreOf([
    for (var bar = 0; bar < 18; bar++)
      [
        staffOf(
          [
            for (var beat = 0; beat < 4; beat++)
              noteAt(kind, laddered[(bar % 6) * 4 + beat], bar * 10 + beat + 1),
          ],
          clef: kind.clef,
          lines: kind.lines,
          instrument: kind.kit,
        ),
      ],
  ]);
  final layout = sheetOf(
    after(score, [
      SetBreak(barId(6), LayoutBreak.system),
      SetBreak(barId(12), LayoutBreak.system),
    ]),
    width: 160,
  );
  expect(layout.systemCount, 3);
  return layout;
}

/// The noteheads drawn at [y] in [system], with the tone each draws.
List<(GlyphDraw, Tone)> headsAt(Score score, SystemLayout system, double y) => [
  for (final draw in system.drawables.whereType<GlyphDraw>())
    if (draw.owner case ElementOwner(:final NoteRef ref)
        when draw.glyph.name.startsWith('notehead') &&
            (draw.origin.y - y).abs() < 1e-9)
      (
        draw,
        (score.lookup(ref.event)!.event as ChordEvent).notes
            .firstWhere((note) => note.id == ref.note)
            .tone,
      ),
];

/// A system of nothing but [drawables], for the target ranking.
SystemLayout bare(List<Drawable> drawables) => SystemLayout(
  drawables: drawables,
  bars: const [],
  staves: const [],
  width: 10,
  height: 10,
);

void main() {
  group('the hit round trip', () {
    for (final kind in kinds) {
      for (final (index, position) in ['first', 'middle', 'last'].indexed) {
        late SheetLayout layout;
        late SystemLayout system;
        late PlacedStaff staff;

        setUp(() {
          layout = ladder(kind);
          system = layout.systemAt(index);
          staff = system.staves.single;
        });

        test('a tap at each step of a ${kind.name} staff on the $position '
            'system reports that step', () {
          for (final step in steps) {
            final heads = headsAt(layout.score, system, staff.yOf(step));
            expect(heads, isNotEmpty, reason: 'step $step');
            for (final (head, _) in heads) {
              final hit = layout.hitTest(
                sheetPoint(layout, index, centreOf(head.bounds)),
              );
              expect(hit, isNotNull, reason: 'step $step');
              expect(hit!.staffStep, step, reason: 'step $step');
              expect(hit.staff, staff.staff, reason: 'step $step');
            }
          }
        });

        test('the tone of each tapped step of a ${kind.name} staff on the '
            '$position system is the tone whose head was drawn there', () {
          for (final step in steps) {
            for (final (head, tone) in headsAt(
              layout.score,
              system,
              staff.yOf(step),
            )) {
              final hit = layout.hitTest(
                sheetPoint(layout, index, centreOf(head.bounds)),
              )!;
              expect(
                layout.score.toneForStaffStep(hit.staff, hit.at, step),
                tone,
                reason: 'step $step',
              );
            }
          }
        });
      }
    }

    test('a treble staff reads E4 at step 0 and a bass staff G2', () {
      for (final (kind, tone) in [
        (kinds[0], Pitch.parse('E4')),
        (kinds[1], Pitch.parse('G2')),
      ]) {
        final layout = ladder(kind);
        final staff = layout.systemAt(0).staves.single;
        final hit = layout.hitTest(SpPoint(20, layout.tops[0] + staff.yOf(0)))!;
        expect(hit.staffStep, 0);
        expect(layout.score.toneForStaffStep(hit.staff, hit.at, 0), tone);
      }
    });

    test('a one-line staff draws its line at step 4', () {
      final layout = ladder(kinds.last);
      final system = layout.systemAt(0);
      final lines = system.drawables
          .whereType<LineDraw>()
          .where((line) => line.ink == InkRole.staffLine)
          .map((line) => line.from.y)
          .toSet();
      expect(lines, {system.staves.single.yOf(4)});
    });

    test('a tap on a notehead gives its NoteRef', () {
      final layout = barSheet([
        chordOf(1, 'E4'),
        chordOf(2, 'G4'),
        chordOf(3, 'B4'),
        chordOf(4, 'D5'),
      ]);
      final system = layout.systemAt(0);
      for (final id in [1, 2, 3, 4]) {
        final head = headOf(system, ElementOwner(noteRef(id)));
        final hit = layout.hitTest(
          sheetPoint(layout, 0, centreOf(head.bounds)),
        );
        expect(hit!.target, ElementOwner(noteRef(id)), reason: 'note $id');
        expect(hit.voice, VoiceSlot.one);
        expect(hit.at, ScorePoint(barId(0), at(id - 1, 4)));
      }
    });

    test('a tap on each head of a chord in thirds, with a finger\'s reach '
        'over the heads beside it, gives that head', () {
      final layout = barSheet([
        chordOf(1, 'E4 G4 B4'),
        chordOf(2, 'E4', value: dottedHalf),
      ]);
      final system = layout.systemAt(0);
      for (final note in [10, 11, 12]) {
        final owner = ElementOwner(NoteRef(eventRef(1), NoteId(note)));
        final hit = layout.hitTest(
          sheetPoint(layout, 0, centreOf(headOf(system, owner).bounds)),
          reach: 1,
        );
        expect(hit!.target, owner, reason: 'note $note');
      }
    });

    test('a tap on a voice-two note gives voice two and a time in voice '
        'two', () {
      final layout = barSheet(
        [chordOf(1, 'G5', value: half), chordOf(2, 'G5', value: half)],
        two: [
          chordOf(3, 'C4', value: half),
          chordOf(4, 'C4', value: half),
        ],
      );
      final system = layout.systemAt(0);
      final head = headOf(system, ElementOwner(noteRef(4)));
      final hit = layout.hitTest(sheetPoint(layout, 0, centreOf(head.bounds)));
      expect(hit!.voice, VoiceSlot.two);
      expect(hit.target, ElementOwner(noteRef(4)));
      expect(hit.at, ScorePoint(barId(0), at(1, 2)));
    });

    test('a tap on a grace head gives the principal\'s EventRef', () {
      final layout = barSheet([
        chordOf(1, 'E4', graces: [graceOf(5, 'D4')]),
        chordOf(2, 'E4'),
        chordOf(3, 'E4', value: half),
      ]);
      final system = layout.systemAt(0);
      final grace = system.drawables.whereType<GlyphDraw>().singleWhere(
        (draw) =>
            draw.owner == ElementOwner(eventRef(1)) &&
            draw.glyph.name.startsWith('notehead'),
      );
      expect(grace.scale, lessThan(1));
      final hit = layout.hitTest(sheetPoint(layout, 0, centreOf(grace.bounds)));
      expect(hit!.target, ElementOwner(eventRef(1)));
      expect(
        hit.target,
        isA<ElementOwner>().having((o) => o.ref, 'ref', isA<EventRef>()),
      );
      expect(hit.at, ScorePoint(barId(0), Moment.zero));
    });

    test('a tap on a head drawn beside its stem, or on a grace head, gives '
        'its chord\'s onset on the finest grid', () {
      final layout = barSheet([
        chordOf(1, 'E4'),
        chordOf(2, 'E4 F4'),
        chordOf(3, 'E4', graces: [graceOf(6, 'D4')]),
        chordOf(4, 'E4'),
      ]);
      final system = layout.systemAt(0);
      final bar = system.bars.single;
      final beside = headOf(
        system,
        ElementOwner(NoteRef(eventRef(2), const NoteId(21))),
      );
      final grace = system.drawables.whereType<GlyphDraw>().singleWhere(
        (draw) =>
            draw.owner == ElementOwner(eventRef(3)) &&
            draw.scale < 1 &&
            draw.glyph.name.startsWith('notehead'),
      );
      for (final (head, onset) in [(beside, at(1, 4)), (grace, at(1, 2))]) {
        final centre = centreOf(head.bounds);
        expect((centre.x - bar.time.xAt(onset)).abs(), greaterThan(1));
        final hit = layout.hitTest(
          sheetPoint(layout, 0, centre),
          grid: DurationBase.oneTwentyEighth,
        );
        expect(hit!.at, ScorePoint(barId(0), onset), reason: '$onset');
      }
    });

    test('a tap inside a triplet of eighths, at an x that is no onset, gives '
        'a time where a sixteenth enters', () {
      final layout = barSheet([
        Tuplet(
          id: const TupletId(50),
          ratio: TupletRatio.triplet,
          unit: NoteValue.eighth,
          members: Seq([
            chordOf(1, 'E4', value: eighth),
            chordOf(2, 'E4', value: eighth),
            chordOf(3, 'E4', value: eighth),
          ]),
        ),
        chordOf(4, 'E4'),
        chordOf(5, 'E4', value: half),
      ]);
      final system = layout.systemAt(0);
      final bar = system.bars.single;
      final onsets = voiceTimes(
        layout.score.measureView(barId(0)),
        staffId(0),
        VoiceSlot.one,
      )!.onsets;
      final x = (bar.time.xAt(Moment.zero) + bar.time.xAt(at(1, 12))) / 2;
      expect(
        bar.time.xAt(at(1, 12)) - bar.time.xAt(Moment.zero),
        greaterThan(2),
      );

      final hit = layout.hitTest(
        sheetPoint(layout, 0, SpPoint(x, system.staves.single.yOf(4))),
      );
      expect(hit!.target, isNull);
      expect(onsets, isNot(contains(hit.at.offset)));
      expect(hit.at, ScorePoint(barId(0), at(1, 24)));
      final entered = EditSession.start(layout.score).run(
        EnterNote(
          at: VoicePoint(staff: hit.staff, voice: hit.voice, at: hit.at),
          tone: Pitch.parse('F4'),
          value: sixteenth,
        ),
      );
      expect(entered, isA<Applied>());
    });

    test('a tap on a voice-two rest, in a bar where only voice two has a '
        'triplet, gives voice two and a time on the triplet\'s grid', () {
      final layout = barSheet(
        [chordOf(1, 'G5', value: half), chordOf(2, 'G5', value: half)],
        two: [
          Tuplet(
            id: const TupletId(50),
            ratio: TupletRatio.triplet,
            unit: NoteValue.eighth,
            members: Seq([
              chordOf(3, 'C4', value: eighth),
              restOf(4, eighth),
              chordOf(5, 'C4', value: eighth),
            ]),
          ),
          chordOf(6, 'C4'),
          chordOf(7, 'C4', value: half),
        ],
      );
      final system = layout.systemAt(0);
      final rest = system.drawables.whereType<GlyphDraw>().singleWhere(
        (draw) => draw.owner == ElementOwner(eventRef(4)),
      );
      final hit = layout.hitTest(sheetPoint(layout, 0, centreOf(rest.bounds)));
      expect(hit!.voice, VoiceSlot.two);
      expect(hit.target, ElementOwner(eventRef(4)));
      expect(hit.at, ScorePoint(barId(0), at(1, 12)));

      final bar = system.bars.single;
      expect(
        entryPoints(
          bar.length,
          voiceTimes(
            layout.score.measureView(barId(0)),
            staffId(0),
            VoiceSlot.two,
          ),
          DurationBase.sixteenth,
        ),
        contains(at(1, 12)),
      );
      expect(
        entryPoints(
          bar.length,
          voiceTimes(
            layout.score.measureView(barId(0)),
            staffId(0),
            VoiceSlot.one,
          ),
          DurationBase.sixteenth,
        ),
        isNot(contains(at(1, 12))),
      );
    });

    test('a tap in a slur\'s box away from its line has no target, and one '
        'near its line has the slur', () {
      final score = withSlurOver(
        scoreOf([
          [
            staffOf([
              chordOf(1, 'B4'),
              chordOf(2, 'B4'),
              chordOf(3, 'B4'),
              chordOf(4, 'B4'),
            ]),
          ],
        ]),
      );
      final layout = sheetOf(score);
      final system = layout.systemAt(0);
      final slur = system.drawables.whereType<CurveDraw>().single;
      expect(slur.owner, const SpannerOwner(SpannerId(900)));
      final apex = slur.pointAt(0.5);
      final inBox = SpPoint(apex.x, slur.bounds.bottom - 0.05);
      expect(slur.bounds.contains(inBox), isTrue);
      expect(slur.distanceTo(inBox), greaterThan(0.25));
      expect(slur.bounds.height, greaterThan(1));

      final under = layout.hitTest(sheetPoint(layout, 0, inBox), reach: 0.25);
      expect(under!.target, isNull);
      expect(under.staff, staffId(0));
      final bar = system.bars.single;
      final voice = voiceTimes(
        layout.score.measureView(barId(0)),
        staffId(0),
        VoiceSlot.one,
      )!;
      expect(
        voice.onsets.map((onset) => (bar.time.xAt(onset) - apex.x).abs()),
        everyElement(greaterThan(1)),
      );
      expect(under.at.measure, barId(0));
      expect(under.at.offset > at(1, 4), isTrue);
      expect(under.at.offset < at(1, 2), isTrue);
      expect(
        entryPoints(bar.length, voice, DurationBase.sixteenth),
        contains(under.at.offset),
      );

      final near = layout.hitTest(sheetPoint(layout, 0, apex), reach: 0.25);
      expect(near!.target, const SpannerOwner(SpannerId(900)));
    });

    test('a tap within reach of a stem gives its EventRef, and one out of '
        'reach nothing', () {
      final layout = barSheet([
        chordOf(1, 'E4'),
        chordOf(2, 'E4', value: dottedHalf),
      ]);
      final system = layout.systemAt(0);
      final stem = system.drawables.whereType<LineDraw>().singleWhere(
        (line) =>
            line.owner == ElementOwner(eventRef(1)) && line.from.x == line.to.x,
      );
      final top = stem.from.y < stem.to.y ? stem.from.y : stem.to.y;
      final beside = SpPoint(stem.from.x + 0.3, top + 0.5);

      final within = layout.hitTest(sheetPoint(layout, 0, beside), reach: 0.5);
      expect(within!.target, ElementOwner(eventRef(1)));
      expect(
        within.target,
        isA<ElementOwner>().having((o) => o.ref, 'ref', isA<EventRef>()),
      );

      final without = layout.hitTest(sheetPoint(layout, 0, beside));
      expect(without!.target, isNull);
    });

    test('a tap on the third stem of a beamed group gives the third event, '
        'and the first event\'s bounds stop short of it', () {
      final layout = barSheet([
        chordOf(1, 'E4', value: eighth),
        chordOf(2, 'E4', value: eighth),
        chordOf(3, 'E4', value: eighth),
        chordOf(4, 'E4', value: eighth),
        chordOf(5, 'E4', value: half),
      ]);
      final system = layout.systemAt(0);
      final stems =
          system.drawables
              .whereType<LineDraw>()
              .where((line) => line.from.x == line.to.x && line.owner != null)
              .toList()
            ..sort((a, b) => a.from.x.compareTo(b.from.x));
      expect(stems, hasLength(5));
      final third = stems[2];
      final middle = SpPoint(third.from.x, (third.from.y + third.to.y) / 2);

      final hit = layout.hitTest(sheetPoint(layout, 0, middle), reach: 0.5);
      expect(hit!.target, ElementOwner(eventRef(3)));
      expect(
        system.boundsOf(ElementOwner(eventRef(1)))!.right,
        lessThan(system.boundsOf(ElementOwner(eventRef(2)))!.left),
      );
    });

    test('a triplet\'s number and bracket belong to no event, so a tap on '
        'the number has no target and the first event\'s bounds stop short '
        'of the last', () {
      final layout = barSheet([
        Tuplet(
          id: const TupletId(50),
          ratio: TupletRatio.triplet,
          unit: NoteValue.quarter,
          members: Seq([
            for (var i = 1; i <= 3; i++) chordOf(i, 'E4'),
          ]),
        ),
        chordOf(4, 'E4', value: half),
      ]);
      final system = layout.systemAt(0);
      final number = system.drawables.whereType<GlyphDraw>().singleWhere(
        (draw) => draw.glyph.name == 'tuplet3',
      );
      final centre = SpPoint(
        (number.bounds.left + number.bounds.right) / 2,
        (number.bounds.top + number.bounds.bottom) / 2,
      );

      final hit = layout.hitTest(
        sheetPoint(layout, 0, centre),
      );
      expect(number.owner, isNull);
      expect(hit!.target, isNull);
      expect(
        system.boundsOf(ElementOwner(eventRef(1)))!.right,
        lessThan(system.boundsOf(ElementOwner(eventRef(3)))!.left),
      );
    });

    test('a tap in the gap between two systems gives a hit on the nearer '
        'one', () {
      final layout = sheetOf(beatsScore(4), width: 40);
      expect(layout.systemCount, greaterThan(1));
      final gap = style.systemGap;
      final bottom = layout.tops[0] + layout.heightOf(0);
      expect(layout.tops[1] - bottom, gap);

      final lower = layout.hitTest(SpPoint(20, layout.tops[1] - gap / 4));
      expect(layout.systemOf(lower!.at.measure), 1);
      final upper = layout.hitTest(SpPoint(20, bottom + gap / 4));
      expect(layout.systemOf(upper!.at.measure), 0);
    });

    test('between two staves of one system, a tap nearer the lower staff\'s '
        'middle line gives the lower staff', () {
      final layout = sheetOf(
        beatsScore(1, clefs: const [Clef.treble, Clef.bass]),
      );
      final [upper, lower] = layout.systemAt(0).staves;
      final middle = (upper.top + 2 + lower.top + 2) / 2;

      final below = layout.hitTest(SpPoint(20, layout.tops[0] + middle + 0.25));
      expect(below!.staff, lower.staff);
      final above = layout.hitTest(SpPoint(20, layout.tops[0] + middle - 0.25));
      expect(above!.staff, upper.staff);
    });

    test('a tap on a head drawn nearer the next staff\'s middle line gives '
        'the head\'s staff, step and tone', () {
      final layout = sheetOf(
        scoreOf([
          [
            staffOf([chordOf(1, 'F2', value: whole)]),
            staffOf([chordOf(2, 'C3', value: whole)], clef: Clef.bass),
          ],
        ]),
      );
      final system = layout.systemAt(0);
      final [upper, lower] = system.staves;
      final head = headOf(system, ElementOwner(noteRef(1)));
      final y = centreOf(head.bounds).y;
      expect((lower.top + 2 - y).abs(), lessThan((upper.top + 2 - y).abs()));

      final hit = layout.hitTest(sheetPoint(layout, 0, centreOf(head.bounds)))!;
      expect(hit.target, ElementOwner(noteRef(1)));
      expect(hit.staff, upper.staff);
      expect(hit.staffStep, -13);
      expect(
        layout.score.toneForStaffStep(hit.staff, hit.at, hit.staffStep),
        Pitch.parse('F2'),
      );
    });

    test('a tap on the clef that starts a system snaps to its bar\'s first '
        'point', () {
      final layout = barSheet([chordOf(1, 'E4', value: whole)]);
      final system = layout.systemAt(0);
      final clef = system.drawables.whereType<GlyphDraw>().firstWhere(
        (draw) => draw.glyph.name.startsWith('gClef'),
      );
      final hit = layout.hitTest(sheetPoint(layout, 0, centreOf(clef.bounds)));
      expect(hit!.target, isNull);
      expect(hit.at, ScorePoint(barId(0), Moment.zero));
    });

    test('a tap on a clef change before a barline gives the bar before, as '
        'a tap on that barline does, and a tap on a courtesy clef gives the '
        'system\'s last bar', () {
      final layout = sheetOf(
        after(beatsScore(3), [
          for (final (bar, clef) in [(1, Clef.bass), (2, Clef.treble)])
            SetClef(
              staff: staffId(0),
              at: ScorePoint(barId(bar), Moment.zero),
              clef: clef,
            ),
          SetBreak(barId(2), LayoutBreak.system),
        ]),
      );
      final system = layout.systemAt(0);
      Box clefOf(Glyph glyph) => system.drawables
          .whereType<GlyphDraw>()
          .singleWhere((draw) => draw.glyph == glyph)
          .bounds;
      final changed = clefOf(Glyph.fClefChange);
      final courtesy = clefOf(Glyph.gClefChange);
      final barline = system.drawables.whereType<LineDraw>().singleWhere(
        (line) =>
            line.owner == null &&
            line.from.x == line.to.x &&
            line.from.x > changed.right &&
            line.from.x < system.bars[1].left,
      );
      SheetHit hitAt(double x) => layout.hitTest(
        sheetPoint(layout, 0, SpPoint(x, centreOf(changed).y)),
      )!;

      final onClef = hitAt(centreOf(changed).x);
      expect(system.bars, hasLength(2));
      expect(onClef.target, isNull);
      expect(onClef.at.measure, barId(0));
      expect(onClef.at, hitAt(barline.from.x).at);
      expect(hitAt(centreOf(courtesy).x).at.measure, barId(1));
    });

    test('a tap past half a system gap above the first system or below the '
        'last gives nothing, and one within it the system', () {
      final layout = sheetOf(beatsScore(4), width: 40);
      final gap = style.systemGap;
      final last = layout.systemCount - 1;
      final bottom = layout.tops[last] + layout.heightOf(last);

      expect(layout.hitTest(SpPoint(20, layout.tops[0] - gap)), isNull);
      expect(layout.hitTest(SpPoint(20, bottom + gap)), isNull);
      final first = layout.hitTest(SpPoint(20, layout.tops[0] - gap / 4));
      expect(layout.systemOf(first!.at.measure), 0);
      final end = layout.hitTest(SpPoint(20, bottom + gap / 4));
      expect(layout.systemOf(end!.at.measure), last);
    });

    test('a tap right of the last bar gives the last bar, and left of the '
        'first the first', () {
      final layout = sheetOf(beatsScore(2));
      final system = layout.systemAt(0);
      expect(system.bars, hasLength(2));
      final y = layout.tops[0] + system.staves.single.yOf(4);

      final left = layout.hitTest(SpPoint(0, y));
      expect(left!.at.measure, system.bars.first.measure);
      final right = layout.hitTest(SpPoint(system.width + 1, y));
      expect(right!.at.measure, system.bars.last.measure);
    });
  });

  group('the system readers', () {
    test('barOf finds a system\'s bar by id and gives null for a bar of '
        'another system', () {
      final layout = sheetOf(beatsScore(4), width: 40);
      final first = layout.systemAt(0);
      final second = layout.systemAt(1);
      expect(first.barOf(barId(0))!.measure, barId(0));
      expect(first.barOf(second.bars.first.measure), isNull);
      expect(second.barOf(barId(0)), isNull);
    });

    test('staffOf finds a visible staff by id and gives null for a hidden '
        'one', () {
      final score = beatsScore(1, clefs: const [Clef.treble, Clef.bass]);
      final system = sheetOf(score).systemAt(0);
      expect(system.staffOf(staffId(1))!.staff, staffId(1));
      expect(system.staffOf(staffId(2)), isNull);

      final hidden = sheetOf(hidePart(score, 1)).systemAt(0);
      expect(hidden.staves.map((s) => s.staff), [staffId(0)]);
      expect(hidden.staffOf(staffId(1)), isNull);
    });

    test('stepAt undoes yOf on every step and rounds to the nearest', () {
      const staff = PlacedStaff(staff: StaffId(1), top: 7.5, lines: 5);
      for (final step in steps) {
        expect(staff.stepAt(staff.yOf(step)), step, reason: 'step $step');
        expect(staff.stepAt(staff.yOf(step) + 0.2), step, reason: 'step $step');
        expect(staff.stepAt(staff.yOf(step) - 0.2), step, reason: 'step $step');
      }
      expect(staff.yOf(0), 11.5);
      expect(staff.yOf(8), 7.5);
    });

    test('xAt is linear between stops and xAtWholeNotes clamps past the '
        'last', () {
      final time = TimeAxis([
        (Moment.zero, 10),
        (at(1, 4), 14),
        (at(1, 2), 22),
        (at(1, 1), 30),
      ]);
      expect(time.xAt(Moment.zero), 10);
      expect(time.xAt(at(1, 8)), 12);
      expect(time.xAt(at(3, 8)), 18);
      expect(time.xAt(at(1, 1)), 30);
      expect(time.xAtWholeNotes(0.75), 26);
      expect(time.xAtWholeNotes(1.5), 30);
    });

    test('nearest picks the candidate nearest in x, and the earlier on a '
        'tie', () {
      final time = TimeAxis([(Moment.zero, 0), (at(1, 1), 16)]);
      final candidates = [Moment.zero, at(1, 4), at(1, 2)];
      expect(time.nearest(candidates, 5), at(1, 4));
      expect(time.nearest(candidates, 1), Moment.zero);
      expect(time.nearest(candidates, 6), at(1, 4));
      expect(time.nearest(candidates, 15), at(1, 2));
    });

    test('barAt gives the bar holding x, the first left of it and the last '
        'right of it', () {
      final system = sheetOf(beatsScore(2)).systemAt(0);
      final [first, second] = system.bars;
      expect(system.barAt(first.left - 3), same(first));
      expect(system.barAt(first.left), same(first));
      expect(system.barAt(second.left - 0.01), same(first));
      expect(system.barAt(second.left), same(second));
      expect(system.barAt(second.right + 5), same(second));
    });

    test('staffNear picks the staff whose middle line is nearest', () {
      final system = sheetOf(
        beatsScore(1, clefs: const [Clef.treble, Clef.bass]),
      ).systemAt(0);
      final [upper, lower] = system.staves;
      expect(system.staffNear(-5), same(upper));
      expect(system.staffNear(upper.top + 2), same(upper));
      expect(system.staffNear(lower.top + 2), same(lower));
      expect(system.staffNear(lower.top + 20), same(lower));
      // Between the staves, nearer the lower top line but the upper middle,
      // then nearer the upper bottom line but the lower middle.
      final midTops = (upper.top + lower.top) / 2;
      expect(system.staffNear(midTops + 1.5), same(upper));
      expect(system.staffNear(midTops + 2.5), same(lower));
    });

    test('voiceTimes holds each event\'s onset and each tuplet\'s sounding '
        'and written time, and is null for a voice the bar does not have', () {
      final layout = barSheet([
        Tuplet(
          id: const TupletId(50),
          ratio: TupletRatio.triplet,
          unit: NoteValue.eighth,
          members: Seq([
            chordOf(1, 'E4', value: eighth),
            chordOf(2, 'E4', value: eighth),
            chordOf(3, 'E4', value: eighth),
          ]),
        ),
        chordOf(4, 'E4'),
        chordOf(5, 'E4', value: half),
      ]);
      final view = layout.score.measureView(barId(0));
      expect(voiceTimes(view, staffId(0), VoiceSlot.two), isNull);
      expect(voiceTimes(view, staffId(1), VoiceSlot.one), isNull);
      final times = voiceTimes(view, staffId(0), VoiceSlot.one)!;
      expect(times.onsets, [
        Moment.zero,
        at(1, 12),
        at(1, 6),
        at(1, 4),
        at(1, 2),
      ]);
      expect(times.tuplets, [
        (
          onset: Moment.zero,
          duration: Length(Fraction(1, 4)),
          written: Length(Fraction(3, 8)),
          depth: 0,
        ),
      ]);
    });

    test('a bar with a tuplet inside a tuplet gives the inner one\'s points '
        'over its stretch', () {
      final layout = barSheet([
        Tuplet(
          id: const TupletId(60),
          ratio: TupletRatio.triplet,
          unit: NoteValue.quarter,
          members: Seq([
            Tuplet(
              id: const TupletId(61),
              ratio: TupletRatio.triplet,
              unit: NoteValue.eighth,
              members: Seq([
                chordOf(1, 'E4', value: eighth),
                chordOf(2, 'E4', value: eighth),
                chordOf(3, 'E4', value: eighth),
              ]),
            ),
            chordOf(4, 'E4'),
            chordOf(5, 'E4'),
          ]),
        ),
        chordOf(6, 'E4', value: half),
      ]);
      final bar = layout.systemAt(0).bars.single;
      expect(
        entryPoints(
          bar.length,
          voiceTimes(
            layout.score.measureView(barId(0)),
            staffId(0),
            VoiceSlot.one,
          ),
          DurationBase.sixteenth,
        ),
        [
          for (var k = 0; k < 6; k++) at(k, 36),
          for (var k = 4; k < 12; k++) at(k, 24),
          for (var k = 8; k < 16; k++) at(k, 16),
        ],
      );
    });

    test('a tap over each bar of a rest run gives that bar, with time '
        'running evenly across its share', () {
      // The first bar prints the meter, so the run is the three after it.
      final layout = SheetLayout(
        scoreOf([
          for (var bar = 0; bar < 4; bar++)
            [
              staffOf([
                MeasureRest(id: EventId(bar + 1), span: Length.whole),
              ]),
            ],
        ]),
        width: 120,
        text: const FakeMeasurer(),
        style: const EngravingStyle(multiMeasureRests: true),
      );
      final system = layout.systemAt(0);
      expect(
        system.drawables.whereType<GlyphDraw>().map((d) => d.glyph.name),
        contains('restHBarLeft'),
      );
      expect(system.bars, hasLength(4));
      final above = system.staves.single.yOf(12);
      for (final bar in system.bars) {
        for (final (x, offset) in [
          (bar.time.xAt(Moment.zero) + 0.5, Moment.zero),
          (bar.time.xAt(at(1, 2)), at(1, 2)),
        ]) {
          final hit = layout.hitTest(sheetPoint(layout, 0, SpPoint(x, above)));
          expect(hit!.target, isNull);
          expect(hit.at, ScorePoint(bar.measure, offset));
        }
      }
    });

    test('drawablesOf an event covers its notes\' heads with its stem, '
        'accidental and ledger line, and of a note only that note\'s head', () {
      final layout = barSheet([
        chordOf(1, 'C#4 E4'),
        chordOf(2, 'E4', value: dottedHalf),
      ]);
      final system = layout.systemAt(0);
      String name(Drawable d) => d is GlyphDraw ? d.glyph.name : 'line';
      final event = system.drawablesOf(ElementOwner(eventRef(1))).toList();
      final lowerNote = system
          .drawablesOf(ElementOwner(NoteRef(eventRef(1), const NoteId(10))))
          .toList();
      final upperNote = system
          .drawablesOf(ElementOwner(NoteRef(eventRef(1), const NoteId(11))))
          .toList();
      expect(lowerNote.map(name), ['noteheadBlack']);
      expect(upperNote.map(name), ['noteheadBlack']);
      expect(event, containsAll([...lowerNote, ...upperNote]));
      expect(
        event.where((d) => d.owner == ElementOwner(eventRef(1))).map(name),
        unorderedEquals(['line', 'line', 'accidentalSharp']),
      );
      final other = system.drawablesOf(ElementOwner(eventRef(2))).toList();
      expect(other.map(name), ['noteheadHalf', 'augmentationDot', 'line']);
      expect(other.toSet().intersection(event.toSet()), isEmpty);
    });

    test('boundsOf unites an owner\'s drawables and is null for an owner '
        'not drawn in the system', () {
      final layout = barSheet([
        chordOf(1, 'E4'),
        chordOf(2, 'E4', value: dottedHalf),
      ]);
      final system = layout.systemAt(0);
      final head = headOf(system, ElementOwner(noteRef(1)));
      final stem = system.drawables.whereType<LineDraw>().singleWhere(
        (line) => line.owner == ElementOwner(eventRef(1)),
      );
      expect(system.boundsOf(ElementOwner(noteRef(1))), head.bounds);
      expect(
        system.boundsOf(ElementOwner(eventRef(1))),
        head.bounds.union(stem.bounds),
      );
      expect(system.boundsOf(ElementOwner(eventRef(9))), isNull);
      expect(system.boundsOf(const SpannerOwner(SpannerId(1))), isNull);
    });

    test('targetAt prefers a notehead to another part of an event, and that '
        'to a spanner', () {
      final note = ElementOwner(noteRef(1));
      final event = ElementOwner(eventRef(1));
      const spanner = SpannerOwner(SpannerId(1));
      const here = SpPoint(5, 5);
      LineDraw across(Owner? owner) => LineDraw(
        const SpPoint(0, 5),
        const SpPoint(10, 5),
        thickness: 0.2,
        ink: InkRole.ledgerLine,
        owner: owner,
      );
      expect(
        bare([across(spanner), across(event), across(note)]).targetAt(here),
        note,
      );
      expect(bare([across(spanner), across(event)]).targetAt(here), event);
      expect(bare([across(spanner)]).targetAt(here), spanner);
      expect(bare([across(null)]).targetAt(here), isNull);
      expect(bare([across(note)]).targetAt(const SpPoint(5, 6)), isNull);
      expect(
        bare([across(note)]).targetAt(const SpPoint(5, 6), reach: 1),
        note,
      );
    });

    test('targetAt takes the nearest owner within reach, and the rank only '
        'between owners as near as each other', () {
      final note = ElementOwner(noteRef(1));
      final event = ElementOwner(eventRef(2));
      LineDraw at(double y, Owner owner) => LineDraw(
        SpPoint(0, y),
        SpPoint(10, y),
        thickness: 0.25,
        ink: InkRole.ledgerLine,
        owner: owner,
      );
      const here = SpPoint(5, 5);
      expect(
        bare([at(6.4, note), at(5, event)]).targetAt(here, reach: 1.5),
        event,
      );
      expect(
        bare([at(5, event), at(6.4, note)]).targetAt(here, reach: 1.5),
        event,
      );
      expect(
        bare([at(5.6, note), at(4, event)]).targetAt(here, reach: 1.5),
        note,
      );
      expect(
        bare([at(5.5, event), at(4.5, note)]).targetAt(here, reach: 1),
        note,
      );
      expect(
        bare([at(4.5, note), at(5.5, event)]).targetAt(here, reach: 1),
        note,
      );
    });

    test('distanceTo is zero inside a drawable\'s box and grows straight '
        'out of it, and a curve\'s is to its line', () {
      const box = LineDraw(
        SpPoint(0, 5),
        SpPoint(10, 5),
        thickness: 0.2,
        ink: InkRole.ledgerLine,
      );
      expect(box.distanceTo(const SpPoint(5, 5)), 0);
      expect(box.distanceTo(const SpPoint(5, 6.1)), closeTo(1, 1e-9));
      expect(box.distanceTo(const SpPoint(13, 9.1)), closeTo(5, 1e-9));
      const curve = CurveDraw(
        start: SpPoint.zero,
        control1: SpPoint.zero,
        control2: SpPoint(10, 0),
        end: SpPoint(10, 0),
        endThickness: 0.1,
        midThickness: 0.2,
        ink: InkRole.slur,
      );
      expect(curve.distanceTo(const SpPoint(5, 0.05)), 0);
      expect(curve.distanceTo(const SpPoint(5, 2)), closeTo(1.9, 1e-9));
    });
  });

  group('entry points and snapping', () {
    final bar = PlacedBar(
      measure: barId(0),
      left: 0,
      right: 32,
      time: TimeAxis([(Moment.zero, 0), (at(1, 1), 32)]),
      length: Length.whole,
    );

    test('outside a tuplet the points are the grid\'s multiples in the bar, '
        'never the bar end', () {
      expect(entryPoints(Length.whole, null, DurationBase.quarter), [
        Moment.zero,
        at(1, 4),
        at(1, 2),
        at(3, 4),
      ]);
      expect(
        entryPoints(Length(Fraction(3, 4)), null, DurationBase.eighth),
        [for (var k = 0; k < 6; k++) at(k, 8)],
      );
    });

    test('inside a triplet of eighths a sixteenth grid gives six points a '
        'twenty-fourth apart', () {
      final voice = (
        onsets: const <Moment>[],
        tuplets: [
          (
            onset: at(1, 2),
            duration: Length(Fraction(1, 4)),
            written: Length(Fraction(3, 8)),
            depth: 0,
          ),
        ],
      );
      expect(entryPoints(Length.whole, voice, DurationBase.sixteenth), [
        for (var k = 0; k < 8; k++) at(k, 16),
        for (var k = 0; k < 6; k++) at(12 + k, 24),
        for (var k = 12; k < 16; k++) at(k, 16),
      ]);
    });

    test('where a tuplet holds a deeper one, the deeper one\'s points replace '
        'its own over that stretch', () {
      final voice = (
        onsets: const <Moment>[],
        tuplets: [
          (
            onset: Moment.zero,
            duration: Length(Fraction(1, 2)),
            written: Length(Fraction(3, 4)),
            depth: 0,
          ),
          (
            onset: Moment.zero,
            duration: Length(Fraction(1, 6)),
            written: Length(Fraction(3, 8)),
            depth: 1,
          ),
        ],
      );
      expect(entryPoints(Length.whole, voice, DurationBase.sixteenth), [
        for (var k = 0; k < 6; k++) at(k, 36),
        for (var k = 4; k < 12; k++) at(k, 24),
        for (var k = 8; k < 16; k++) at(k, 16),
      ]);
    });

    test('snapTime takes an onset within one space of the tap, and the '
        'nearest grid point otherwise', () {
      final voice = (
        onsets: [Moment.zero, at(3, 8)],
        tuplets: const <TupletSpan>[],
      );
      expect(snapTime(bar, voice, 12.9, DurationBase.quarter), at(3, 8));
      expect(snapTime(bar, voice, 10.9, DurationBase.quarter), at(1, 4));
      expect(snapTime(bar, voice, 31.9, DurationBase.quarter), at(3, 4));
      expect(snapTime(bar, null, 12.9, DurationBase.quarter), at(1, 2));
    });
  });

  test('a sheet whose every part is hidden gives no hit', () {
    final score = beatsScore(2);
    final layout = sheetOf(
      score.copyWith(
        parts: Seq([
          for (final part in score.parts) part.copyWith(hidden: true),
        ]),
      ),
    );
    expect(layout.systemAt(0).staves, isEmpty);
    expect(layout.hitTest(SpPoint(20, layout.tops[0] + 2)), isNull);
  });
}

/// [score] with a slur over the whole of its first bar.
Score withSlurOver(Score score) => score.copyWith(
  spanners: Seq([
    Spanner(
      id: const SpannerId(900),
      kind: const Slur(),
      staff: staffId(0),
      first: ScorePoint(barId(0), Moment.zero),
      last: ScorePoint(barId(0), at(3, 4)),
    ),
  ]),
);
