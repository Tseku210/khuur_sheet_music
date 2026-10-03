/// Score layout. Turns a `Score` into systems of positioned drawables and
/// keeps them current across edits.
///
/// Read `SheetLayout` first. All geometry is in staff spaces with y down.
/// Nothing here knows about pixels, Flutter or a platform. Text extents come
/// in through `TextMeasurer`.
library;

export 'src/drawable.dart';
export 'src/geometry.dart';
export 'src/glyphs.dart';
export 'src/hit.dart' show SheetHit;
export 'src/sheet_layout.dart';
export 'src/smufl_font.dart';
export 'src/style.dart';
export 'src/system_layout.dart';
export 'src/text.dart';
