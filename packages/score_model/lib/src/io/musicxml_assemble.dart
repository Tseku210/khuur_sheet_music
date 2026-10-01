/// The Assemble stage of MusicXML import: builds a score from the records
/// the Read stage made. Internal to the package.
library;

import '../events.dart';
import '../measure.dart';
import '../pitch.dart';
import '../refs.dart';
import '../rules.dart';
import '../score.dart';
import '../seq.dart';
import '../time.dart';
import 'musicxml_names.dart';
import 'musicxml_records.dart';
import 'musicxml_spanners.dart';

/// The score [document] describes, with every accidental and beam left to
/// the model's own rules.
Score assemble(DocumentRecord document) {
  final assembly = _Assembly(document);
  final measures = [
    for (var bar = 0; bar < document.measures.length; bar++)
      assembly.column(bar),
  ];
  final everyHidden = document.parts.every((part) => part.hidden);
  final score = Score(
    meta: document.meta,
    parts: Seq([
      for (final (p, part) in document.parts.indexed)
        Part(
          id: part.id,
          name: part.name,
          shortName: part.shortName,
          hidden: part.hidden && !everyHidden,
          instrument: Instrument(
            key: '',
            program: part.program,
            bank: part.bank,
            transposition: part.transposition,
            clef: assembly.openingClefs[p],
            strings: part.strings,
            drums: part.drums,
          ),
          staves: Seq([
            for (final (k, id) in part.staves.indexed)
              Staff(id: id, lines: part.lines[k]),
          ]),
        ),
    ]),
    measures: Seq(measures),
  );
  return score.copyWith(spanners: Seq(spannersOf(score, document)));
}

/// The state that runs from bar to bar while the columns are built.
final class _Assembly {
  _Assembly(this.document)
    : clefs = [
        for (final part in document.parts)
          List.filled(part.staves.length, Clef.treble),
      ],
      movedDirections = [for (final _ in document.parts) []];

  final DocumentRecord document;

  List<PartRecord> get parts => document.parts;

  /// The part whose key signatures are the score's.
  late final PartRecord reference =
      parts
          .where(
            (part) =>
                !part.isPercussion && part.transposition == Interval.unison,
          )
          .firstOrNull ??
      parts.where((part) => !part.isPercussion).firstOrNull ??
      parts.first;

  late final List<Volta?> voltas = _voltas();

  KeySignature key = KeySignature.cMajor;
  Meter meter = Meter.fourFour;

  /// The clef each staff of each part has when the next bar opens.
  final List<List<Clef>> clefs;

  /// The first staff's clef in the first bar, per part.
  final openingClefs = <Clef>[];

  /// What the bar before held at its very end, which opens the next bar.
  final List<List<({int staff, StaffDirection direction})>> movedDirections;
  List<TempoMark> movedTempos = [];
  List<String> movedRehearsals = [];

  MeasureColumn column(int bar) {
    var keyDisplay = SignatureDisplay.auto;
    if (reference.bars[bar].key case final written?) {
      final stated = _concertKey(written);
      if (bar > 0 && stated.fifths == key.fifths) {
        keyDisplay = SignatureDisplay.restated;
      }
      key = stated;
    }
    var meterDisplay = SignatureDisplay.auto;
    ({Meter meter, Source source})? stated;
    for (final part in parts) {
      final own = part.bars[bar].meter;
      if (own == null) {
        continue;
      }
      if (stated == null) {
        stated = own;
      } else if (own.meter.unit != stated.meter.unit ||
          own.meter.groups.join('+') != stated.meter.groups.join('+')) {
        own.source.refuse('parts disagree on the meter');
      }
    }
    if (stated != null) {
      if (bar > 0 && stated.meter == meter) {
        meterDisplay = SignatureDisplay.restated;
      }
      meter = stated.meter;
    }

    var longest = parts.first.bars[bar];
    for (final part in parts) {
      if (part.bars[bar].end > longest.end) {
        longest = part.bars[bar];
      }
    }
    final length = longest.end.isZero
        ? meter.length
        : Moment.zero.until(longest.end);
    if (barLengthProblem(length) case final problem?) {
      longest.source.refuse(problem);
    }
    final end = Moment.zero + length;

    final tempos = <Moment, TempoMark>{};
    for (final tempo in movedTempos) {
      tempos.putIfAbsent(Moment.zero, () => tempo);
    }
    final rehearsals = movedRehearsals;
    movedTempos = [];
    movedRehearsals = [];
    final navigation = <NavigationMark>[];
    final staves = <StaffMeasure>[];
    for (final (p, part) in parts.indexed) {
      final record = part.bars[bar];
      for (final tempo in record.tempos) {
        if (tempo.offset < end) {
          tempos.putIfAbsent(tempo.offset, () => tempo);
        } else {
          movedTempos.add(
            TempoMark(
              offset: Moment.zero,
              tempo: tempo.tempo,
              text: tempo.text,
              showMetronome: tempo.showMetronome,
            ),
          );
        }
      }
      for (final rehearsal in record.rehearsals) {
        (rehearsal.at < end ? rehearsals : movedRehearsals).add(rehearsal.text);
      }
      for (final mark in record.navigation) {
        if (!navigation.contains(mark)) {
          navigation.add(mark);
        }
      }
      final moved = movedDirections[p];
      movedDirections[p] = [
        for (final (:staff, :direction) in record.directions)
          if (direction.offset >= end)
            (staff: staff, direction: _atBarStart(direction)),
      ];
      for (var k = 0; k < part.staves.length; k++) {
        staves.add(_staff(bar, p, k, end, moved));
      }
    }

    final first = parts.first.bars[bar];
    return MeasureColumn(
      id: document.measures[bar],
      meter: meter,
      key: key,
      staves: Seq(staves),
      irregularLength: length == meter.length ? null : length,
      barline: switch (first.barline.style) {
        final style? => barlineByStyle(
          style,
          repeats: first.barline.repeatEnd != null,
        ),
        null => Barline.regular,
      },
      repeatStart: first.barline.repeatStart,
      repeatEnd: first.barline.repeatEnd,
      volta: voltas[bar],
      navigation: Seq(navigation),
      rehearsal: rehearsals.firstOrNull,
      tempos: Seq(
        tempos.values.toList()..sort((a, b) => a.offset.compareTo(b.offset)),
      ),
      breakBefore: first.breakBefore,
      keyDisplay: keyDisplay,
      meterDisplay: meterDisplay,
    );
  }

  /// The concert key under the reference part's [written] key.
  KeySignature _concertKey(KeySignature written) {
    final transposition = reference.transposition;
    if (reference.isPercussion || transposition == Interval.unison) {
      return written;
    }
    // Transposing a key wraps past seven sharps or flats, so the way back
    // is not always the inverse interval.
    return [
              written.transpose(-transposition),
              for (var fifths = -7; fifths <= 7; fifths++)
                KeySignature(fifths, written.mode),
            ]
            .where((concert) => concert.transpose(transposition) == written)
            .firstOrNull ??
        written;
  }

  /// The brackets the first part's endings draw, bar by bar. Whether a
  /// bracket is open is known when it closes, and holds for all its bars.
  List<Volta?> _voltas() {
    final bars = parts.first.bars;
    final voltas = List<Volta?>.filled(bars.length, null);
    ({int from, List<int> endings})? open;
    for (final (bar, record) in bars.indexed) {
      final barline = record.barline;
      if (barline.endingStart case final endings?) {
        if (open != null) {
          _bracket(voltas, open.from, bar - 1, open.endings, open: true);
        }
        open = (from: bar, endings: endings);
      }
      if (barline.endingStop case final stop? when open != null) {
        _bracket(
          voltas,
          open.from,
          bar,
          open.endings,
          open: stop == 'discontinue',
        );
        open = null;
      }
    }
    if (open != null) {
      _bracket(voltas, open.from, bars.length - 1, open.endings, open: true);
    }
    return voltas;
  }

  void _bracket(
    List<Volta?> voltas,
    int from,
    int through,
    List<int> endings, {
    required bool open,
  }) {
    for (var bar = from; bar <= through; bar++) {
      voltas[bar] = Volta(endings, open: open);
    }
  }

  StaffMeasure _staff(
    int bar,
    int p,
    int k,
    Moment end,
    List<({int staff, StaffDirection direction})> moved,
  ) {
    final part = parts[p];
    final record = part.bars[bar];
    var clef = clefs[p][k];
    final changes = <Moment, Clef>{};
    Clef? closing;
    for (final stated in record.clefs) {
      if (stated.staff != k) {
        continue;
      }
      if (stated.at.isZero) {
        clef = stated.clef;
      } else if (stated.at < end) {
        changes[stated.at] = stated.clef;
      } else {
        closing = stated.clef;
      }
    }
    final clefChanges = [
      for (final MapEntry(key: offset, value: clef) in changes.entries)
        ClefChange(offset, clef),
    ]..sort((a, b) => a.offset.compareTo(b.offset));
    clefs[p][k] = closing ?? clefChanges.lastOrNull?.clef ?? clef;
    if (bar == 0 && k == 0) {
      openingClefs.add(clef);
    }

    final own = [
      for (final (:staff, :direction) in record.directions)
        if (staff == k && direction.offset < end) direction,
    ];
    final order = [for (var i = 0; i < own.length; i++) i]
      ..sort((a, b) {
        final byOffset = own[a].offset.compareTo(own[b].offset);
        return byOffset != 0 ? byOffset : a - b;
      });

    final lanes = [
      for (final lane in record.lanes)
        if (lane.staff == k) lane,
    ]..sort((a, b) => a.slot.index - b.slot.index);
    final voices = _Voices(this, part, bar, end);
    return StaffMeasure(
      staff: part.staves[k],
      clef: clef,
      clefChanges: Seq(clefChanges),
      directions: Seq([
        for (final (:staff, :direction) in moved)
          if (staff == k) direction,
        for (final i in order) own[i],
      ]),
      voices: Seq(voices.of(lanes, record.source)),
    );
  }
}

StaffDirection _atBarStart(StaffDirection direction) => switch (direction) {
  DynamicMark(:final level) => DynamicMark(Moment.zero, level),
  TextMark(:final text, :final above) => TextMark(
    Moment.zero,
    text,
    above: above,
  ),
  ChordSymbol(:final root, :final quality, :final bass) => ChordSymbol(
    Moment.zero,
    root: root,
    quality: quality,
    bass: bass,
  ),
};

/// Builds the voices of one part's staves in one bar.
final class _Voices {
  _Voices(this.assembly, this.part, this.bar, this.end);

  final _Assembly assembly;
  final PartRecord part;
  final int bar;

  /// The bar's end.
  final Moment end;

  Ids get ids => assembly.document.ids;

  /// The voices [lanes] make on their staff, voice one first. Voice one is
  /// rests where the file gives it nothing.
  List<Voice> of(List<LaneRecord> lanes, Source measure) {
    final voices = <Voice>[];
    for (final lane in lanes) {
      final items = _items(lane, measure);
      if (lane.slot == VoiceSlot.one || items.any((item) => item is! Gap)) {
        voices.add(Voice(slot: lane.slot, items: Seq(items)));
      }
    }
    if (voices.isEmpty) {
      return [
        Voice(
          slot: VoiceSlot.one,
          items: Seq([
            MeasureRest(id: EventId(ids.take()), span: Moment.zero.until(end)),
          ]),
        ),
      ];
    }
    return [
      if (voices.first.slot != VoiceSlot.one)
        Voice(
          slot: VoiceSlot.one,
          items: Seq(_fill(Moment.zero, end, one: true, at: measure)),
        ),
      ...voices,
    ];
  }

  List<VoiceItem> _items(LaneRecord lane, Source measure) {
    if (lane.items case [final RestRecord rest]
        when rest.onset.isZero &&
            (rest.measure ||
                (rest.end == end &&
                    !rest.hidden &&
                    (rest.value == null || !rest.typed)))) {
      return [
        MeasureRest(
          id: rest.id,
          span: Moment.zero.until(end),
          articulations: _restMarks(rest),
        ),
      ];
    }
    final one = lane.slot == VoiceSlot.one;
    final items = <VoiceItem>[];
    var filled = Moment.zero;
    for (final item in lane.items) {
      // A hidden rest of no writable length is the gap it stands for.
      if (item case RestRecord(value: null, hidden: true)) {
        continue;
      }
      items
        ..addAll(
          _fill(
            filled,
            item.onset,
            one: one,
            at: eventsIn([item]).first.note,
          ),
        )
        ..add(_content(item, lane));
      filled = item.end;
    }
    return items
      ..addAll(_fill(filled, end, one: one, at: lane.lastForward ?? measure));
  }

  /// What fills a voice from [from] to [to] where the file has nothing:
  /// hidden rests in voice [one], since it has no gaps, and a gap elsewhere.
  List<VoiceItem> _fill(
    Moment from,
    Moment to, {
    required bool one,
    required Source at,
  }) {
    if (to <= from) {
      return const [];
    }
    final gap = from.until(to);
    if (!one) {
      return [Gap(storable(gap.wholeNotes) ? gap : at.refuse(unstorable))];
    }
    if (startProblem(from) != null || startProblem(to) != null) {
      at.refuse('no rest value fits the gap');
    }
    return [
      for (final value in assembly.meter.spell(from, gap, rest: true))
        RestEvent(id: EventId(ids.take()), value: value, hidden: true),
    ];
  }

  Set<Articulation> _restMarks(RestRecord rest) =>
      rest.fermata ? const {Articulation.fermata} : const {};

  Content _content(LaneItem item, LaneRecord lane) => switch (item) {
    ChordRecord() => _chord(item, lane),
    RestRecord(value: null, :final typed, :final durationSource) =>
      durationSource.refuse(
        typed
            ? 'the duration does not match the written value'
            : 'no note value has this duration',
      ),
    RestRecord(:final value?) => RestEvent(
      id: item.id,
      value: value,
      articulations: _restMarks(item),
      hidden: item.hidden,
    ),
    TupletRecord() => Tuplet(
      id: item.id,
      ratio: item.ratio,
      unit: item.unit,
      members: Seq([for (final member in item.members) _content(member, lane)]),
      bracket: item.bracket,
    ),
  };

  ChordEvent _chord(ChordRecord chord, LaneRecord lane) => ChordEvent(
    id: chord.id,
    value: chord.value,
    notes: Seq(_notes(chord.notes, tiesTo: _tieTarget(chord, lane))),
    articulations: chord.articulations,
    ornament: chord.ornament,
    bowing: chord.bowing,
    graces: Seq([
      for (final grace in chord.graces)
        GraceChord(
          id: grace.id,
          kind: grace.kind,
          value: grace.value,
          notes: Seq(_notes(grace.notes, tiesTo: const [])),
        ),
    ]),
    stem: chord.stem,
    tremolo: chord.tremolo,
    lyrics: Seq(
      [...chord.lyrics]..sort((a, b) => a.verse - b.verse),
    ),
  );

  /// The notes of the event the model ties [chord] to: the next event of
  /// its voice when that starts where the chord ends, or the event that
  /// opens the voice in the next bar when the chord ends its bar.
  List<NoteRecord> _tieTarget(ChordRecord chord, LaneRecord lane) {
    final EventRecord? target;
    if (chord.end == end) {
      final bars = part.bars;
      target = bar + 1 < bars.length
          ? eventsIn(
              bars[bar + 1].lanes
                  .where(
                    (next) =>
                        next.staff == lane.staff && next.slot == lane.slot,
                  )
                  .expand((next) => next.items),
            ).where((event) => event.onset.isZero).firstOrNull
          : null;
    } else {
      target = eventsIn(
        lane.items,
      ).where((event) => event.onset == chord.end).firstOrNull;
    }
    return target is ChordRecord ? target.notes : const [];
  }

  /// [records] as notes in the order the model keeps a chord's, each tone
  /// once. A tie that starts is kept when one of [tiesTo] stops it.
  List<Note> _notes(
    List<NoteRecord> records, {
    required List<NoteRecord> tiesTo,
  }) {
    final notes = [
      for (final record in records)
        _note(
          record,
          tie:
              record.letRing ||
              (record.tieStart &&
                  tiesTo.any((to) => to.tieStop && _sameTone(to, record))),
        ),
    ];
    final order = [for (var i = 0; i < notes.length; i++) i]
      ..sort((a, b) {
        final byTone = notes[a].tone.compareTo(notes[b].tone);
        return byTone != 0 ? byTone : a - b;
      });
    final kept = <Note>[];
    for (final i in order) {
      if (kept.lastOrNull?.tone.compareTo(notes[i].tone) != 0) {
        kept.add(notes[i]);
      }
    }
    return kept;
  }

  Note _note(NoteRecord record, {required bool tie}) {
    switch (record) {
      case DrumRecord(:final id, :final drum):
        return DrumNote(id: id, drum: drum, tie: tie);
      case PitchedRecord(:final id, :final written, :final source):
        final pitch = written.transpose(
          part.transposition,
          key: assembly.key,
        );
        if (pitchProblem(pitch) case final problem?) {
          source.refuse(problem);
        }
        return PitchedNote(
          id: id,
          pitch: pitch,
          tie: tie,
          head: record.head,
          fingering: record.fingering,
          string: switch (record.string) {
            final number? => part.strings.length - number,
            null => null,
          },
        );
    }
  }
}

bool _sameTone(NoteRecord a, NoteRecord b) => switch ((a, b)) {
  (PitchedRecord(written: final a), PitchedRecord(written: final b)) => a == b,
  (DrumRecord(drum: final a), DrumRecord(drum: final b)) => a == b,
  _ => false,
};
