import 'package:score_layout/src/assembly.dart';
import 'package:score_layout/src/sheet_layout.dart';
import 'package:score_layout/src/system_layout.dart';
import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

/// Every placed bar of [system] as a list, since a record holding a list
/// is not equal to another by value.
List<List<Object>> describeBars(SystemLayout system) => [
  for (final bar in system.bars)
    [bar.measure, bar.left, bar.right, '${bar.length}', ...bar.time.stops],
];

List<(StaffId, double, int)> describeStaves(SystemLayout system) => [
  for (final staff in system.staves) (staff.staff, staff.top, staff.lines),
];

void expectSameSystem(SystemLayout actual, SystemLayout fresh) {
  expect(actual.width, fresh.width);
  expect(actual.height, fresh.height);
  expect(actual.drawables, fresh.drawables);
  expect(describeBars(actual), describeBars(fresh));
  expect(describeStaves(actual), describeStaves(fresh));
}

void expectSameSheet(SheetLayout actual, SheetLayout fresh) {
  expect(actual.width, fresh.width);
  expect(actual.header, fresh.header);
  expect(actual.systemCount, fresh.systemCount);
  expect(actual.tops, fresh.tops);
  for (var i = 0; i < fresh.systemCount; i++) {
    expect(actual.firstBarOf(i), fresh.firstBarOf(i));
    expect(actual.heightOf(i), fresh.heightOf(i));
    expect(actual.labelOf(i), fresh.labelOf(i));
    expectSameSystem(actual.systemAt(i), fresh.systemAt(i));
  }
}

void expectInsideBands(SheetLayout layout) {
  for (var i = 0; i < layout.systemCount; i++) {
    final system = layout.systemAt(i);
    final label = layout.labelOf(i);
    for (final drawable in [...system.drawables, ?label]) {
      final box = drawable.bounds;
      expect(
        box.left >= -bandTolerance &&
            box.right <= system.width + bandTolerance &&
            box.top >= -bandTolerance &&
            box.bottom <= system.height + bandTolerance,
        isTrue,
        reason:
            '$drawable of system $i lies outside '
            '${system.width} by ${system.height}',
      );
    }
  }
}

/// The systems of [layout] holding a bar of [measures], and the system
/// before each, whose courtesy signatures come from the bar after it.
Set<int> systemsTouchedBy(SheetLayout layout, Iterable<MeasureId> measures) => {
  for (final measure in measures)
    if (layout.systemOf(measure) case final index?) ...[
      index,
      if (index > 0) index - 1,
    ],
};
