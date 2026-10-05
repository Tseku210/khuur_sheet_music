import 'package:flutter/material.dart';
import 'package:simple_sheet_music/simple_sheet_music.dart';

/// The selected events in time order, which is what every button of the
/// action row works on. Each event names its staff in its `ref` and its
/// voice in `voice`.
final class Picked {
  Picked._(this._score, this.selection, this.events);

  factory Picked.of(Score score, Selection selection) {
    final staves = [for (final staff in score.staves) staff.id];
    final events = switch (selection) {
      NoSelection() => <TimedEvent>[],
      ItemSelection(:final items) => [
        for (final ref in {for (final item in items) item.event})
          ?score.lookup(ref),
      ],
      RangeSelection() => _within(score, selection, staves),
    };
    return Picked._(
      score,
      selection,
      events..sort((a, b) {
        final bars =
            score.indexOf(a.ref.measure) - score.indexOf(b.ref.measure);
        if (bars != 0) {
          return bars;
        }
        final time = a.onset.compareTo(b.onset);
        return time != 0
            ? time
            : staves.indexOf(a.ref.staff) - staves.indexOf(b.ref.staff);
      }),
    );
  }

  final Score _score;
  final Selection selection;
  final List<TimedEvent> events;

  /// What the selection names one by one, which is its own items, or every
  /// event of a range.
  late final List<ElementRef> items = switch (selection) {
    ItemSelection(items: final named) => [...named],
    _ => [for (final timed in events) timed.ref],
  };

  /// The heads of [timed] that the selection names. A tap on a head names
  /// that head alone.
  Iterable<Note> headsOf(TimedEvent timed) => switch (timed.event) {
    ChordEvent(:final notes) when items.contains(timed.ref) => notes,
    ChordEvent(:final notes) => notes.where(
      (note) => items.contains(NoteRef(timed.ref, note.id)),
    ),
    _ => const [],
  };

  /// The event before [timed] in its voice, in the bar before when [timed]
  /// opens its bar. Null at the start of the score.
  TimedEvent? before(TimedEvent timed) {
    final bar = _score.indexOf(timed.ref.measure);
    final earlier = _lane(bar, timed).takeWhile((e) => e.ref != timed.ref);
    return earlier.lastOrNull ?? _lane(bar - 1, timed).lastOrNull;
  }

  /// The event after [timed] in its voice, in the next bar when [timed]
  /// closes its bar. Null at the end of the score.
  TimedEvent? after(TimedEvent timed) {
    final bar = _score.indexOf(timed.ref.measure);
    final later = _lane(bar, timed).skipWhile((e) => e.ref != timed.ref);
    return later.skip(1).firstOrNull ?? _lane(bar + 1, timed).firstOrNull;
  }

  /// The voice of [like] in the bar at index [bar], or nothing where the
  /// score has no such bar or the bar no such voice.
  List<TimedEvent> _lane(int bar, TimedEvent like) => [
    if (bar >= 0 && bar < _score.measures.length)
      for (final staff in _score.measureView(_score.measures[bar].id).staves)
        if (staff.source.staff == like.ref.staff)
          for (final voice in staff.voices)
            if (voice.slot == like.voice) ...voice.events,
  ];

  /// The events that start in [range], on its staves.
  static List<TimedEvent> _within(
    Score score,
    RangeSelection range,
    List<StaffId> staves,
  ) {
    final first = score.indexOf(range.from.measure);
    final last = score.indexOf(range.to.measure);
    final top = staves.indexOf(range.top);
    final bottom = staves.indexOf(range.bottom);
    return [
      for (var bar = first; bar <= last; bar++)
        for (final staff in score.measureView(score.measures[bar].id).staves)
          if (staves.indexOf(staff.source.staff) case final index
              when index >= top && index <= bottom)
            for (final voice in staff.voices)
              for (final timed in voice.events)
                if ((bar > first || timed.onset >= range.from.offset) &&
                    (bar < last || timed.onset < range.to.offset))
                  timed,
    ];
  }
}

/// What a button of the action row does.
sealed class Press {
  const Press();
}

/// Runs an edit on the session.
final class RunEdit extends Press {
  const RunEdit(this.edit);

  final Edit edit;
}

/// Selects something else, which is no undo step.
final class Reselect extends Press {
  const Reselect(this.selection);

  final Selection selection;
}

/// Keeps a copy of the selection for Paste.
final class TakeCopy extends Press {
  const TakeCopy();
}

/// One button of the action row, which shows [label] under [icon]. A null
/// [press] turns the button off.
typedef SelectionAction = ({String label, IconData icon, Press? press});

/// The action row for [picked], or no button when nothing is picked.
/// [clip] is what Copy kept, and a paste crosses a bar line as [overfill]
/// says.
List<SelectionAction> selectionActions(
  Picked picked, {
  required ScoreClip? clip,
  required Overfill overfill,
}) {
  final events = picked.events;
  if (events.isEmpty) {
    return const [];
  }
  final (first, last) = (events.first, events.last);
  final (before, after) = (picked.before(first), picked.after(last));
  final (from, to) = (_startOf(first), _startOf(last));
  final staff = first.ref.staff;
  final several = events.length > 1;
  final chords = [
    for (final timed in events)
      if (timed.event is ChordEvent) timed.ref,
  ];
  final tie = _tie(picked);

  Press widenTo(TimedEvent neighbour) =>
      Reselect(ItemSelection(Seq([...picked.items, neighbour.ref])));
  Press without(TimedEvent dropped) => Reselect(
    ItemSelection(Seq(picked.items.where((item) => item.event != dropped.ref))),
  );
  Press transpose(int steps) =>
      RunEdit(Transpose(picked.selection, Transposition.diatonic(steps)));
  Press hairpin({required bool crescendo}) => RunEdit(
    AddSpanner(
      kind: Hairpin(crescendo: crescendo),
      staff: staff,
      first: from,
      last: to,
    ),
  );

  // Delete and the four buttons that widen and narrow come first, since
  // a phone shows five buttons before the row scrolls.
  return [
    (
      label: 'Delete',
      icon: Icons.delete_outline,
      press: RunEdit(Erase(picked.selection)),
    ),
    (
      label: 'Widen left',
      icon: Icons.keyboard_double_arrow_left,
      press: before == null ? null : widenTo(before),
    ),
    (
      label: 'Widen right',
      icon: Icons.keyboard_double_arrow_right,
      press: after == null ? null : widenTo(after),
    ),
    (
      label: 'Narrow left',
      icon: Icons.arrow_right,
      press: several ? without(first) : null,
    ),
    (
      label: 'Narrow right',
      icon: Icons.arrow_left,
      press: several ? without(last) : null,
    ),
    (
      label: 'Pitch down',
      icon: Icons.arrow_downward,
      press: chords.isEmpty ? null : transpose(-1),
    ),
    (
      label: 'Pitch up',
      icon: Icons.arrow_upward,
      press: chords.isEmpty ? null : transpose(1),
    ),
    (
      label: 'Octave down',
      icon: Icons.keyboard_double_arrow_down,
      press: chords.isEmpty ? null : transpose(-7),
    ),
    (
      label: 'Octave up',
      icon: Icons.keyboard_double_arrow_up,
      press: chords.isEmpty ? null : transpose(7),
    ),
    (label: 'Tie', icon: Icons.link, press: tie == null ? null : RunEdit(tie)),
    (
      label: 'Slur',
      icon: Icons.gesture,
      press: several
          ? RunEdit(
              AddSpanner(
                kind: const Slur(),
                staff: staff,
                voice: first.voice,
                first: from,
                last: to,
              ),
            )
          : null,
    ),
    (
      label: 'Beam',
      icon: Icons.call_merge,
      press: chords.length > 1
          ? RunEdit(
              Batch([
                for (final (index, chord) in chords.indexed)
                  SetBeam(chord, index == 0 ? BeamMode.begin : BeamMode.join),
              ], label: 'Beam'),
            )
          : null,
    ),
    (
      label: 'Unbeam',
      icon: Icons.call_split,
      press: chords.isEmpty
          ? null
          : RunEdit(
              Batch([
                for (final chord in chords) SetBeam(chord, BeamMode.none),
              ], label: 'Unbeam'),
            ),
    ),
    (
      label: 'Crescendo',
      icon: Icons.chevron_left,
      press: hairpin(crescendo: true),
    ),
    (
      label: 'Decrescendo',
      icon: Icons.chevron_right,
      press: hairpin(crescendo: false),
    ),
    (label: 'Copy', icon: Icons.copy, press: const TakeCopy()),
    (
      label: 'Paste',
      icon: Icons.paste,
      press: clip == null
          ? null
          : RunEdit(
              Paste(
                clip,
                at: VoicePoint(staff: staff, voice: first.voice, at: from),
                overfill: overfill,
              ),
            ),
    ),
    (
      label: 'Deselect',
      icon: Icons.deselect,
      press: const Reselect(Selection.none()),
    ),
  ];
}

ScorePoint _startOf(TimedEvent timed) =>
    ScorePoint(timed.ref.measure, timed.onset);

/// Ties each picked head onward where the next event of its voice has the
/// head's tone, because the model draws a tie to nothing as a loose end.
/// When no head is left to tie, it clears the ties the picked heads have.
/// Null when there is neither to do.
Edit? _tie(Picked picked) {
  final heads = [
    for (final timed in picked.events)
      for (final note in picked.headsOf(timed))
        (
          ref: NoteRef(timed.ref, note.id),
          tied: note.tie,
          repeats: switch (picked.after(timed)?.event) {
            ChordEvent(:final notes) => notes.any(
              (next) => next.tone == note.tone,
            ),
            _ => false,
          },
        ),
  ];
  final untied = [
    for (final head in heads)
      if (head.repeats && !head.tied) head.ref,
  ];
  final tied = [
    for (final head in heads)
      if (head.tied) head.ref,
  ];
  if (untied.isNotEmpty) {
    return Batch([
      for (final note in untied) SetTie(note, tied: true),
    ], label: 'Add tie');
  }
  if (tied.isNotEmpty) {
    return Batch([
      for (final note in tied) SetTie(note, tied: false),
    ], label: 'Remove tie');
  }
  return null;
}
