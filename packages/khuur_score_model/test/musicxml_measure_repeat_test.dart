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
}
