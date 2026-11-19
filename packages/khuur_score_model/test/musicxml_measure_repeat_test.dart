import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'musicxml_import_test.dart'
    show backup, flute, grand, imported, keyboard, note, opening;
import 'support.dart';

/// Each staff's sign, bar by bar.
List<List<MeasureRepeat?>> signsOf(Score score) => [
  for (final column in score.measures)
    [for (final staff in column.staves) staff.measureRepeat],
];

/// The `<measure-repeat>` elements of each bar of the first part, as
/// `type` and count, with `@n` for a staff number.
List<List<String>> stylesOf(String xml) => [
  for (final measure in XmlDocument.parse(
    xml,
  ).findAllElements('part').first.findElements('measure'))
    [
      for (final style in measure.findAllElements('measure-style'))
        [
          style.getElement('measure-repeat')!.getAttribute('type'),
          style.getElement('measure-repeat')!.innerText,
          if (style.getAttribute('number') case final n?) '@$n',
        ].where((s) => s != null && s.isNotEmpty).join(' '),
    ],
];

String whole(String pitch, [String more = '']) =>
    note(pitch, 16, 'whole', more);

String start(int bars, [String number = '']) =>
    '<attributes><measure-style$number>'
    '<measure-repeat type="start">$bars</measure-repeat>'
    '</measure-style></attributes>';

String stop([String number = '']) =>
    '<attributes><measure-style$number>'
    '<measure-repeat type="stop"/></measure-style></attributes>';

/// The `<note>`s of bar [bar] of part [part], both from 0, each as its XML.
List<String> notesAt(String xml, int bar, {int part = 0}) => [
  for (final note
      in XmlDocument.parse(xml)
          .findAllElements('part')
          .elementAt(part)
          .findElements('measure')
          .elementAt(bar)
          .findElements('note'))
    note.toXmlString(),
];

/// The children of bar [bar] of the first part, from 0, as element names
/// and the `type` of each `<tie>`, `<slur>` and `<wedge>` in them.
List<String> contentsAt(String xml, int bar) => [
  for (final child in XmlDocument.parse(
    xml,
  ).findAllElements('measure').elementAt(bar).childElements)
    [
      child.name.local,
      for (final mark in child.descendantElements)
        if (const {'tie', 'slur', 'wedge'}.contains(mark.name.local))
          '${mark.name.local}:${mark.getAttribute('type')}',
    ].join(' '),
];

/// [score] with the measure-repeat signs [signs] set, each a bar index
/// and the bars it repeats, on staff [staff] of the score or every staff.
Score withSigns(Score score, List<(int, int)> signs, {int? staff}) =>
    signs.fold(EditSession.start(score), (session, sign) {
      final (bar, bars) = sign;
      return applied(
        session.run(
          SetMeasureRepeat(
            idOf(session, bar),
            bars: bars,
            staff: staff == null ? null : score.staves[staff].id,
          ),
        ),
      );
    }).score;

/// [xml] read back, checking that its export is [xml] itself.
Score readBack(String xml) {
  final score = imported(xml);
  expect(scoreToMusicXml(score), xml);
  return score;
}

void main() {
  test('export opens a run at its first bar and stops it at the bar after, '
      'and import reads the signs back', () {
    final score =
        [
          for (final bar in [1, 2]) (bar, 1),
          (4, 2),
        ].fold(blank(bars: 7), (session, at) {
          final (bar, bars) = at;
          return applied(
            session.run(SetMeasureRepeat(idOf(session, bar), bars: bars)),
          );
        }).score;

    final xml = scoreToMusicXml(score);

    expect(stylesOf(xml), [
      <String>[],
      ['start 1'],
      <String>[],
      ['stop'],
      ['start 2'],
      <String>[],
      ['stop'],
    ]);
    expect(signsOf(imported(xml)), signsOf(score));
  });

  test('import puts a run of three bars from another app under one-bar '
      'repeats, dropping their notes', () {
    final score = imported(
      flute([
        [opening(), whole('C5')],
        [start(1), whole('D5')],
        [whole('E5')],
        [whole('F5')],
        [stop(), whole('G5')],
      ]),
    );

    expect(signsOf(score).map((s) => s.single), [
      null,
      MeasureRepeat.oneBar,
      MeasureRepeat.oneBar,
      MeasureRepeat.oneBar,
      null,
    ]);
    expect(bar(score, 2), ['measure-rest']);
  });

  test('a run with no stop lasts to the end, and a two-bar run takes its '
      'bars in pairs', () {
    final score = imported(
      flute([
        [opening(), whole('C5')],
        [whole('D5')],
        [start(2), whole('C5')],
        [whole('D5')],
        [whole('C5')],
        [whole('D5')],
      ]),
    );

    expect(signsOf(score).map((s) => s.single), [
      null,
      null,
      MeasureRepeat.twoBarsFirst,
      MeasureRepeat.twoBarsSecond,
      MeasureRepeat.twoBarsFirst,
      MeasureRepeat.twoBarsSecond,
    ]);
  });

  test('a numbered measure style puts the sign on its own staff', () {
    final score = imported(
      keyboard([
        [
          grand,
          whole('C5', '<voice>1</voice><staff>1</staff>'),
          backup(16),
          whole('C3', '<voice>5</voice><staff>2</staff>'),
        ],
        [
          start(1, ' number="2"'),
          whole('D5', '<voice>1</voice><staff>1</staff>'),
          backup(16),
          whole('D3', '<voice>5</voice><staff>2</staff>'),
        ],
      ]),
    );

    expect(signsOf(score)[1], [null, MeasureRepeat.oneBar]);
    expect(stylesOf(scoreToMusicXml(score))[1], ['start 1 @2']);
  });

  test('import drops a sign with nothing to repeat or of another count, and '
      'its bar keeps its notes', () {
    final score = imported(
      flute([
        [opening(), start(1), whole('C5')],
        [stop(), whole('D5')],
        [start(3), whole('E5')],
      ]),
    );

    expect(signsOf(score).expand((s) => s), everyElement(isNull));
    expect(bar(score, 0), isNot(['measure-rest']));
  });

  test('export writes, in each bar of a chain of one-bar repeats, the '
      'notes of the bar they repeat, with its beams and tuplet', () {
    final score = withSigns(
      fill(blankScore(bars: 5), 0, [
        chordOf(101, 'C5', value: NoteValue.eighth),
        chordOf(102, 'D5', value: NoteValue.eighth),
        tripletOfEighths(103, [
          chordOf(104, 'E5', value: NoteValue.eighth),
          chordOf(105, 'F#5', value: NoteValue.eighth),
          chordOf(106, 'G5', value: NoteValue.eighth),
        ]),
        chordOf(107, 'A5', value: NoteValue.half),
      ]),
      [(1, 1), (2, 1), (3, 1)],
    );

    final xml = scoreToMusicXml(score);

    for (final bar in [1, 2, 3]) {
      expect(notesAt(xml, bar), notesAt(xml, 0), reason: 'bar $bar');
    }
    expect(
      notesAt(xml, 0).join(),
      allOf(contains('<beam'), contains('<tuplet')),
    );
    expect(notesAt(xml, 4).single, contains('<rest measure="yes"/>'));
    final back = readBack(xml);
    expect(signsOf(back), signsOf(score));
    expect(
      [
        for (final i in [1, 2, 3]) bar(back, i),
      ],
      [
        for (final _ in [1, 2, 3]) ['measure-rest'],
      ],
    );
  });

  test('a copied bar keeps the tie inside it, and leaves the slur and the '
      'lyric to the bar it copies', () {
    final source = fill(blankScore(bars: 3), 0, [
      chordOf(101, 'C5', tie: true).copyWith(
        lyrics: Seq(const [Lyric(verse: 1, text: 'la')]),
      ),
      chordOf(102, 'C5'),
      chordOf(103, 'D5'),
      chordOf(104, 'E5'),
    ]);
    final score = withSigns(
      withSlur(
        source,
        pointAt(source, 0, at(1, 2)),
        pointAt(source, 0, at(3, 4)),
      ),
      [(1, 1)],
    );

    final xml = scoreToMusicXml(score);

    expect(contentsAt(xml, 1), [
      'attributes',
      'note tie:start',
      'note tie:stop',
      'note',
      'note',
    ]);
    expect(contentsAt(xml, 0).where((child) => child.startsWith('note')), [
      'note tie:start',
      'note tie:stop',
      'note slur:start',
      'note slur:stop',
    ]);
    expect(notesAt(xml, 1).join(), isNot(contains('<lyric')));
    expect(notesAt(xml, 0).join(), contains('<lyric'));
    final back = readBack(xml);
    expect(back.spanners, hasLength(1));
    expect(bar(back, 0), [
      'C5/quarter~',
      'C5/quarter',
      'D5/quarter',
      'E5/quarter',
    ]);
  });

  test('a slur and a hairpin that end under the sign end on its copy', () {
    final source = fill(blankScore(bars: 3), 0, [
      chordOf(101, 'C5'),
      chordOf(102, 'D5'),
      chordOf(103, 'E5'),
      chordOf(104, 'F5'),
    ]);
    final end = pointAt(source, 1, Moment.zero);
    final score = withSigns(
      withSpanner(
        withSlur(source, pointAt(source, 0, at(3, 4)), end),
        const Hairpin(crescendo: true),
        pointAt(source, 0, Moment.zero),
        end,
      ),
      [(1, 1)],
    );

    final xml = scoreToMusicXml(score);

    expect(contentsAt(xml, 1), [
      'attributes',
      'note slur:stop',
      'note',
      'note',
      'note',
      'direction wedge:stop',
    ]);
    readBack(xml);
  });

  test('a two-bar repeat on the lower staff of a second part copies both '
      'bars there, voice two and the tie between them included', () {
    var source = blankScore(parts: const [morinKhuur, piano], bars: 5);
    source = fill(source, 0, [
      chordOf(201, 'C3', value: NoteValue.whole, tie: true),
    ], staff: 2);
    source = fill(source, 1, [
      chordOf(202, 'C3', value: NoteValue.whole),
    ], staff: 2);
    source = fill(
      source,
      0,
      [Gap(len(1, 2)), chordOf(203, 'G2', value: NoteValue.half)],
      staff: 2,
      slot: VoiceSlot.two,
    );
    final score = withSigns(source, [(2, 2)], staff: 2);

    final xml = scoreToMusicXml(score);

    expect(notesAt(xml, 2, part: 1), notesAt(xml, 0, part: 1));
    expect(notesAt(xml, 3, part: 1), notesAt(xml, 1, part: 1));
    expect(notesAt(xml, 2, part: 1).join(), contains('<tie type="start"/>'));
    expect(notesAt(xml, 3, part: 1).join(), contains('<tie type="stop"/>'));
    expect(notesAt(xml, 2, part: 1), hasLength(3));
    expect(notesAt(xml, 2).single, contains('<rest measure="yes"/>'));
    expect(signsOf(readBack(xml)), signsOf(score));
  });
}
