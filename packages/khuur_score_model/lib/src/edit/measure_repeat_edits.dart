part of 'session.dart';

/// The bars the sign [sign] on bar [bar] covers with its other half: none
/// without a sign, [bar] for a one-bar sign, and both bars of a two-bar
/// sign.
List<int> _signBars(MeasureRepeat? sign, int bar) => switch (sign) {
  null => const [],
  MeasureRepeat.oneBar => [bar],
  MeasureRepeat.twoBarsFirst => [bar, bar + 1],
  MeasureRepeat.twoBarsSecond => [bar - 1, bar],
};

_Result _setMeasureRepeat(
  Score score,
  MeasureId measure,
  StaffId? staff,
  int? bars,
  _Ids ids,
) {
  if (bars != null && bars != 1 && bars != 2) {
    throw const _Refuse(InvalidValue('a measure repeat repeats 1 or 2 bars'));
  }
  if (staff != null) {
    _staff(score, staff);
  }
  final at = _barIndex(score, measure);
  final measures = score.measures;
  final staves = [
    for (final (k, slice) in measures[at].staves.indexed)
      if (staff == null || slice.staff == staff) k,
  ];
  if (bars == null) {
    var cleared = measures;
    for (final k in staves) {
      for (final i in _signBars(measures[at].staves[k].measureRepeat, at)) {
        if (i < 0 || i >= cleared.length) {
          continue;
        }
        final column = cleared[i];
        cleared = cleared.replaceAt(
          i,
          column.withStaff(
            column.staves[k].copyWith(measureRepeat: () => null),
          ),
        );
      }
    }
    return _Result(
      identical(cleared, measures) ? score : score.copyWith(measures: cleared),
    );
  }
  if (at < bars) {
    throw _Refuse(InvalidValue('no $bars bars before to repeat'));
  }
  final signs = bars == 1
      ? const [MeasureRepeat.oneBar]
      : const [MeasureRepeat.twoBarsFirst, MeasureRepeat.twoBarsSecond];
  final covered = _signBars(signs.first, at);
  if (covered.last >= measures.length) {
    throw const _Refuse(InvalidValue('a two-bar repeat needs a bar after'));
  }
  if (bars == 2 && measures[covered.last].breakBefore != null) {
    throw const _Refuse(
      InvalidValue('a two-bar repeat has no layout break between its bars'),
    );
  }
  if (covered.any((i) => measures[i].length != measures[i - bars].length)) {
    throw const _Refuse(
      InvalidValue('a measure repeat repeats bars of its own length'),
    );
  }
  var next = score;
  for (final k in staves) {
    for (final (h, i) in covered.indexed) {
      final column = next.measures[i];
      final slice = column.staves[k];
      if (slice.measureRepeat == signs[h]) {
        continue;
      }
      final rest = switch (slice.voices.first.items.singleOrNull) {
        final MeasureRest rest when slice.voices.length == 1 => rest,
        _ => MeasureRest(id: ids.event(), span: column.length),
      };
      for (final voice in measures[i - 1].staves[k].voices) {
        next = _untieInto(
          next,
          VoicePoint(
            staff: slice.staff,
            voice: voice.slot,
            at: ScorePoint(column.id, Moment.zero),
          ),
          const {},
        );
      }
      final updated = next.measures[i];
      next = next.copyWith(
        measures: next.measures.replaceAt(
          i,
          updated.withStaff(
            updated.staves[k].copyWith(
              clefChanges: const Seq.empty(),
              voices: Seq([
                Voice(slot: VoiceSlot.one, items: Seq([rest])),
              ]),
              measureRepeat: () => signs[h],
            ),
          ),
        ),
      );
    }
  }
  return _Result(next);
}

/// [score] with every measure-repeat sign an edit has left unable to stand
/// cleared, such as a half of a two-bar repeat whose other half was
/// deleted or written into.
Score _withStandingMeasureRepeats(Score score) {
  final measures = withStandingMeasureRepeats(score.measures);
  return identical(measures, score.measures)
      ? score
      : score.copyWith(measures: measures);
}

/// [score] with the notes written out on every staff under a standing
/// measure-repeat sign that a new meter on bars [start] up to [end] would
/// break, so the music goes on sounding. A sign breaks when it or a bar it
/// repeats is re-barred, or with [keep] when only some of its bars take the
/// meter. Both halves of a two-bar sign go together.
///
/// A written-out bar gets the part of each slur, trill line and other line
/// on notes that lies in the bars it repeats, which playback replayed with
/// the notes.
/// It gets no dynamics, hairpins, tempo lines or pedal lines, which apply
/// by time where they stand: the copy plays at the loudness in force where
/// it stands, as later bars do.
Score _writtenOut(
  Score score,
  int start,
  int end,
  _Ids ids, {
  required bool keep,
}) {
  final measures = score.measures;
  final copies = <(int, StaffId), PlayedCopy>{};
  for (var k = 0; k < measures.first.staves.length; k++) {
    for (var bar = 0; bar < measures.length; bar++) {
      final covered = _signBars(measures[bar].staves[k].measureRepeat, bar);
      if (covered.isEmpty ||
          covered.first != bar ||
          !measureRepeatStands(measures, bar, k)) {
        continue;
      }
      final first = covered.map((i) => playedBar(measures, i, k)).reduce(min);
      final touched = first < end && start <= covered.last;
      final inside = start <= first && covered.last < end;
      if (touched && !(keep && inside)) {
        for (final i in covered) {
          if (playedVoices(measures, i, k, () => ids.next++) case final copy?) {
            copies[(i, measures[i].staves[k].staff)] = copy;
          }
        }
      }
    }
  }
  if (copies.isEmpty) {
    return score;
  }
  var columns = measures;
  for (final MapEntry(key: (bar, staff), value: copy) in copies.entries) {
    final slice = columns[bar].staff(staff);
    columns = columns.replaceAt(
      bar,
      columns[bar].withStaff(
        slice.copyWith(voices: copy.voices, measureRepeat: () => null),
      ),
    );
  }
  final spanners = [...score.spanners];
  for (final MapEntry(key: (bar, staff), value: (:source, voices: _, ids: _))
      in copies.entries) {
    if (copies[(bar - 1, staff)]?.source == source - 1) {
      continue;
    }
    var length = 1;
    while (copies[(bar + length, staff)]?.source == source + length) {
      length++;
    }
    for (final spanner in score.spanners) {
      if (spanner.staff == staff && _lieOnNotes(spanner.kind)) {
        if (_copiedInto(score, columns, spanner, bar, source, length)
            case (final first, final last)) {
          spanners.add(
            Spanner(
              id: ids.spanner(),
              kind: spanner.kind,
              staff: staff,
              voice: spanner.voice,
              first: first,
              last: last,
            ),
          );
        }
      }
    }
  }
  return score.copyWith(measures: columns, spanners: Seq(spanners));
}

/// Whether playback replays a spanner of [kind] with the notes it lies
/// over, so that notes written out from a measure-repeat sign need a copy
/// of it, or reads it by time where it stands.
bool _lieOnNotes(SpannerKind kind) => switch (kind) {
  Slur() || TrillLine() || Glissando() || OctaveLine() => true,
  Hairpin() || TempoLine() || PedalLine() => false,
};

/// Where the copy of [spanner] goes in [written], whose [length] bars from
/// [bar] hold copies of the bars from [source] on, or null when [spanner]
/// does not reach those bars. Only the part of [spanner] within them is
/// copied: from the start of [bar] when it starts before them, and to the
/// last onset of the copies when it ends after them. Null too when that
/// part ends before it starts.
(ScorePoint, ScorePoint)? _copiedInto(
  Score score,
  Seq<MeasureColumn> written,
  Spanner spanner,
  int bar,
  int source,
  int length,
) {
  final from = score.indexOf(spanner.first.measure);
  final to = score.indexOf(spanner.last.measure);
  final end = source + length - 1;
  if (to < source || from > end) {
    return null;
  }
  final shift = bar - source;
  final first = from < source
      ? ScorePoint(written[bar].id, Moment.zero)
      : ScorePoint(written[from + shift].id, spanner.first.offset);
  final last = to > end
      ? _lastOnset(written[end + shift], spanner)
      : ScorePoint(written[to + shift].id, spanner.last.offset);
  return first.measure == last.measure && last.offset < first.offset
      ? null
      : (first, last);
}
