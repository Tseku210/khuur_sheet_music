/// New empty bars. Internal to the package.
library;

import 'events.dart';
import 'measure.dart';
import 'pitch.dart';
import 'refs.dart';
import 'seq.dart';
import 'time.dart';

/// A bar holding one [MeasureRest] per staff in [clefs], in system order.
/// [restId] mints the rests' ids after [id] has been minted, so ids follow
/// document order.
MeasureColumn emptyBar({
  required MeasureId id,
  required Meter meter,
  required KeySignature key,
  required List<(StaffId, Clef)> clefs,
  required EventId Function() restId,
  Seq<TempoMark> tempos = const Seq.empty(),
}) => MeasureColumn(
  id: id,
  meter: meter,
  key: key,
  tempos: tempos,
  staves: Seq([
    for (final (staff, clef) in clefs)
      StaffMeasure(
        staff: staff,
        clef: clef,
        voices: Seq([
          Voice(
            slot: VoiceSlot.one,
            items: Seq([MeasureRest(id: restId(), span: meter.length)]),
          ),
        ]),
      ),
  ]),
);
