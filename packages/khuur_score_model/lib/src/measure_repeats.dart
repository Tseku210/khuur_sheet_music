/// The rule across bars for measure-repeat signs. See [MeasureRepeat].
library;

import 'events.dart';
import 'measure.dart';
import 'refs.dart';
import 'seq.dart';

/// Whether the sign on staff [staff] of bar [bar] stands: it has the bars
/// it repeats, they have its length, and a half of a two-bar repeat sits
/// next to its other half, which stands too, with no layout break before
/// the second half. True for a bar with no sign.
bool measureRepeatStands(Seq<MeasureColumn> measures, int bar, int staff) {
  bool alone(int i) {
    final sign = measures[i].staves[staff].measureRepeat;
    return sign == null ||
        i >= sign.bars && measures[i - sign.bars].length == measures[i].length;
  }

  MeasureRepeat? at(int i) => i >= 0 && i < measures.length
      ? measures[i].staves[staff].measureRepeat
      : null;

  return switch (at(bar)) {
    null => true,
    MeasureRepeat.oneBar => alone(bar),
    MeasureRepeat.twoBarsFirst =>
      at(bar + 1) == MeasureRepeat.twoBarsSecond &&
          measures[bar + 1].breakBefore == null &&
          alone(bar) &&
          alone(bar + 1),
    MeasureRepeat.twoBarsSecond =>
      at(bar - 1) == MeasureRepeat.twoBarsFirst &&
          measures[bar].breakBefore == null &&
          alone(bar - 1) &&
          alone(bar),
  };
}

/// [measures] with every measure-repeat sign that does not stand cleared,
/// or [measures] itself when every sign stands. A cleared bar keeps its
/// whole-bar rest.
Seq<MeasureColumn> withStandingMeasureRepeats(Seq<MeasureColumn> measures) {
  List<MeasureColumn>? changed;
  for (final (bar, column) in measures.indexed) {
    var next = column;
    for (final (staff, slice) in column.staves.indexed) {
      if (!measureRepeatStands(measures, bar, staff)) {
        next = next.withStaff(slice.copyWith(measureRepeat: () => null));
      }
    }
    if (!identical(next, column)) {
      (changed ??= measures.toList())[bar] = next;
    }
  }
  return changed == null ? measures : Seq(changed);
}

/// The index of the bar whose notes staff [staff] of bar [bar] plays: [bar]
/// itself, or for a bar under a standing sign the bar it repeats, followed
/// back through any sign that bar is under. A sign that does not stand,
/// which only a score built outside edits and loading can hold, plays its
/// own rest.
int playedBar(Seq<MeasureColumn> measures, int bar, int staff) {
  var source = bar;
  for (
    var sign = measures[source].staves[staff].measureRepeat;
    sign != null && measureRepeatStands(measures, source, staff);
    sign = measures[source].staves[staff].measureRepeat
  ) {
    source -= sign.bars;
  }
  return source;
}

/// [playedBar] of every bar of staff [staff].
List<int> playedBars(Seq<MeasureColumn> measures, int staff) {
  final played = List<int>.filled(measures.length, 0);
  for (var bar = 0; bar < measures.length; bar++) {
    final sign = measures[bar].staves[staff].measureRepeat;
    played[bar] = sign != null && measureRepeatStands(measures, bar, staff)
        ? played[bar - sign.bars]
        : bar;
  }
  return played;
}

/// A copy of the voices a bar under a measure-repeat sign plays: the bar it
/// copies, the voices, and the id of each copied event, chord and grace,
/// and of each copied note, by the id it has in the bar it copies.
typedef PlayedCopy = ({
  int source,
  Seq<Voice> voices,
  Map<EventId, EventId> ids,
  Map<NoteId, NoteId> notes,
});

/// A copy of the voices of staff [staff] of bar [source], with new ids from
/// [mint] and no lyrics, for a bar that plays [source]. Null when they are a
/// whole-bar rest.
PlayedCopy? copiedVoices(
  Seq<MeasureColumn> measures,
  int source,
  int staff,
  int Function() mint,
) {
  final voices = measures[source].staves[staff].voices;
  if (voices.length == 1 && voices.first.items.singleOrNull is MeasureRest) {
    return null;
  }
  final ids = <EventId, EventId>{};
  final notes = <NoteId, NoteId>{};
  EventId event(EventId id) => ids[id] = EventId(mint());
  NoteId note(NoteId id) => notes[id] = NoteId(mint());
  return (
    source: source,
    voices: Seq([
      for (final voice in voices)
        Voice(
          slot: voice.slot,
          items: Seq([
            for (final item in voice.items) _copied(item, event, note, mint),
          ]),
        ),
    ]),
    ids: ids,
    notes: notes,
  );
}

/// [item] with a new id on every event, note, grace and tuplet in it, taken
/// from [event] for events, [head] for notes and [mint] for tuplets, and
/// no lyrics.
VoiceItem _copied(
  VoiceItem item,
  EventId Function(EventId source) event,
  NoteId Function(NoteId source) head,
  int Function() mint,
) {
  Seq<Note> heads(Seq<Note> notes) => Seq([
    for (final note in notes) note.copyWith(id: head(note.id)),
  ]);
  return switch (item) {
    Gap() => item,
    ChordEvent(:final graces) => item.copyWith(
      id: event(item.id),
      notes: heads(item.notes),
      graces: Seq([
        for (final grace in graces)
          GraceChord(
            id: event(grace.id),
            kind: grace.kind,
            value: grace.value,
            notes: heads(grace.notes),
          ),
      ]),
      lyrics: const Seq.empty(),
    ),
    RestEvent(:final id, :final value, :final articulations, :final hidden) =>
      RestEvent(
        id: event(id),
        value: value,
        articulations: articulations,
        hidden: hidden,
      ),
    MeasureRest(:final id, :final span, :final articulations) => MeasureRest(
      id: event(id),
      span: span,
      articulations: articulations,
    ),
    Tuplet(:final ratio, :final unit, :final members, :final bracket) => Tuplet(
      id: TupletId(mint()),
      ratio: ratio,
      unit: unit,
      members: Seq([
        for (final member in members)
          _copied(member, event, head, mint) as Content,
      ]),
      bracket: bracket,
    ),
  };
}
