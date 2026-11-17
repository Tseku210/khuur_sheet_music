---
title: Edit by tap
description: Select notes and lines with a tap, enter notes where the user taps, and undo and redo edits through an EditSession.
sidebar:
  order: 2
---

This guide turns taps on a `SheetView` into edits. A tap on a note or a line selects it, a tap anywhere else enters a note, and buttons undo and redo the edits.

## Keep the session in your state

Your app owns the `EditSession`. Keep it in the `State` of the widget that shows the sheet, together with a `SheetController` and the note value the user enters.

```dart
late EditSession _session = EditSession.start(widget.score);
final SheetController _sheet = SheetController();
NoteValue _value = NoteValue.quarter;

@override
void dispose() {
  _sheet.dispose();
  super.dispose();
}
```

Give the view the session's score, cursor and selection, and a tap handler.

```dart
SheetView(
  score: _session.score,
  cursor: _session.cursor,
  selection: _session.selection,
  controller: _sheet,
  tapGrid: _value.base,
  onTap: _onTap,
)
```

## Handle a tap

In this handler, a tap on a note or a line selects it, and a tap anywhere else enters a note.

```dart
void _onTap(SheetHit hit) {
  final picked = switch (hit.target) {
    ElementOwner(:final ref)
        when _session.score.lookup(ref.event)?.event is ChordEvent =>
      ItemSelection(Seq([ref])),
    SpannerOwner(:final id) => Selection.spanner(id),
    _ => null,
  };
  if (picked != null) {
    setState(() => _session = _session.select(picked));
    return;
  }
  final tone = _session.score.toneForStaffStep(hit.staff, hit.at, hit.staffStep);
  if (tone == null) return;
  _run(EnterNote(
    at: VoicePoint(staff: hit.staff, voice: hit.voice, at: hit.at),
    tone: tone,
    value: _value,
  ));
}
```

A tap on a rest enters a note too. A rest of voice one is the room its bar has left, and `Erase` leaves it as it is. An editor that selected a rest on a tap would offer nothing to do with it, and would take no note where a finger most often lands in an empty bar.

The `SheetHit` names the staff, the voice, the time and the staff step under the tap, so your app works none of them out. On a pitched staff, `toneForStaffStep` turns the staff step into a concert pitch from the clef, the key, any octave line and the instrument's transposition. On a percussion staff it gives the kit's drum at that position, or null when no drum sits there.

## Run the edit and report a refusal

Run each edit through one method. Keep the next session when the edit applies, and tell the user why when it does not.

```dart
void _run(Edit edit) {
  switch (_session.run(edit)) {
    case Applied(:final session):
      setState(() => _session = session);
    case Refused(:final reason):
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_sentence(reason))),
      );
  }
}

String _sentence(EditRefusal reason) => switch (reason) {
  StaleReference() => 'That is no longer in the score.',
  WouldSplitTuplet() => 'This would cut a tuplet in two.',
  OutsideMeasure() => 'That point is outside its bar.',
  WouldCrossBarline() => 'This note does not fit in the bar.',
  WouldEmptyScore() => 'The score would have nothing left to show.',
  InvalidValue(:final message) => message,
};
```

`EditRefusal` is sealed, so the compiler tells you when a switch misses a case.

After `EnterNote` the cursor sits at the end of the note, and the new note is selected.

## Enter the note where the finger is

On a note or a rest, the hit's time is the start of that note or rest. So the handler above enters a note tapped on a rest at the start of the rest. A note tapped on a bar rest goes to the start of the bar, though the view draws the bar rest in the middle of it.

To enter the note where the finger is, take the tap in a `GestureDetector` of your own around the view. Ask `hitTest` what is under the finger, and `entryAt` where a note would go.

```dart
void _onTapAt(Offset at) {
  final voice = _session.cursor.voice;
  final picked = switch (_sheet.hitTest(at, voice: voice)?.target) {
    ElementOwner(:final ref)
        when _session.score.lookup(ref.event)?.event is ChordEvent =>
      ItemSelection(Seq([ref])),
    SpannerOwner(:final id) => Selection.spanner(id),
    _ => null,
  };
  if (picked != null) {
    setState(() => _session = _session.select(picked));
    return;
  }
  if (_sheet.entryAt(at, voice: voice) case final hit?) {
    _enter(hit);
  }
}

GestureDetector(
  onTapUp: (details) => _onTapAt(details.localPosition),
  child: SheetView(
    score: _session.score,
    cursor: _session.cursor,
    selection: _session.selection,
    controller: _sheet,
    tapGrid: _value.base,
  ),
)
```

`_enter` is the second half of `_onTap` above, from `toneForStaffStep` to `_run`. `entryAt` looks at no drawn mark and gives a hit with no target.

## Change a clef, a key, a meter or a tempo

A clef, a key signature, a time signature and a tempo mark are not elements of the score, so a hit on one has no target, and the handlers above would enter a note there. `signatureAt` tells whether a tap is on one. Ask it first in your own tap handler, and go on to `hitTest` when it gives null.

```dart
void _onTapAt(Offset at) {
  if (_sheet.signatureAt(at) case final sign?) {
    _change(sign);
    return;
  }
  // Select a note or a line, or enter a note, as above.
}

Future<void> _change(SignatureHit sign) async {
  switch (sign.kind) {
    case SignatureKind.clef:
      if (await _pickClef() case final clef?) {
        _run(SetClef(staff: sign.staff, at: sign.at, clef: clef));
      }
    case SignatureKind.key:
      if (await _pickKey() case final key?) {
        _run(SetKey(from: sign.at.measure, key: key));
      }
    case SignatureKind.meter:
      if (await _pickMeter() case final meter?) {
        _run(SetMeter(from: sign.at.measure, meter: meter));
      }
    case SignatureKind.tempo:
      if (await _pickTempo() case final tempo?) {
        final bar = _score.measures[_score.indexOf(sign.at.measure)];
        _run(
          SetTempoMarks(
            sign.at.measure,
            Seq([
              for (final mark in bar.tempos)
                mark.offset == sign.at.offset
                    ? TempoMark(
                        offset: mark.offset,
                        tempo: tempo,
                        text: mark.text,
                        showMetronome: mark.showMetronome,
                      )
                    : mark,
            ]),
          ),
        );
      }
  }
}
```

`_pickClef`, `_pickKey`, `_pickMeter` and `_pickTempo` are your app's own choosers. `SetTempoMarks` replaces all of a bar's marks, so keep the ones the tap was not on.

The `SignatureHit` names the staff the sign is drawn on, its kind, and the point it takes effect from:

- A sign before the music of a bar names the start of that bar.
- The clef and key at the start of each system name that system's first bar, though they only restate what came before. A `SetKey` there starts the new key at that bar.
- The courtesy key and meter at the end of a system, and a courtesy clef before its last barline, name the first bar of the next system.
- A clef that changes inside a bar names the bar and the clef's offset.
- A tempo mark names its bar and its offset, whether the tap is on its words, its note or its number. It is drawn above the system's top staff and names that staff. The sheet never restates a tempo mark, and the words of a tempo line such as *rit.* belong to the line.

A note, a rest or a line drawn as near as the sign takes the tap, so a note just after a clef stays easy to select. A key signature counts as one box over all its accidentals. C major and A minor draw no key, so nothing there answers to a tap.

## Choose the tap grid

`tapGrid` is the grid a tap snaps to. It is a sixteenth unless you give another. Pass the base of the value being entered, and a note starts on a beat of its own value.

A tap within a staff space of where a note or a rest of its voice starts takes that start, whatever the grid. A long note that starts off the beats of its own value is cut at the beats and at the barline, and the model ties the pieces. That happens to a whole note that starts in the middle of a bar, on a finer grid or at such a start.

## Select and delete lines

A line is a slur, a hairpin or another spanner. `Selection.spanner(id)` selects one, and the view draws it in the selection style.

An `ItemSelection` keeps its events and heads in `items` and its lines in `spanners`, so one selection can hold both. To delete what is selected, run `Erase`.

```dart
_run(Erase(_session.selection));
```

`Erase` behaves as follows:

- It removes the lines the selection names and leaves their notes.
- It clears the notes the selection names. A note of voice one becomes a rest.
- It keeps every line the selection does not name, even one over a cleared note.

Undo brings a removed line back. To close the gap instead of leaving rests, pass `ripple: Ripple.part`, as [Show a score](/khuur_sheet_music/guides/show-a-score/) describes.

## Undo and redo

Each edit that changes the score is one undo step. `undo` and `redo` return a new session, and `canUndo` and `canRedo` say whether there is a step.

```dart
IconButton(
  tooltip: switch (_session.undoLabel) {
    final label? => 'Undo $label',
    null => 'Undo',
  },
  icon: const Icon(Icons.undo),
  onPressed: _session.canUndo
      ? () => setState(() => _session = _session.undo())
      : null,
),
IconButton(
  tooltip: switch (_session.redoLabel) {
    final label? => 'Redo $label',
    null => 'Redo',
  },
  icon: const Icon(Icons.redo),
  onPressed: _session.canRedo
      ? () => setState(() => _session = _session.redo())
      : null,
),
```

`undoLabel` and `redoLabel` are the `label` of the edit, a short English name such as `Delete`. Translate them by the type of the edit if your app is not in English.

Undo and redo bring back the cursor and the selection with the score. Any edit that changes the score clears the redo steps. An edit that leaves the score as it was applies without an undo step. `EditSession.start` keeps 200 undo steps unless you pass another `historyLimit`, and drops the oldest past that.

## Move the cursor

The view draws the cursor as a caret. It opens with the cursor's system in view, and scrolls that system into view when the cursor moves. To move the cursor from a button, call `moveCursor`.

```dart
setState(() => _session = _session.moveCursor(CursorMove.nextEvent));
```

`CursorMove` also has `previousEvent`, `nextMeasure`, `previousMeasure`, `staffUp` and `staffDown`. To put the cursor at a given point, call `placeCursor`. Neither is an undo step.

## Zoom

To zoom, set the controller's `zoom`.

```dart
_sheet.zoom *= 1.25;
```

Each new zoom breaks the lines again over the whole score. If your app zooms by pinch, set `zoom` when the gesture ends.

## Related pages

- [Your first sheet](/khuur_sheet_music/tutorial/first-sheet/) enters notes by tap from a blank page.
- [Show where a note will go](/khuur_sheet_music/guides/note-preview/) shows the note under a held finger before it is entered.
- [Draw the sheet's glyphs in your own widgets](/khuur_sheet_music/guides/glyphs-in-your-widgets/) draws the keys of a key chooser as the sheet draws them.
- [Place widgets over the sheet](/khuur_sheet_music/guides/widgets-over-the-sheet/) puts a delete button at the selected note.
- [Show a score](/khuur_sheet_music/guides/show-a-score/) lists the edits and how entry fits notes into bars.
- [The score model](/khuur_sheet_music/explanation/score-model/) explains sessions, edits and undo.
