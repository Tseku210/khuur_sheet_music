import 'dart:math';

import 'package:score_model/score_model.dart';

import 'support.dart';

/// Everything layout reads from [view] but the bar number, as one string
/// to compare.
String describeView(MeasureView view) => [
  view.meterChanged,
  view.keyChanged,
  view.printsMeter,
  view.printsKey,
  view.meterCourtesy,
  view.keyCourtesy,
  _key(view.previousKey),
  view.voltaStarts,
  view.voltaEnds,
  view.isRestOnly,
  for (final s in view.spanners)
    (s.spanner.id, s.from, s.to, s.startsHere, s.endsHere),
  for (final staff in view.staves) ...[
    staff.source.staff,
    staff.clefChanged,
    _key(staff.writtenKey),
    for (final MapEntry(:key, :value) in staff.accidentals.entries)
      (key, value.alter, value.cautionary),
    for (final tie in staff.ties)
      (
        tie.from,
        tie.to?.event.id,
        tie.to?.event.measure,
        tie.to?.note,
        tie.crossesBarline,
      ),
    staff.tiedIn,
    for (final MapEntry(:key, :value) in staff.writtenPitches.entries)
      (key, value),
    for (final voice in staff.voices) ...[
      voice.slot,
      for (final e in voice.events) (e.event.id, e.onset, e.duration),
      for (final b in voice.beams) (b.events, b.secondaryBreaks),
      for (final t in voice.tuplets)
        (t.tuplet.id, t.onset, t.duration, t.events, t.depth),
    ],
  ],
].join(' | ');

(int, KeyMode)? _key(KeySignature? key) =>
    key == null ? null : (key.fifths, key.mode);

T pick<T>(Random random, List<T> options) =>
    options[random.nextInt(options.length)];

Score edited(Score score, Edit edit) =>
    switch (EditSession.start(score).run(edit)) {
      Applied(:final session) => session.score,
      Refused() => score,
    };

/// One random edit of the kinds a composer makes: note entry (the common
/// case), voltas, keys, clefs, spanners, inserted and deleted bars, bar
/// lengths, meters, erased, pasted and transposed ranges, breaks, signature
/// displays, and adding, removing, hiding and showing parts.
Score randomEdit(Score score, Random random) {
  final bar = random.nextInt(score.measures.length);
  final id = score.measures[bar].id;
  switch (random.nextInt(15)) {
    case 0 || 1 || 2:
      return edited(
        score,
        EnterNote(
          at: VoicePoint(
            staff: pick(random, score.staves).id,
            voice: pick(random, [VoiceSlot.one, VoiceSlot.two]),
            at: ScorePoint(id, at(random.nextInt(8), 8)),
          ),
          tone: Pitch.parse(pick(random, ['F4', 'F#4', 'Bb4', 'E5'])),
          value: pick(random, [
            NoteValue.eighth,
            NoteValue.sixteenth,
            NoteValue.quarter,
            NoteValue.quarter.dotted,
            NoteValue.half,
          ]),
        ),
      );
    case 3:
      final last = score.measures[min(bar + 1, score.measures.length - 1)];
      return edited(
        score,
        SetVolta(
          id,
          last.id,
          pick(random, [
            null,
            const Volta([1]),
            const Volta([2]),
          ]),
        ),
      );
    case 4:
      return edited(
        score,
        SetKey(from: id, key: KeySignature(random.nextInt(5) - 2)),
      );
    case 5:
      return edited(
        score,
        SetClef(
          staff: pick(random, score.staves).id,
          at: ScorePoint(id, at(random.nextInt(4), 4)),
          clef: pick(random, [Clef.treble, Clef.bass, Clef.alto]),
        ),
      );
    case 6:
      if (score.spanners.isNotEmpty && random.nextBool()) {
        return edited(
          score,
          RemoveSpanner(pick(random, score.spanners.toList()).id),
        );
      }
      final ends = [
        (random.nextInt(score.measures.length), random.nextInt(4)),
        (random.nextInt(score.measures.length), random.nextInt(4)),
      ]..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
      return edited(
        score,
        AddSpanner(
          kind: pick(random, const [
            Slur(),
            OctaveLine(OctaveShift.up8),
            OctaveLine(OctaveShift.down8),
          ]),
          staff: pick(random, score.staves).id,
          first: pointAt(score, ends[0].$1, at(ends[0].$2, 4)),
          last: pointAt(score, ends[1].$1, at(ends[1].$2, 4)),
        ),
      );
    case 7:
      if (score.measures.length > 3 && random.nextBool()) {
        final last = score.measures[min(bar + 1, score.measures.length - 1)];
        return edited(score, DeleteMeasures(id, last.id));
      }
      return edited(
        score,
        InsertMeasures(
          before: random.nextBool() ? id : null,
          count: 1 + random.nextInt(2),
        ),
      );
    case 8:
      return edited(
        score,
        SetBarLength(id, pick(random, [null, len(1, 4), len(3, 8), len(5, 4)])),
      );
    case 9:
      return edited(
        score,
        SetMeter(
          from: id,
          meter: pick(random, const [
            Meter.fourFour,
            Meter.threeFour,
            Meter.twoFour,
            Meter.sixEight,
          ]),
          content: pick(random, MeterContent.values),
        ),
      );
    case 10:
      final last = min(bar + random.nextInt(2), score.measures.length - 1);
      return edited(
        score,
        Erase(
          RangeSelection(
            from: ScorePoint(id, at(random.nextInt(4), 4)),
            to: pointAt(score, last, at(1 + random.nextInt(4), 4)),
            top: pick(random, score.staves).id,
            bottom: pick(random, score.staves).id,
          ),
        ),
      );
    case 11:
      final last = min(bar + random.nextInt(2), score.measures.length - 1);
      final clip = EditSession.start(score)
          .select(
            RangeSelection(
              from: ScorePoint(id, at(random.nextInt(4), 4)),
              to: pointAt(score, last, at(1 + random.nextInt(4), 4)),
              top: pick(random, score.staves).id,
              bottom: pick(random, score.staves).id,
            ),
          )
          .copy();
      return clip == null
          ? score
          : edited(
              score,
              Paste(
                clip,
                at: VoicePoint(
                  staff: pick(random, score.staves).id,
                  voice: VoiceSlot.one,
                  at: ScorePoint(
                    score.measures[random.nextInt(score.measures.length)].id,
                    at(random.nextInt(4), 4),
                  ),
                ),
              ),
            );
    case 12:
      final last = min(bar + random.nextInt(2), score.measures.length - 1);
      return edited(
        score,
        Transpose(
          RangeSelection(
            from: ScorePoint(id, at(random.nextInt(4), 4)),
            to: pointAt(score, last, at(1 + random.nextInt(4), 4)),
            top: pick(random, score.staves).id,
            bottom: pick(random, score.staves).id,
          ),
          pick(random, const [
            Transposition.interval(Interval.majorSecond),
            Transposition.diatonic(-2),
            Transposition.chromatic(1),
          ]),
        ),
      );
    case 13:
      return edited(score, switch (random.nextInt(3)) {
        0 => SetBreak(id, pick(random, [null, ...LayoutBreak.values])),
        1 => SetKeyDisplay(id, pick(random, SignatureDisplay.values)),
        _ => SetMeterDisplay(id, pick(random, SignatureDisplay.values)),
      });
    default:
      final part = score.parts[random.nextInt(score.parts.length)];
      return edited(score, switch (random.nextInt(3)) {
        0 => SetPartHidden(part.id, hidden: !part.hidden),
        1 => AddPart(
          pick(random, const [morinKhuur, clarinet, piano]),
          index: random.nextInt(score.parts.length + 1),
        ),
        _ => RemovePart(part.id),
      });
  }
}
