part of 'musicxml_read.dart';

extension on _BarReader {
  void _direction(XmlElement direction) {
    final staff = _staff(direction);
    final at = cursor;
    final types = [
      for (final type in direction.findElements('direction-type'))
        ...type.childElements,
    ];
    final written = [
      for (final type in types)
        if (type.name.local == 'words') type.innerText,
    ];
    var words = written.isEmpty ? null : written.join();
    if (_marks(
      direction.getElement('sound'),
      at: at,
      types: types,
      words: words,
    )) {
      words = null;
    }
    final anchor = TimeAnchor(bar, staff, at);
    for (final type in types) {
      final name = type.name.local;
      final number = type.getAttribute('number') ?? '1';
      final kind = type.getAttribute('type');
      switch (name) {
        case 'dashes' when kind == 'start':
          final text = words;
          words = null;
          part.start(
            name,
            number,
            text == null ? null : TempoLine(text: text, factor: _factor(text)),
            anchor,
          );
        case 'wedge' when kind == 'crescendo' || kind == 'diminuendo':
          final hairpin = Hairpin(crescendo: kind == 'crescendo');
          part.start(name, number, hairpin, anchor);
        case 'octave-shift' when kind == 'up' || kind == 'down':
          part.start(
            name,
            number,
            _octaveLine(type, down: kind == 'down'),
            anchor,
          );
        case 'pedal' when kind == 'start':
          part.start(name, number, const PedalLine(), anchor);
        case 'pedal' when kind == 'change':
          part
            ..stop(name, number, anchor)
            ..start(name, number, const PedalLine(), anchor);
        case 'dashes' || 'wedge' || 'octave-shift' || 'pedal'
            when kind == 'stop':
          part.stop(name, number, anchor);
        case 'rehearsal':
          rehearsals.add((at: at, text: type.innerText));
        case 'dynamics':
          final levels = Dynamic.values.asNameMap();
          final level = type.childElements
              .map((child) => levels[child.name.local])
              .nonNulls
              .firstOrNull;
          if (level != null) {
            directions.add((staff: staff, direction: DynamicMark(at, level)));
          }
      }
    }
    if (words != null) {
      directions.add((
        staff: staff,
        direction: TextMark(
          at,
          words,
          above: direction.getAttribute('placement') != 'below',
        ),
      ));
    }
  }

  OctaveLine _octaveLine(XmlElement shift, {required bool down}) {
    final size = shift.getAttributeNode('size');
    final written = size == null ? 8 : integerOf(size.value);
    return OctaveLine(
      OctaveShift.values
              .where(
                (shift) =>
                    octaveShiftSize(shift) == written &&
                    shift.octaves > 0 == down,
              )
              .firstOrNull ??
          Source(size!).refuse('size is 8, 15 or 22'),
    );
  }

  /// Reads the navigation and tempo marks of a `<sound>` and, inside a
  /// direction, of its [types]. Returns whether one of them took the
  /// direction's [words].
  bool _marks(
    XmlElement? sound, {
    required Moment at,
    List<XmlElement> types = const [],
    String? words,
  }) {
    final mark = _navigation(sound, types, words);
    if (mark != null) {
      navigation.add(mark);
    }
    final tempo = _tempo(types, sound);
    if (tempo != null) {
      tempos.add(
        TempoMark(
          offset: at,
          tempo: tempo.tempo,
          text: mark == null ? words : null,
          showMetronome: tempo.shown,
        ),
      );
    }
    return mark != null || tempo != null;
  }

  void _harmony(XmlElement harmony) {
    final root = _pitchName(harmony.getElement('root'), 'root');
    final kind = harmony.getElement('kind');
    final name = kind?.innerText.trim();
    if (root == null || name == 'none') {
      return;
    }
    directions.add((
      staff: _staff(harmony),
      direction: ChordSymbol(
        cursor,
        root: root,
        quality: kind?.getAttribute('text') ?? qualityByKind[name] ?? '',
        bass: _pitchName(harmony.getElement('bass'), 'bass'),
      ),
    ));
  }

  void _barline(XmlElement barline) {
    for (final child in barline.childElements) {
      switch (child.name.local) {
        case 'bar-style'
            when (barline.getAttribute('location') ?? 'right') == 'right':
          style = child.innerText.trim();
        case 'repeat' when child.getAttribute('direction') == 'forward':
          repeatStart = true;
        case 'repeat' when child.getAttribute('direction') == 'backward':
          var times = 2;
          if (child.getAttributeNode('times') case final stated?) {
            times =
                integerOf(stated.value) ??
                Source(stated).refuse('expected an integer');
            if (repeatProblem(times) case final problem?) {
              Source(stated).refuse(problem);
            }
          }
          repeatEnd = RepeatEnd(times: times);
        case 'ending' when child.getAttribute('type') == 'start':
          final number =
              child.getAttributeNode('number') ??
              Source(child).missing('@number');
          final endings = {
            for (final ending in number.value.trim().split(RegExp(r'[,\s]+')))
              integerOf(ending) ?? 0,
          };
          if (endings.any((ending) => ending < 1)) {
            Source(number).refuse('ending numbers are integers from 1');
          }
          endingStart = endings.toList()..sort();
        case 'ending':
          endingStop = switch (child.getAttribute('type')) {
            'stop' => 'stop',
            'discontinue' => 'discontinue',
            _ => endingStop,
          };
      }
    }
  }
}

double _factor(String words) {
  final lower = words.toLowerCase();
  if (const ['rit', 'rall', 'allarg'].any(lower.contains)) {
    return 0.75;
  }
  return const ['accel', 'string', 'stretto'].any(lower.contains) ? 4 / 3 : 1;
}

/// The navigation mark a direction's `<sound>` states, else the one its
/// segno or coda symbol among [types] draws.
NavigationMark? _navigation(
  XmlElement? sound,
  List<XmlElement> types,
  String? words,
) {
  if (sound?.getAttribute('dacapo') == 'yes') {
    return _jump(JumpTarget.start, types, words);
  }
  if (sound?.getAttribute('dalsegno') != null) {
    return _jump(JumpTarget.segno, types, words);
  }
  if (sound?.getAttribute('tocoda') != null) {
    return const ToCoda();
  }
  if (sound?.getAttribute('fine') != null) {
    return const Fine();
  }
  if (sound?.getAttribute('segno') != null) {
    return const Segno();
  }
  if (sound?.getAttribute('coda') != null) {
    return const Coda();
  }
  for (final type in types) {
    switch (type.name.local) {
      case 'segno':
        return const Segno();
      case 'coda':
        return const Coda();
    }
  }
  return null;
}

/// The jump to [target] that prints [words]. It ends where its standard
/// words in an `<other-direction>` among [types] say, else where [words]
/// say.
Jump _jump(JumpTarget target, List<XmlElement> types, String? words) {
  final beside = {
    for (final type in types)
      if (type.name.local == 'other-direction') type.innerText.trim(),
  };
  final plain =
      JumpThen.values
          .map((then) => Jump(target, then: then))
          .where((jump) => beside.contains(jump.label))
          .firstOrNull ??
      Jump(target, then: jumpEndingIn(words ?? ''));
  return words == plain.label
      ? plain
      : Jump(target, then: plain.then, text: words);
}

/// The tempo of the first metronome among [types] that states one, else of
/// [sound], and whether the metronome prints.
({Tempo tempo, bool shown})? _tempo(List<XmlElement> types, XmlElement? sound) {
  for (final metronome in types) {
    if (metronome.name.local != 'metronome') {
      continue;
    }
    final base =
        baseByTypeName[metronome.getElement('beat-unit')?.innerText.trim()];
    final dots = metronome.findElements('beat-unit-dot').length;
    final bpm = _bpm(metronome.getElement('per-minute')?.innerText);
    if (base == null || dots > 3 || bpm == null) {
      continue;
    }
    final tempo = Tempo(bpm, beat: NoteValue(base, dots: dots));
    if (tempoMarkProblem(tempo) == null) {
      return (
        tempo: tempo,
        shown: metronome.getAttribute('print-object') != 'no',
      );
    }
  }
  final bpm = _bpm(sound?.getAttribute('tempo'));
  return bpm == null ? null : (tempo: Tempo(bpm), shown: false);
}

double? _bpm(String? text) {
  final exact = decimalOf(text);
  return exact != null && exact.isPositive ? exact.toDouble() : null;
}
