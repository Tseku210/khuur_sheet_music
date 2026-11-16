## 0.3.1
* `SheetLayout.playingIn` takes the column's width from the playing events other than a `MeasureRest`, which is centred in its bar and not drawn at its onset. On a downbeat where one staff plays a note and another holds a bar rest, the column reached the bar's middle and covered notes that had not started. A bar rest still gives the column its width when nothing else started with it.

## 0.3.0
* First release on pub.dev. Earlier versions were part of [`khuur_sheet_music`](https://github.com/Tseku210/khuur_sheet_music), as `score_layout`. Its CHANGELOG lists their changes.
* Every public member has a doc comment, so the API reference covers the whole package. The `public_member_api_docs` lint keeps it that way.
