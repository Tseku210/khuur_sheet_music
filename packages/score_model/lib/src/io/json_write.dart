part of 'json.dart';

Map<String, Object?> _part(Part part) => {
  'id': part.id.value,
  'name': part.name,
  if (part.shortName.isNotEmpty) 'shortName': part.shortName,
  if (part.hidden) 'hidden': true,
  'instrument': _instrument(part.instrument),
  'staves': [
    for (final staff in part.staves)
      {'id': staff.id.value, if (staff.lines != 5) 'lines': staff.lines},
  ],
};

Map<String, Object?> _instrument(Instrument instrument) => {
  'key': instrument.key,
  'program': instrument.program,
  if (instrument.bank != 0) 'bank': instrument.bank,
  if (instrument.transposition case final interval
      when interval != Interval.unison)
    'transposition': [interval.steps, interval.semitones],
  if (instrument.clef != Clef.treble) 'clef': instrument.clef.name,
  if (instrument.strings.isNotEmpty)
    'strings': [for (final pitch in instrument.strings) _pitch(pitch)],
  if (instrument.drums.isNotEmpty)
    'drums': [
      for (final sound in instrument.drums)
        {
          'name': sound.name,
          'position': _pitch(sound.position),
          'midiKey': sound.midiKey,
          if (sound.head != NoteHead.normal) 'head': sound.head.name,
        },
    ],
  if (instrument.lowest case final lowest?) 'lowest': _pitch(lowest),
  if (instrument.highest case final highest?) 'highest': _pitch(highest),
};

/// [column], with its meter, key and clefs left out where they are the
/// same as at the end of [previous].
Map<String, Object?> _column(MeasureColumn column, MeasureColumn? previous) => {
  'id': column.id.value,
  if (column.meter != previous?.meter) ...{
    'meter': '${column.meter.groups.join('+')}/${column.meter.unit}',
    if (column.meter.symbol != MeterSymbol.numeric)
      'meterSymbol': column.meter.symbol.name,
  },
  if (column.key != previous?.key) ...{
    'key': column.key.fifths,
    if (column.key.mode != KeyMode.none) 'mode': column.key.mode.name,
  },
  if (column.irregularLength case final length?)
    'length': _fraction(length.wholeNotes),
  if (column.barline != Barline.regular) 'barline': column.barline.name,
  if (column.repeatStart) 'repeatStart': true,
  if (column.repeatEnd case final end?) 'repeatEnd': end.times,
  if (column.volta case final volta?)
    'volta': {'endings': volta.endings, if (volta.open) 'open': true},
  if (column.navigation.isNotEmpty)
    'navigation': [for (final mark in column.navigation) _navigation(mark)],
  'rehearsal': ?column.rehearsal,
  if (column.tempos.isNotEmpty)
    'tempos': [
      for (final mark in column.tempos)
        {
          'at': _fraction(mark.offset.wholeNotes),
          'bpm': mark.tempo.bpm,
          if (mark.tempo.beat != NoteValue.quarter)
            'beat': _value(mark.tempo.beat),
          'text': ?mark.text,
          if (!mark.showMetronome) 'metronome': false,
        },
    ],
  if (column.breakBefore case final layoutBreak?) 'break': layoutBreak.name,
  if (column.keyDisplay != SignatureDisplay.auto)
    'keyDisplay': column.keyDisplay.name,
  if (column.meterDisplay != SignatureDisplay.auto)
    'meterDisplay': column.meterDisplay.name,
  'staves': [
    for (final (k, staff) in column.staves.indexed)
      _staffMeasure(staff, previous?.staves[k].clefAtEnd),
  ],
};

Object _navigation(NavigationMark mark) => switch (mark) {
  Segno() => 'segno',
  Coda() => 'coda',
  ToCoda() => 'toCoda',
  Fine() => 'fine',
  Jump(:final target, :final then, :final text) => {
    'jump': target.name,
    if (then != JumpThen.toEnd) 'then': then.name,
    'text': ?text,
  },
};

Map<String, Object?> _staffMeasure(StaffMeasure staff, Clef? before) => {
  if (staff.clef != before) 'clef': staff.clef.name,
  if (staff.clefChanges.isNotEmpty)
    'clefChanges': [
      for (final change in staff.clefChanges)
        {
          'at': _fraction(change.offset.wholeNotes),
          'clef': change.clef.name,
        },
    ],
  if (staff.directions.isNotEmpty)
    'directions': [
      for (final direction in staff.directions)
        {
          'at': _fraction(direction.offset.wholeNotes),
          ...switch (direction) {
            DynamicMark(:final level) => {'dynamic': level.name},
            TextMark(:final text, :final above) => {
              'text': text,
              if (!above) 'above': false,
            },
            ChordSymbol(:final root, :final quality, :final bass) => {
              'chord': _pitchName(root),
              if (quality.isNotEmpty) 'quality': quality,
              if (bass != null) 'bass': _pitchName(bass),
            },
          },
        },
    ],
  'voices': [
    for (final voice in staff.voices)
      {
        'voice': voice.slot.index + 1,
        'items': [for (final item in voice.items) _item(item)],
      },
  ],
};

Map<String, Object?> _item(VoiceItem item) => switch (item) {
  Gap(:final span) => {'gap': _fraction(span.wholeNotes)},
  ChordEvent() => _chord(item),
  RestEvent(:final id, :final value, :final hidden, :final articulations) => {
    'rest': id.value,
    'value': _value(value),
    if (hidden) 'hidden': true,
    ..._articulations(articulations),
  },
  MeasureRest(:final id, :final articulations) => {
    'measureRest': id.value,
    ..._articulations(articulations),
  },
  Tuplet(
    :final id,
    :final ratio,
    :final unit,
    :final bracket,
    :final members,
  ) =>
    {
      'tuplet': id.value,
      'ratio': [ratio.actual, ratio.normal],
      'unit': _value(unit),
      if (bracket != TupletBracket.auto) 'bracket': bracket.name,
      'members': [for (final member in members) _item(member)],
    },
};

Map<String, Object?> _chord(ChordEvent chord) => {
  'chord': chord.id.value,
  'value': _value(chord.value),
  'notes': [for (final note in chord.notes) _note(note)],
  ..._articulations(chord.articulations),
  if (chord.ornament case final ornament?) 'ornament': ornament.name,
  if (chord.bowing case final bowing?) 'bowing': bowing.name,
  if (chord.graces.isNotEmpty)
    'graces': [
      for (final grace in chord.graces)
        {
          'id': grace.id.value,
          'kind': grace.kind.name,
          'value': _value(grace.value),
          'notes': [for (final note in grace.notes) _note(note)],
        },
    ],
  if (chord.stem != StemDirection.auto) 'stem': chord.stem.name,
  if (chord.beam != BeamMode.auto) 'beam': chord.beam.name,
  if (chord.tremolo != 0) 'tremolo': chord.tremolo,
  if (chord.lyrics.isNotEmpty)
    'lyrics': [
      for (final lyric in chord.lyrics)
        {
          'verse': lyric.verse,
          'text': lyric.text,
          if (lyric.syllabic != Syllabic.single)
            'syllabic': lyric.syllabic.name,
          if (lyric.extend) 'extend': true,
        },
    ],
};

/// [marks] in [Articulation] order, so a set saves the same every time.
Map<String, Object?> _articulations(Set<Articulation> marks) => {
  if (marks.isNotEmpty)
    'articulations': [
      for (final mark in Articulation.values)
        if (marks.contains(mark)) mark.name,
    ],
};

Map<String, Object?> _note(Note note) => switch (note) {
  PitchedNote() => {
    'id': note.id.value,
    'pitch': _pitch(note.pitch),
    if (note.tie) 'tie': true,
    if (note.accidental != AccidentalRequest.auto)
      'accidental': note.accidental.name,
    if (note.head != NoteHead.normal) 'head': note.head.name,
    'fingering': ?note.fingering,
    'string': ?note.string,
  },
  DrumNote() => {
    'id': note.id.value,
    'drum': note.drum.name,
    if (note.tie) 'tie': true,
  },
};

Map<String, Object?> _spanner(Spanner spanner) => {
  'id': spanner.id.value,
  ...switch (spanner.kind) {
    Slur(:final dashed) => {'kind': 'slur', if (dashed) 'dashed': true},
    Hairpin(:final crescendo) => {
      'kind': crescendo ? 'crescendo' : 'diminuendo',
    },
    OctaveLine(:final shift) => {'kind': 'octave', 'shift': shift.name},
    TrillLine() => {'kind': 'trill'},
    TempoLine(:final text, :final factor) => {
      'kind': 'tempo',
      'text': text,
      'factor': factor,
    },
    PedalLine() => {'kind': 'pedal'},
    Glissando() => {'kind': 'glissando'},
  },
  'staff': spanner.staff.value,
  if (spanner.voice case final voice?) 'voice': voice.index + 1,
  for (final (key, point) in [('from', spanner.first), ('to', spanner.last)])
    key: {
      'measure': point.measure.value,
      'at': _fraction(point.offset.wholeNotes),
    },
};
