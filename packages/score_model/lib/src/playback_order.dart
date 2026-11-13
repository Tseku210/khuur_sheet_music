part of 'playback.dart';

/// Unrolls repeats, voltas and navigation into (bar index, pass) pairs,
/// where pass counts the times the bar has played, this one included.
///
/// An end repeat returns to the last start repeat, or to the bar after the
/// previous repeated section, or to the score start. A bar under a volta
/// plays on the passes its endings list. A section being repeated ends
/// after its end repeat, or after the last bar of the endings that hold its
/// end repeat. A [Jump] is taken once, after the repeats of its bar are
/// done. A D.S. without a [Segno] goes to the start. After the jump,
/// repeats are not taken, a bar under a volta plays only if it is under
/// the last ending of its run, and the jump's [JumpThen] says whether [Fine] stops or
/// [ToCoda] leaves for the [Coda], once. A loop guard stops at 64 × bar
/// count.
List<({int index, int pass})> _playOrder(Seq<MeasureColumn> measures) {
  final segno = measures.indexWhere(
    (c) => c.navigation.contains(const Segno()),
  );
  final coda = measures.indexWhere((c) => c.navigation.contains(const Coda()));
  final plays = List.filled(measures.length, 0);
  final order = <({int index, int pass})>[];
  var i = 0;
  var pass = 1;
  var start = 0;
  int? sectionEnd;
  Jump? jump;
  var codaTaken = false;
  while (i < measures.length && order.length < 64 * measures.length) {
    final column = measures[i];
    if ((sectionEnd != null && i > sectionEnd) ||
        (column.repeatStart && i != start)) {
      pass = 1;
      start = i;
      sectionEnd = null;
    }
    final volta = column.volta;
    if (volta != null &&
        (jump == null
            ? !volta.endings.contains(pass)
            : volta != measures[_endingsEnd(measures, i)].volta)) {
      i++;
      continue;
    }
    order.add((index: i, pass: ++plays[i]));
    final marks = column.navigation;
    if (jump != null) {
      if (jump.then == JumpThen.toFine && marks.contains(const Fine())) {
        break;
      }
      if (jump.then == JumpThen.toCoda &&
          marks.contains(const ToCoda()) &&
          coda >= 0 &&
          !codaTaken) {
        codaTaken = true;
        i = coda;
        continue;
      }
    } else {
      final end = column.repeatEnd;
      if (end != null && pass < end.times) {
        pass++;
        sectionEnd = _endingsEnd(measures, i);
        i = start;
        continue;
      }
      jump = marks.whereType<Jump>().firstOrNull;
      if (jump != null) {
        i = jump.target == JumpTarget.segno && segno >= 0 ? segno : 0;
        continue;
      }
    }
    i++;
  }
  return order;
}

/// The last bar of the run of volta bars holding bar [i], or [i] when it
/// has no volta.
int _endingsEnd(Seq<MeasureColumn> measures, int i) {
  var end = i;
  while (measures[end].volta != null &&
      end + 1 < measures.length &&
      measures[end + 1].volta != null) {
    end++;
  }
  return end;
}

/// The bars of `[from, to)` in notated order, once, each with the part of
/// it that plays.
List<({int index, int pass, Moment from, Moment to})> _range(
  Score score,
  ScorePoint? from,
  ScorePoint? to,
) {
  final first = from == null ? 0 : score.indexOf(from.measure);
  final last = to == null
      ? score.measures.length - 1
      : score.indexOf(to.measure);
  return [
    for (var i = first; i <= last; i++)
      if ((
            index: i,
            pass: 1,
            from: i == first && from != null ? from.offset : Moment.zero,
            to: i == last && to != null
                ? to.offset
                : Moment.zero + score.measures[i].length,
          )
          case final window when window.from < window.to)
        window,
  ];
}
