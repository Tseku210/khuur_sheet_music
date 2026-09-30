// The caller's view, written before the type sketch. The sketch is derived
// from these call sites; when the two disagree, the sketch changes.
//
// # score_model quickstart
//
// A `Score` is an immutable value shaped like a MusicXML "score-timewise"
// document: a global list of `MeasureColumn`s. A column owns the bar-level
// facts every staff shares (meter, key, barline, repeats, volta, tempo,
// navigation marks). Inside it, each staff has voices, and each voice holds
// items that fill the bar exactly. Things that cross barlines (slurs,
// hairpins, 8va lines) live beside the columns in `Score.spanners`.
//
//     final score = Score.blank(
//       title: 'Жороо морь',
//       parts: [PartTemplate(name: 'Морин хуур', instrument: Instrument.morinKhuur)],
//       measureCount: 8,
//       meter: Meter.fourFour,
//       key: const KeySignature(-1),
//     );
//
// You never mutate a score. Run `Edit`s through an `EditSession`. Each run
// returns `Applied` (a new session: score, cursor, selection, undo history)
// or `Refused` (the old session plus the reason).
//
//     var session = EditSession.start(score);
//     session = session.run(EnterNote(
//       at: session.cursor,
//       pitch: Pitch.parse('F4'),
//       value: NoteValue.quarter,
//     )).session;
//
// Layout reads one `MeasureView` at a time and asks which measures changed.
// Playback compiles a `PlaybackScript` of timed MIDI notes that point back at
// the events that produced them. Persistence is `scoreToJson`/`scoreFromJson`.

// ignore_for_file: avoid_print, unused_local_variable, unreachable_from_main

import 'dart:convert';

import 'package:score_model/score_model.dart';

void main() {
  final score = Score.blank(
    title: 'Жороо морь',
    parts: [
      const PartTemplate(name: 'Морин хуур', instrument: Instrument.morinKhuur),
    ],
    measureCount: 8,
    key: const KeySignature(-1),
  );

  final composer = ComposerController(score);
  final layout = LayoutCache()..sync(composer.score);
  composer.addListener(() => layout.sync(composer.score));

  // Pattern 1: tap the second space of the staff (A4 in treble clef) in bar 1.
  final staff = composer.score.staves.first.id;
  final bar1 = composer.score.measures.first.id;
  composer
    ..onStaffTap((
      staff: staff,
      at: ScorePoint(bar1, Moment.zero),
      staffStep: 3,
    ))
    // Pattern 2: stack C5 on the note just entered.
    ..addPitch(Pitch.parse('C5'))
    // Pattern 4.
    ..undo()
    ..redo();

  // Pattern 6: play it.
  final player = PlayerSketch()..play(composer.score);
  final lit = player.highlightAt(0.25);

  // Pattern 7: save and load keep every id.
  final text = jsonEncode(scoreToJson(composer.score));
  final loaded = scoreFromJson(jsonDecode(text));
  assert(loaded.measures.first.id == bar1);
}

// ---------------------------------------------------------------------------
// Composer screen controller. In the app this extends ChangeNotifier and is
// read with context.watch; here a plain listener list stands in for it.
// ---------------------------------------------------------------------------

/// What the layout engine's hit test returns for a tap on a staff. Owned by
/// the layout package, not by the model; mirrored here as a record.
typedef StaffHit = ({StaffId staff, ScorePoint at, int staffStep});

class ComposerController {
  ComposerController(Score score) : _session = EditSession.start(score);

  EditSession _session;
  Clip? _clipboard;
  final List<void Function()> _listeners = [];

  /// Palette state. Plain UI state, not part of the model.
  NoteValue inputValue = NoteValue.quarter;
  VoiceSlot inputVoice = VoiceSlot.one;
  bool chordMode = false;

  /// A setting. `Overfill.refuse` gives Maestro's "need a bar line".
  Overfill overfill = Overfill.splitAndTie;

  /// The last refusal, shown as a toast ("this would split a triplet", or
  /// "need a bar line" for `WouldCrossBarline`).
  EditRefusal? lastRefusal;

  Score get score => _session.score;
  VoicePoint get cursor => _session.cursor;
  Selection get selection => _session.selection;
  bool get canUndo => _session.canUndo;
  bool get canRedo => _session.canRedo;
  String? get undoLabel => _session.undoLabel;

  void addListener(void Function() listener) => _listeners.add(listener);

  void notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  // Pattern 1: tap to enter a note. The layout resolved the tap to a staff,
  // a measure, an offset and a staff step. The model turns the staff step
  // into a concert pitch using the clef, key, 8va line and instrument
  // transposition in effect there, then overwrites the voice at that point.
  // The session advances the cursor past the new note and selects it.
  void onStaffTap(StaffHit hit) {
    final pitch = score.pitchForStaffStep(hit.staff, hit.at, hit.staffStep);
    final at = VoicePoint(staff: hit.staff, voice: inputVoice, at: hit.at);
    final under = score.eventAt(at);
    if (chordMode && under != null && under.onset == hit.at.offset) {
      _run(AddToChord(event: under.ref, pitch: pitch));
    } else {
      _run(
        EnterNote(
          at: at,
          pitch: pitch,
          value: inputValue,
          overfill: overfill,
        ),
      );
    }
  }

  void enterRest() => _run(EnterRest(at: cursor, value: inputValue));

  // Pattern 2: add a pitch to the event under the cursor. After EnterNote the
  // session selects the new event, so that is the target; otherwise the
  // event that covers the cursor.
  void addPitch(Pitch pitch) {
    final target = selection.singleEvent ?? score.eventAt(cursor)?.ref;
    if (target == null) {
      return;
    }
    _run(AddToChord(event: target, pitch: pitch));
  }

  // Pattern 3: range select, copy, paste, transpose.
  void selectRange(
    ScorePoint from,
    ScorePoint to,
    StaffId top,
    StaffId bottom,
  ) {
    _session = _session.select(
      RangeSelection(from: from, to: to, top: top, bottom: bottom),
    );
    notifyListeners();
  }

  void copy() => _clipboard = _session.copy();

  void paste() {
    final clip = _clipboard;
    if (clip == null) {
      return;
    }
    _run(Paste(clip, at: cursor));
  }

  void transposeDiatonic(int steps) =>
      _run(Transpose(selection, Transposition.diatonic(steps)));

  void transposeChromatic(int semitones) =>
      _run(Transpose(selection, Transposition.chromatic(semitones)));

  // Pattern 4.
  void undo() {
    _session = _session.undo();
    notifyListeners();
  }

  void redo() {
    _session = _session.redo();
    notifyListeners();
  }

  // Pattern 8: 4/4 to 3/4 from bar [from] onward. `MeterContent.rebar`
  // re-bars the music up to the next meter change, section by section, and
  // is refused if a tuplet would straddle a new barline. `keepBars` keeps
  // every bar where it is and is refused if a bar still holds too much.
  void changeMeter(
    MeasureId from,
    Meter meter, {
    MeterContent content = MeterContent.rebar,
  }) => _run(SetMeter(from: from, meter: meter, content: content));

  // Pattern 9 needs no special call. With the default overfill policy,
  // EnterNote with a half note on beat 4 splits the note at the barline and
  // ties it into the next bar. With `Overfill.refuse` the same tap comes back
  // as `Refused(WouldCrossBarline)`, handled in `_run`.

  // Palette actions a morin khuur composer needs.
  void toggleArticulation(Articulation articulation) {
    final target = selection.singleEvent;
    if (target == null) {
      return;
    }
    final present =
        score.lookup(target)?.event.articulations.contains(articulation) ??
        false;
    _run(SetArticulation(target, articulation, present: !present));
  }

  void setString(NoteRef note, int? string) => _run(SetString(note, string));

  void setBowing(Bowing? bowing) {
    final target = selection.singleEvent;
    if (target != null) {
      _run(SetBowing(target, bowing));
    }
  }

  void slurSelection() {
    if (selection case RangeSelection(:final from, :final to, :final top)) {
      _run(
        AddSpanner(
          kind: const Slur(),
          staff: top,
          voice: inputVoice,
          first: from,
          last: to,
        ),
      );
    }
  }

  void addRepeat(MeasureId first, MeasureId last) => _run(
    Batch([
      SetRepeatStart(first, start: true),
      SetRepeatEnd(last, const RepeatEnd()),
    ], label: 'Repeat'),
  );

  void _run(Edit edit) {
    switch (_session.run(edit)) {
      case Applied(:final session):
        _session = session;
        lastRefusal = null;
      case Refused(:final reason):
        lastRefusal = reason;
    }
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Layout-engine consumer (pattern 5). Caches one layout per measure id and
// relays out only what `changesSince` reports.
// ---------------------------------------------------------------------------

/// Stand-in for the layout engine's per-measure result.
typedef MeasureLayout = List<String>;

class LayoutCache {
  Score? _laidOut;
  final Map<MeasureId, MeasureLayout> _measures = {};

  void sync(Score score) {
    final previous = _laidOut;
    final changes = previous == null
        ? ScoreChanges.all(score)
        : score.changesSince(previous);
    changes.removed.forEach(_measures.remove);
    for (final id in changes.relayout) {
      _measures[id] = _layoutMeasure(score.measureView(id));
    }
    if (changes.reflow) {
      // Measure order or a width changed: re-run line breaking over the
      // cached measure widths. No measure is laid out again for this.
    }
    _laidOut = score;
  }

  MeasureLayout _layoutMeasure(MeasureView view) {
    final out = <String>[];
    final column = view.column;
    if (view.meterChanged) {
      out.add('time ${column.meter}');
    }
    if (view.keyChanged) {
      out.add('key ${column.key} (was ${view.previousKey})');
    }
    if (column.repeatStart) {
      out.add('|:');
    }
    if (view.isRestOnly) {
      out.add('candidate for a multi-measure rest');
    }

    for (final staff in view.staves) {
      if (staff.clefChanged) {
        out.add('clef ${staff.clef}');
      }
      for (final change in staff.source.clefChanges) {
        out.add('clef ${change.clef} at ${change.offset}');
      }
      for (final voice in staff.voices) {
        for (final placed in voice.events) {
          switch (placed.event) {
            case ChordEvent(:final notes, :final value):
              for (final note in notes) {
                final written = staff.writtenPitches[note.id];
                final accidental = staff.accidentals[note.id];
                out.add(
                  '$written $value at ${placed.onset} '
                  '${accidental == null ? '' : 'acc ${accidental.alter}'}',
                );
              }
            case RestEvent(:final value):
              out.add('rest $value at ${placed.onset}');
            case MeasureRest():
              out.add('measure rest');
          }
        }
        for (final beam in voice.beams) {
          out.add('beam ${beam.events}');
        }
        for (final tuplet in voice.tuplets) {
          out.add('tuplet ${tuplet.tuplet.ratio} over ${tuplet.events}');
        }
      }
      for (final tie in staff.ties) {
        out.add(
          'tie ${tie.from} -> ${tie.to} '
          '${tie.crossesBarline ? '(half, continues)' : ''}',
        );
      }
      for (final note in staff.tiedIn) {
        out.add('tie arrives at $note');
      }
      for (final direction in staff.source.directions) {
        out.add('direction at ${direction.offset}');
      }
    }
    for (final segment in view.spanners) {
      out.add(
        '${segment.spanner.kind} ${segment.from}..${segment.to} '
        'start=${segment.startsHere} end=${segment.endsHere}',
      );
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Playback consumer (pattern 6). The compiler is long-lived so it can keep
// its per-measure fragment cache across edits.
// ---------------------------------------------------------------------------

class PlayerSketch {
  final PlaybackCompiler _compiler = PlaybackCompiler();
  PlaybackScript? _script;

  void play(Score score, {Selection? section, bool loop = false}) {
    final options = switch (section) {
      RangeSelection(:final from, :final to) => PlaybackOptions(
        from: from,
        to: to,
      ),
      _ => const PlaybackOptions(),
    };
    final script = _script = _compiler.compile(score, options);
    for (final channel in script.channels) {
      print('program ${channel.program} on channel ${channel.channel}');
    }
    // A real player reads windows ahead of a monotonic clock instead of
    // chaining timers, and wraps to 0 when `loop` is set.
    for (final note in script.notesBetween(0, 0.5)) {
      print(
        '${note.start}s key ${note.key}+${note.cents}c vel ${note.velocity} '
        'for ${note.duration}s ch ${note.channel} from ${note.source.id}',
      );
    }
  }

  /// Playhead to events, for highlighting. One entry per sounding event.
  List<EventRef> highlightAt(double seconds) =>
      _script?.sourcesAt(seconds) ?? const [];

  /// Start playback at the cursor.
  double startTimeFor(ScorePoint point) => _script?.secondsAt(point) ?? 0;
}
