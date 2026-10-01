/// Recovers the accidentals and beams a MusicXML file states, which the
/// model otherwise derives. Internal to the package.
library;

import '../beaming.dart';
import '../events.dart';
import '../measure.dart';
import '../measure_view.dart';
import '../refs.dart';
import '../score.dart';
import '../seq.dart';
import '../time.dart';
import '../views.dart';
import 'musicxml_records.dart';

/// [score] with the accidental requests and beam modes that make its views
/// print what [document] prints.
Score withOverrides(Score score, DocumentRecord document) {
  // The views leave hidden parts out.
  final shown = score.copyWith(
    parts: Seq([
      for (final part in score.parts) part.copyWith(hidden: false),
    ]),
  );
  final accidentals = <NoteId, AccidentalRequest>{};
  final beams = <EventId, BeamMode>{};
  for (final column in shown.measures) {
    for (final staff in shown.measureView(column.id).staves) {
      foldAccidentals(
        accidentalHeads([for (final voice in staff.voices) voice.events]),
        staff.writtenPitches,
        staff.tiedIn.toSet(),
        staff.writtenKey,
        request: (note, {required autoPrints}) {
          final request = _request(document, note.id, autoPrints: autoPrints);
          if (request != AccidentalRequest.auto) {
            accidentals[note.id] = request;
          }
          return request;
        },
      );
      if (document.joins case final joins?) {
        for (final voice in staff.voices) {
          beams.addAll(_beamModes(voice.events, column.meter, joins));
        }
      }
    }
  }
  if (accidentals.isEmpty && beams.isEmpty) {
    return score;
  }

  Seq<Note> notes(Seq<Note> notes) => Seq([
    for (final note in notes)
      switch (note) {
        PitchedNote(:final id) => note.copyWith(accidental: accidentals[id]),
        DrumNote() => note,
      },
  ]);
  Content content(Content item) => switch (item) {
    ChordEvent() => item.copyWith(
      beam: beams[item.id],
      notes: notes(item.notes),
      graces: Seq([
        for (final grace in item.graces)
          GraceChord(
            id: grace.id,
            kind: grace.kind,
            value: grace.value,
            notes: notes(grace.notes),
          ),
      ]),
    ),
    RestEvent() || MeasureRest() => item,
    Tuplet() => Tuplet(
      id: item.id,
      ratio: item.ratio,
      unit: item.unit,
      members: Seq(item.members.map(content)),
      bracket: item.bracket,
    ),
  };
  return score.copyWith(
    measures: Seq([
      for (final column in score.measures)
        column.copyWith(
          staves: Seq([
            for (final staff in column.staves)
              staff.copyWith(
                voices: Seq([
                  for (final voice in staff.voices)
                    Voice(
                      slot: voice.slot,
                      items: Seq([
                        for (final item in voice.items)
                          switch (item) {
                            Gap() => item,
                            Content() => content(item),
                          },
                      ]),
                    ),
                ]),
              ),
          ]),
        ),
    ]),
  );
}

/// The request that makes the fold print what the file prints on [note].
/// The fold asks in the order it reads the heads, so [autoPrints] already
/// counts the requests given to the heads before.
AccidentalRequest _request(
  DocumentRecord document,
  NoteId note, {
  required bool autoPrints,
}) => switch (document.printed[note]) {
  true => AccidentalRequest.cautionary,
  false => autoPrints ? AccidentalRequest.auto : AccidentalRequest.always,
  null =>
    document.supportsAccidentals && autoPrints
        ? AccidentalRequest.never
        : AccidentalRequest.auto,
};

/// The beam modes that make one voice's [events] group as the file beams
/// them, where [joins] says whether each chord joins the chord before.
///
/// A mode is given to the first chord that groups otherwise, and the voice
/// is regrouped. `begin` always parts a chord from the one before, and
/// `join` always joins it when both carry a beam, so a chord given a mode
/// stays right and each is given one at most once.
Map<EventId, BeamMode> _beamModes(
  List<TimedEvent> events,
  Meter meter,
  Map<EventId, bool> joins,
) {
  final current = [...events];
  final chords = [
    for (final (i, timed) in events.indexed)
      if (timed.event case final ChordEvent chord) (index: i, chord: chord),
  ];
  final modes = <EventId, BeamMode>{};
  final unbeamable = <EventId>{};
  while (true) {
    final joined = {
      for (final group in beamGroups(current, meter)) ...group.events.skip(1),
    };
    final wrong = chords.indexWhere(
      (at) =>
          !modes.containsKey(at.chord.id) &&
          !unbeamable.contains(at.chord.id) &&
          joined.contains(at.chord.id) != (joins[at.chord.id] ?? false),
    );
    if (wrong < 0) {
      return modes;
    }
    final (:index, :chord) = chords[wrong];
    final BeamMode mode;
    if (joined.contains(chord.id)) {
      mode = BeamMode.begin;
    } else if (chord.value.base.beams > 0 &&
        wrong > 0 &&
        chords[wrong - 1].chord.value.base.beams > 0) {
      mode = BeamMode.join;
    } else {
      unbeamable.add(chord.id);
      continue;
    }
    modes[chord.id] = mode;
    final timed = current[index];
    current[index] = TimedEvent(
      ref: timed.ref,
      voice: timed.voice,
      event: chord.copyWith(beam: mode),
      onset: timed.onset,
      duration: timed.duration,
      tuplets: timed.tuplets,
    );
  }
}
