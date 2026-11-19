/// The rule across bars for measure-repeat signs. See [MeasureRepeat].
library;

import 'measure.dart';
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
/// back through any sign that bar is under.
int playedBar(Seq<MeasureColumn> measures, int bar, int staff) {
  var source = bar;
  for (
    var sign = measures[source].staves[staff].measureRepeat;
    sign != null;
    sign = measures[source].staves[staff].measureRepeat
  ) {
    source -= sign.bars;
  }
  return source;
}
