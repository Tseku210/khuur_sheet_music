---
title: Place widgets over the sheet
description: Put your own widgets over a SheetView at a note, a selection, the cursor or a preview, and keep them in place as the sheet scrolls and zooms.
sidebar:
  order: 5
---

This guide places your own widgets over a `SheetView`, such as a delete button at the selected note. The `SheetController` reports where things are drawn, and tells you when they move.

## Put a button at the selected note

1. Wrap the view in a `ListenableBuilder` that listens to the controller.
2. In the builder, ask the controller where the note is.
3. Put the view and your widget in a `Stack`, with the view first.

```dart
ListenableBuilder(
  listenable: _sheet,
  builder: (context, child) {
    final rect = switch (_session.selection.singleEvent) {
      final event? => _sheet.rectOf(event),
      null => null,
    };
    return Stack(children: [
      child!,
      if (rect != null)
        Positioned(
          left: rect.right,
          top: rect.top - 32,
          child: IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.close),
            onPressed: () => _run(Erase(_session.selection)),
          ),
        ),
    ]);
  },
  child: SheetView(
    score: _session.score,
    selection: _session.selection,
    controller: _sheet,
  ),
)
```

`_session` and `_run` are the ones of [Edit by tap](/khuur_sheet_music/guides/edit-by-tap/). `singleEvent` is the selected event when exactly one event, or one head of one chord, is selected.

The controller notifies its listeners when a scroll, a zoom or a new layout moves what it reports, and when a new `tapGrid` changes what a point means. So the button stays at the note.

## Ask for the geometry you need

Every answer is in the view's local logical pixels, with the scroll applied, so it fits a `Stack` whose first child is the view.

Pick the call for what your widget stands next to:

- For a note or an event, call `rectOf(ref)`.
- For a selection, call `rectsOf(selection)`. It gives the boxes the view marks, with a box for a line on each system the line crosses. The padding of the selection style is not in them.
- For the cursor, call `caretOf(cursor)`. It gives the caret, a box of no width over the cursor's staff.
- For a `NotePreview`, call `rectOfPreview(preview)`. It gives the box of the note with its stem, its flag and its ledger lines.

`rectOf`, `caretOf` and `rectOfPreview` return null for something the view does not draw, such as a note on a hidden staff. `rectsOf` leaves it out.

## Place a widget at a selection of several items

A selection of several notes, or of a line that crosses systems, has several boxes. This builder puts a row of actions over the first one.

```dart
ListenableBuilder(
  listenable: _sheet,
  builder: (context, child) {
    final first = _sheet.rectsOf(_session.selection).firstOrNull;
    return Stack(children: [
      child!,
      if (first != null)
        Positioned(left: first.left, top: first.top - 48, child: actions),
    ]);
  },
  child: SheetView(
    score: _session.score,
    selection: _session.selection,
    controller: _sheet,
  ),
)
```

## Know when the answers change

The controller answers about the sheet on screen:

- Before the view's first frame, and while no view has the controller, every query answers null, an empty list or zero.
- A new zoom notifies at once, while the sheet on screen is still the one laid out at the old zoom. It notifies again after the frame that lays out at the new zoom.
- A new score your app gives the view is on screen after the next frame. Until then, answers are about the score before it.

The view itself listens only to the zoom. A scroll or a new layout notifies your listeners and builds nothing in the view.

Views can share a controller. The queries are then for the view that took the controller last, of those that still have it.

## Related pages

- [Edit by tap](/khuur_sheet_music/guides/edit-by-tap/) sets up the session and the selection.
- [Show where a note will go](/khuur_sheet_music/guides/note-preview/) points a magnifying glass at `rectOfPreview`.
- [Export an image](/khuur_sheet_music/guides/export-an-image/) draws the sheet without the cursor and the selection.
- [Use the sheet's glyphs in your widgets](/khuur_sheet_music/guides/glyphs-in-your-widgets/) draws notes and rests in your own widgets with the sheet's font.
