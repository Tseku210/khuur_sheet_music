---
title: Show where a note will go
description: Draw the note a held finger would enter, enter it when the finger lifts, and magnify it beside the finger.
sidebar:
  order: 3
---

This guide draws the note under a held finger before the note is entered, and enters it when the finger lifts. A finger hides the place it points at, so a touch editor shows the note first.

The guide builds on the session and the `_run` method of [Edit by tap](/khuur_sheet_music/guides/edit-by-tap/).

## Show the note while the finger is held

`SheetView.onHold` reports a held finger and where a note entered there would go. `SheetView.preview` draws a note that is not in the score. `SheetView.onRelease` reports where the note goes when the finger lifts.

1. Keep the hold in your state.

   ```dart
   EntryHold? _hold;
   ```

2. Pass the three to the view. Build the preview from the hold's entry, and enter the note on release.

   ```dart
   SheetView(
     score: _session.score,
     cursor: _session.cursor,
     controller: _sheet,
     tapGrid: _value.base,
     preview: switch (_hold?.entry) {
       final hit? => NotePreview.at(hit, base: _value.base),
       null => null,
     },
     onHold: (hold) => setState(() => _hold = hold),
     onRelease: _enter,
   )
   ```

3. In `_enter`, check that the score still has the bar before you enter the note.

   ```dart
   void _enter(SheetHit hit) {
     if (!_session.score.contains(hit.at.measure)) return;
     final tone = _session.score.toneForStaffStep(hit.staff, hit.at, hit.staffStep);
     if (tone == null) return;
     _run(EnterNote(
       at: VoicePoint(staff: hit.staff, voice: hit.voice, at: hit.at),
       tone: tone,
       value: _value,
     ));
   }
   ```

   The hit is about the sheet on screen, which is a frame behind any change your app makes to the score. If your app can take a bar away under a held finger, with an undo for example, the bar may be gone.

The view recognizes a long press only when `onHold` or `onRelease` is set. It calls `onHold` as follows:

- With a hold when the long press starts, each time the finger moves, and each time the sheet moves under the finger. The sheet moves when it scrolls, zooms or is laid out again.
- With null when the hold ends, and when the finger slides off the view.
- With a hold again when the finger slides back on.

The entry of a hold is for the cursor's voice, or voice one with no cursor. It is null off every system.

`onRelease` comes after `onHold` reports null. The view asks for the entry again as the finger lifts, for the sheet on screen then. The view does not call `onRelease` when the finger lifts off the view or off every system, or when Flutter cancels the hold.

Nothing in the sheet moves for the preview.

## Know what the preview shows

The preview is the note of its `base` as it stands alone in its bar:

- A whole note has no stem. A half note and a quarter have a stem. An eighth and every shorter value have a stem and a flag.
- The stem goes up for a note under the middle line, and down for every other.
- It has its ledger lines, and no dot and no accidental.
- It is drawn in the palette's `preview` colour, or in the cursor's colour when the palette has none. The palette the view takes from the theme has none.

A note that is entered may get a beam, or a stem direction from its voice, that the preview does not show.

## Show a drum's head

A drum's note has the head of its kit sound. Pass that head to `NotePreview.at`. This builder also gives no preview where no note can go.

```dart
NotePreview? _previewAt(SheetHit hit) {
  final score = _session.score;
  if (!score.contains(hit.at.measure)) return null;
  return switch (score.toneForStaffStep(hit.staff, hit.at, hit.staffStep)) {
    null => null,
    Pitch() => NotePreview.at(hit, base: _value.base),
    final Drum drum => NotePreview.at(
      hit,
      base: _value.base,
      head: score.partOf(hit.staff).instrument.soundOf(drum)!.head,
    ),
  };
}
```

## Magnify the note beside the finger

The package has no magnifying glass. To add one, put Flutter's `RawMagnifier` in a `Stack` over the view, near the finger.

Point the glass at the middle of `SheetController.rectOfPreview`, the box of the preview with its stem, its flag and its ledger lines. A long value starts on a beat that can be far from the finger, and a glass that looked at the finger would miss the note.

```dart
static const Size _glass = Size(132, 88);

Positioned _glassAt(Offset finger, NotePreview? preview) {
  final centre = finger - Offset(0, _glass.height);
  final note = switch (preview) {
    final preview? => _sheet.rectOfPreview(preview),
    null => null,
  };
  return Positioned.fromRect(
    rect: Rect.fromCenter(
      center: centre,
      width: _glass.width,
      height: _glass.height,
    ),
    child: RawMagnifier(
      size: _glass,
      magnificationScale: 2,
      focalPointOffset: (note?.center ?? finger) - centre,
    ),
  );
}
```

Build it from the hold's finger, over the view. `sheetView` is the `SheetView` above, with `preview` passed as its preview.

```dart
final preview = switch (_hold?.entry) {
  final hit? => _previewAt(hit),
  null => null,
};

Stack(
  children: [
    sheetView,
    if (_hold?.finger case final finger?) _glassAt(finger, preview),
  ],
)
```

The glass in this sample stays above the finger. The example app's [`main.dart`](https://github.com/Tseku210/khuur_sheet_music/blob/main/example/lib/main.dart) also moves it beside the finger near the top of the sheet. A zoomed note can be taller than the glass shows, and the example then keeps the head in the glass.

## Ask for an entry from your own gesture

`SheetController.entryAt` gives the same entry for any point, for a gesture other than a long press on the view. `hitTest` answers what a tap there would select, and gives the time of a note or a rest it lands on. `entryAt` looks at no drawn mark. A bar rest is drawn in the middle of its bar and starts at the bar's start, so a preview from `hitTest` would stand a long way from the finger. Both snap to `tapGrid` by the same rule.

If your app keeps a hit from `entryAt`, ask again after a scroll, a zoom or a new `tapGrid`. The same place on screen then has another entry. The controller notifies its listeners of each.

## Related pages

- [Edit by tap](/khuur_sheet_music/guides/edit-by-tap/) sets up the session and the edits this guide runs.
- [Place widgets over the sheet](/khuur_sheet_music/guides/widgets-over-the-sheet/) covers the other geometry the controller reports.
- [Change the look](/khuur_sheet_music/guides/change-the-look/) sets the palette, its `preview` colour included.
