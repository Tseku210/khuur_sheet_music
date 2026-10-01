part of 'session.dart';

/// Access pattern 8: change the meter from a bar onward and re-bar.
///
/// Why re-bar instead of leaving bars over- or underfull: the column
/// invariant says every voice fills its bar exactly. Keeping old content in
/// bars of a new length would break it; relaxing the invariant would push
/// "is this bar valid?" into layout, playback and every edit. Re-barring
/// keeps the invariant and matches what MuseScore and Finale do.
///
/// Why sections: repeat signs, volta boundaries, key changes, rehearsal
/// marks, navigation marks and any barline other than a plain one are the
/// composer's structure. Re-barring across them would move a repeat sign
/// into the middle of a phrase. Each section is re-barred on its own, so
/// structural barlines stay where they are. Keeping bars is the same
/// re-barring with every bar its own section that may not grow.
///
/// The cursor, a range selection and spanner ends follow the music by
/// time. A meter of the same length only replaces the meter.
_Result _setMeter(Score score, SetMeter edit, _Ids ids, EditSession session) {
  final measures = score.measures;
  final start = _barIndex(score, edit.from);
  final old = measures[start].meter;
  final meter = edit.meter;
  _check(meterProblem(meter));
  if (old == meter) {
    return _Result(score);
  }
  var end = start + 1;
  while (end < measures.length && measures[end].meter == old) {
    end++;
  }
  if (old.length == meter.length) {
    return _Result(
      score.copyWith(
        measures: measures.replaceRange(start, end, [
          for (var i = start; i < end; i++) measures[i].copyWith(meter: meter),
        ]),
      ),
    );
  }
  final keep = edit.content == MeterContent.keepBars;
  final sections = [
    for (final (a, b)
        in keep
            ? [for (var i = start; i < end; i++) (i, i + 1)]
            : _sections(measures, start, end))
      _rebar(score, a, b, meter, ids, keep: keep),
  ];
  final rebarred = score.copyWith(
    measures: measures.replaceRange(start, end, [
      for (final section in sections) ...section.bars,
    ]),
  );
  final holding = {
    for (final section in sections)
      for (final column in section.old) column.id: section,
  };
  // A start in time that was cut goes to where the music goes on.
  ScorePoint? onset(ScorePoint point) {
    final section = holding[point.measure];
    return section == null ? point : section.moved(point) ?? section.resume;
  }

  final spanners = _moveSpanners(
    rebarred,
    first: (spanner) => onset(spanner.first),
    last: (spanner) {
      final section = holding[spanner.last.measure];
      return section == null
          ? spanner.last
          : section.moved(spanner.last) ??
                _lastOnset(section.bars.last, spanner);
    },
  );
  final cursor = session.cursor;
  final at = onset(cursor.at);
  Selection? selection;
  if (session.selection case RangeSelection(
    :final from,
    :final to,
    :final top,
    :final bottom,
  )) {
    final first = onset(from);
    final section = holding[to.measure];
    final last = section == null ? to : section.moved(to) ?? section.end;
    selection = first != null && _precedes(rebarred, first, last)
        ? RangeSelection(from: first, to: last, top: top, bottom: bottom)
        : const Selection.none();
  }
  return _Result(
    rebarred.copyWith(spanners: spanners),
    cursor: at == null
        ? null
        : VoicePoint(staff: cursor.staff, voice: cursor.voice, at: at),
    selection: selection,
  );
}

/// Bars [start] up to [end] as runs of bars that re-bar together, each a
/// start index and the index after its end.
List<(int, int)> _sections(Seq<MeasureColumn> measures, int start, int end) {
  final sections = <(int, int)>[];
  var first = start;
  for (var i = start + 1; i < end; i++) {
    if (_splits(measures[i - 1], measures[i])) {
      sections.add((first, i));
      first = i;
    }
  }
  return sections..add((first, end));
}

/// Whether the barline between [before] and [bar] ends a section. A pickup
/// or other irregular bar is a section of its own.
bool _splits(MeasureColumn before, MeasureColumn bar) =>
    before.irregularLength != null ||
    bar.irregularLength != null ||
    before.barline != Barline.regular ||
    before.repeatEnd != null ||
    before.navigation.any((mark) => !mark.atBarStart) ||
    bar.repeatStart ||
    bar.rehearsal != null ||
    bar.navigation.any((mark) => mark.atBarStart) ||
    bar.key != before.key ||
    bar.volta != before.volta;

/// A run of bars re-barred together: the bars it had and the bars that
/// replace them.
final class _Section {
  const _Section(this.old, this.bars, this.next);

  final List<MeasureColumn> old;
  final List<MeasureColumn> bars;

  /// The bar after the section. Null at the end of the score.
  final MeasureColumn? next;

  ScorePoint? get resume =>
      next == null ? null : ScorePoint(next!.id, Moment.zero);

  ScorePoint get end =>
      ScorePoint(bars.last.id, Moment.zero + bars.last.length);

  /// Where [point], in one of [old], is now. Null when its time was cut.
  ScorePoint? moved(ScorePoint point) {
    final i = old.indexWhere((column) => column.id == point.measure);
    final time =
        old.first.length * Fraction(i) + Moment.zero.until(point.offset);
    final (k, offset) = _barAt(time, bars.first.length);
    return k < bars.length ? ScorePoint(bars[k].id, offset) : null;
  }
}

/// Re-bars [score]'s bars [a] up to [b] under [meter] as one section. With
/// [keep] the section is one bar and refuses to grow. A pickup or other
/// irregular bar keeps its content.
_Section _rebar(
  Score score,
  int a,
  int b,
  Meter meter,
  _Ids ids, {
  required bool keep,
}) {
  final old = [for (var i = a; i < b; i++) score.measures[i]];
  final next = b < score.measures.length ? score.measures[b] : null;
  final first = old.first;
  final last = old.last;
  if (first.irregularLength case final irregular?) {
    return _Section(old, [
      first.copyWith(
        meter: meter,
        irregularLength: () => irregular == meter.length ? null : irregular,
      ),
    ], next);
  }
  final streams = [
    for (final staff in first.staves)
      for (final slot in VoiceSlot.values) _Stream(old, staff.staff, slot),
  ];
  final length = meter.length;
  final longest = streams
      .map((stream) => stream.length)
      .reduce((x, y) => x > y ? x : y);
  if (keep && longest > length) {
    throw _Refuse(WouldCrossBarline(first.id, longest - length));
  }
  final count = max(_ceil(longest / length), old.length);
  final total = length * Fraction(count);
  final voices = [
    for (final stream in streams)
      (
        stream.staff,
        stream.slot,
        _cut(
          (stream..untie(next, padded: stream.length < total)).items,
          count,
          meter,
          ids,
          gaps: stream.slot != VoiceSlot.one,
        ),
      ),
  ];
  (int, Moment)? place(int i, Moment offset) {
    final placed = _barAt(
      first.length * Fraction(i) + Moment.zero.until(offset),
      length,
    );
    return placed.$1 < count ? placed : null;
  }

  // A break or signature display stays where its bar's start is a barline.
  final opening = {
    for (final (i, column) in old.indexed)
      if (place(i, Moment.zero) case (final k, final offset) when offset.isZero)
        k: column,
  };
  final tempos = [for (var k = 0; k < count; k++) <TempoMark>[]];
  for (final (i, column) in old.indexed) {
    for (final tempo in column.tempos) {
      if (place(i, tempo.offset) case (final k, final offset)) {
        tempos[k].add(
          offset == tempo.offset
              ? tempo
              : TempoMark(
                  offset: offset,
                  tempo: tempo.tempo,
                  text: tempo.text,
                  showMetronome: tempo.showMetronome,
                ),
        );
      }
    }
  }
  List<StaffMeasure> staffBars(StaffId staff) {
    final clefs = <(Length, Clef)>[];
    final directions = [for (var k = 0; k < count; k++) <StaffDirection>[]];
    for (final (i, column) in old.indexed) {
      final measure = column.staff(staff);
      final start = first.length * Fraction(i);
      if (i == 0 || measure.clef != old[i - 1].staff(staff).clefAtEnd) {
        clefs.add((start, measure.clef));
      }
      for (final change in measure.clefChanges) {
        clefs.add((start + Moment.zero.until(change.offset), change.clef));
      }
      for (final direction in measure.directions) {
        if (place(i, direction.offset) case (final k, final offset)) {
          directions[k].add(_movedTo(direction, offset));
        }
      }
    }
    return [
      for (var k = 0; k < count; k++)
        StaffMeasure(
          staff: staff,
          clef: clefs.lastWhere((c) => c.$1 <= length * Fraction(k)).$2,
          clefChanges: Seq([
            for (final (time, clef) in clefs)
              if (time > length * Fraction(k) &&
                  time < length * Fraction(k + 1))
                ClefChange(_barAt(time, length).$2, clef),
          ]),
          directions: Seq(directions[k]),
          voices: Seq([
            for (final (lane, slot, bars) in voices)
              if (lane == staff &&
                  (slot == VoiceSlot.one || !bars[k].every((i) => i is Gap)))
                Voice(slot: slot, items: Seq(bars[k])),
          ]),
        ),
    ];
  }

  final staves = [for (final staff in first.staves) staffBars(staff.staff)];
  return _Section(old, [
    for (var k = 0; k < count; k++)
      MeasureColumn(
        id: k < old.length ? old[k].id : ids.measure(),
        meter: meter,
        key: first.key,
        volta: first.volta,
        repeatStart: k == 0 && first.repeatStart,
        rehearsal: k == 0 ? first.rehearsal : null,
        navigation: Seq([
          if (k == 0) ...first.navigation.where((mark) => mark.atBarStart),
          if (k == count - 1)
            ...last.navigation.where((mark) => !mark.atBarStart),
        ]),
        barline: k == count - 1 ? last.barline : Barline.regular,
        repeatEnd: k == count - 1 ? last.repeatEnd : null,
        tempos: Seq(tempos[k]),
        staves: Seq([for (final bars in staves) bars[k]]),
        breakBefore: opening[k]?.breakBefore,
        keyDisplay: opening[k]?.keyDisplay ?? SignatureDisplay.auto,
        meterDisplay: opening[k]?.meterDisplay ?? SignatureDisplay.auto,
      ),
  ], next);
}

/// One voice of one staff through a section, barlines dissolved: each item
/// with the bar it came from, and a gap for a bar without the voice.
/// Trailing rests and gaps are elastic, so they are dropped and the section
/// is refilled after the music.
final class _Stream {
  _Stream(List<MeasureColumn> bars, this.staff, this.slot) {
    for (final column in bars) {
      final voice = column.staff(staff).voice(slot);
      for (final item in voice?.items ?? <VoiceItem>[Gap(column.length)]) {
        items.add((item, column.id));
      }
    }
    final all = items.length;
    while (items.isNotEmpty && _elastic(items.last.$1)) {
      items.removeLast();
    }
    trimmed = items.length < all;
  }

  final StaffId staff;
  final VoiceSlot slot;
  final List<(VoiceItem, MeasureId)> items = [];
  late final bool trimmed;

  late final Length length = Length.sum(items.map((entry) => entry.$1.span));

  /// Clears each tie of the last event that would end on a different head
  /// once the section is refilled: the music now meets rests where it met
  /// [next] ([padded]), or meets [next] where it met rests.
  void untie(MeasureColumn? next, {required bool padded}) {
    if (trimmed == padded || next == null) {
      return;
    }
    final opening = openingEvent(next, staff, slot)?.event;
    if (items.lastOrNull case (final Content item, final origin)
        when opening is ChordEvent) {
      final event = _lastEvent(item);
      bool meets(Note note) =>
          note.tie && opening.notes.any((n) => n.tone == note.tone);
      if (event is ChordEvent && event.notes.any(meets)) {
        items.last = (
          _replaceEvent(
            item,
            event.copyWith(
              notes: Seq([
                for (final note in event.notes)
                  meets(note) ? note.copyWith(tie: false) : note,
              ]),
            ),
          ),
          origin,
        );
      }
    }
  }
}

/// Whether a re-bar may drop [item] from the end of a section: a gap or a
/// plain rest. A rest with a fermata is music.
bool _elastic(VoiceItem item) => switch (item) {
  Gap() => true,
  RestEvent(:final articulations) ||
  MeasureRest(:final articulations) => articulations.isEmpty,
  ChordEvent() || Tuplet() => false,
};

Event _lastEvent(Content item) => switch (item) {
  Event() => item,
  Tuplet(:final members) => _lastEvent(members.last),
};

/// [items], laid end to end from the start of a section, cut into [count]
/// bars of [meter]. A note that crosses a barline is split and tied, and a
/// rest is split. A measure rest is blank time, as is the time after the
/// items. Blank time is rests in voice one and gaps in the others ([gaps]),
/// and a whole bar of it is a measure rest. Refused when a barline would
/// cut a tuplet.
List<List<VoiceItem>> _cut(
  List<(VoiceItem, MeasureId)> items,
  int count,
  Meter meter,
  _Ids ids, {
  required bool gaps,
}) {
  final length = meter.length;
  final grid = BeatGrid.meter(meter);
  final bars = [for (var k = 0; k < count; k++) <VoiceItem>[]];
  void split(List<_Span> spans, Event event) {
    final values = [
      for (final span in spans)
        spellOnGrid(
          grid,
          span.offset,
          span.length,
          rest: event is! ChordEvent,
        ),
    ];
    final pieces = _split(event, [for (final v in values) ...v], ids);
    var n = 0;
    for (final (k, span) in spans.indexed) {
      bars[span.bar].addAll(pieces.getRange(n, n + values[k].length));
      n += values[k].length;
    }
  }

  void blank(Event? kept, List<_Span> spans) {
    for (final (n, span) in spans.indexed) {
      final keeps = n == 0 ? kept : null;
      if (span.length == length) {
        bars[span.bar].add(
          MeasureRest(
            id: keeps?.id ?? ids.event(),
            span: length,
            articulations: keeps?.articulations ?? const {},
          ),
        );
      } else {
        bars[span.bar].addAll(
          keeps == null
              ? _rests(grid, span.offset, span.length, ids)
              : _split(
                  keeps,
                  spellOnGrid(grid, span.offset, span.length, rest: true),
                  ids,
                ),
        );
      }
    }
  }

  var time = Length.zero;
  for (final (item, origin) in items) {
    final spans = _spans(time, item.span, length);
    time += item.span;
    switch (item) {
      case MeasureRest():
        blank(item, spans);
      case _ when spans.length == 1:
        bars[spans.single.bar].add(item);
      case Tuplet(:final id):
        throw _Refuse(WouldSplitTuplet(id, origin));
      case Gap():
        for (final span in spans) {
          bars[span.bar].add(Gap(span.length));
        }
      case Event():
        split(spans, item);
    }
  }
  final left = length * Fraction(count) - time;
  if (left.isPositive) {
    final spans = _spans(time, left, length);
    if (gaps) {
      for (final span in spans) {
        bars[span.bar].add(Gap(span.length));
      }
    } else {
      blank(null, spans);
    }
  }
  return [for (final bar in bars) _mergeGaps(bar)];
}

typedef _Span = ({int bar, Moment offset, Length length});

/// [span] from [time] into a section of bars [length] long, cut at the
/// barlines.
List<_Span> _spans(Length time, Length span, Length length) {
  final spans = <_Span>[];
  final end = time + span;
  var at = time;
  while (at < end) {
    final (bar, offset) = _barAt(at, length);
    final barEnd = length * Fraction(bar + 1);
    final stop = barEnd < end ? barEnd : end;
    spans.add((bar: bar, offset: offset, length: stop - at));
    at = stop;
  }
  return spans;
}

/// The bar holding [time] into a section of bars [length] long, counted
/// from 0, and the offset in it.
(int, Moment) _barAt(Length time, Length length) {
  final ratio = time / length;
  final bar = ratio.numerator ~/ ratio.denominator;
  return (bar, Moment.zero + (time - length * Fraction(bar)));
}

int _ceil(Fraction f) => (f.numerator + f.denominator - 1) ~/ f.denominator;

StaffDirection _movedTo(StaffDirection direction, Moment offset) =>
    offset == direction.offset
    ? direction
    : switch (direction) {
        DynamicMark(:final level) => DynamicMark(offset, level),
        TextMark(:final text, :final above) => TextMark(
          offset,
          text,
          above: above,
        ),
        ChordSymbol(:final root, :final quality, :final bass) => ChordSymbol(
          offset,
          root: root,
          quality: quality,
          bass: bass,
        ),
      };
