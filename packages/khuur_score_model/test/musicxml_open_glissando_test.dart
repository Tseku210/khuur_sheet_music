import 'dart:io';

import 'package:khuur_score_model/khuur_score_model.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support.dart';

/// What the file's previous exporter wrote for [fourShapes], with the note to
/// rest line and the next glissando under one number.
final capturedBefore = File('test/golden/glissando_to_rest_captured.musicxml');

/// The glissandi MuseScore 4.7.7 builds from [xml], each as its first and
/// last note with their times in quarters.
///
/// Transcribed from `addGlissandoSlide` in `importmusicxmlpass2.cpp`. A mark
/// on a rest is not read. Slots are per part, element and number. A start on
/// a held slot is dropped, and any stop on a note closes the slot's line. A
/// pair on one tick is a fall and a line of four whole notes or more is
/// dropped. A start still open at the end of its part builds no line.
List<String> museScoreGlissandi(String xml) {
  final lines = <String>[];
  for (final part in XmlDocument.parse(xml).findAllElements('part')) {
    final open = <(String, int), ({String note, int time})>{};
    var divisions = 1;
    var barStart = 0;
    for (final bar in part.findElements('measure')) {
      var time = barStart;
      var furthest = barStart;
      var onset = barStart;
      for (final child in bar.childElements) {
        final duration =
            int.tryParse(child.getElement('duration')?.innerText ?? '') ?? 0;
        switch (child.name.local) {
          case 'attributes':
            final value = child.getElement('divisions')?.innerText;
            divisions = value == null ? divisions : int.parse(value);
          case 'backup':
            time -= duration;
          case 'forward':
            time += duration;
          case 'note':
            final inChord = child.getElement('chord') != null;
            if (!inChord) {
              onset = time;
              time += duration;
            }
            final pitch = child.getElement('pitch');
            if (pitch == null) {
              break;
            }
            final name =
                '${pitch.getElement('step')!.innerText}'
                '${pitch.getElement('octave')!.innerText}';
            for (final mark
                in child
                    .findAllElements('*')
                    .where(
                      (e) =>
                          e.name.local == 'glissando' ||
                          e.name.local == 'slide',
                    )) {
              final number = int.parse(mark.getAttribute('number') ?? '1');
              expect(number, inInclusiveRange(1, 16));
              final slot = (mark.name.local, number);
              final held = open[slot];
              if (mark.getAttribute('type') == 'start') {
                open[slot] ??= (note: name, time: onset);
              } else if (held != null) {
                open.remove(slot);
                if (held.time != onset &&
                    onset + duration - held.time < 16 * divisions) {
                  lines.add(
                    '${held.note}@${held.time / divisions} '
                    '$name@${onset / divisions}',
                  );
                }
              }
            }
        }
        if (time > furthest) {
          furthest = time;
        }
      }
      barStart = furthest;
    }
  }
  return lines;
}

/// A line from a note to a rest, a line between notes, a line from a rest to
/// a note and a line between rests, in two bars.
Score fourShapes() {
  var score = sessionWith([
    [
      chordOf(1, 'C5'),
      rest(2, NoteValue.quarter),
      chordOf(3, 'E5'),
      chordOf(4, 'G5'),
    ],
    [
      rest(5, NoteValue.quarter),
      chordOf(6, 'D5'),
      rest(7, NoteValue.quarter),
      rest(8, NoteValue.quarter),
    ],
  ]).score;
  ScorePoint beat(int bar, int quarter) => pointAt(score, bar, at(quarter, 4));
  for (final (first, last) in [
    (beat(0, 0), beat(0, 1)),
    (beat(0, 2), beat(0, 3)),
    (beat(1, 0), beat(1, 1)),
    (beat(1, 2), beat(1, 3)),
  ]) {
    score = withSpanner(score, const Glissando(), first, last);
  }
  return score;
}

/// A piano bar whose line starts on C4 of the top staff and stops on G3 of
/// the bottom staff, with the top staff's voice resting there.
const crossStaff = '''
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
<part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
<part id="P1"><measure number="1">
<attributes><divisions>1</divisions><key><fifths>0</fifths></key><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves><clef number="1"><sign>G</sign><line>2</line></clef><clef number="2"><sign>F</sign><line>4</line></clef></attributes>
<note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><staff>1</staff><notations><glissando type="start" number="1"/></notations></note>
<note><rest/><duration>1</duration><voice>1</voice><type>quarter</type><staff>1</staff></note>
<note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><staff>1</staff><notations><glissando type="start" number="2"/></notations></note>
<note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice><type>quarter</type><staff>1</staff><notations><glissando type="stop" number="2"/></notations></note>
<backup><duration>4</duration></backup>
<note><rest/><duration>1</duration><voice>5</voice><type>quarter</type><staff>2</staff></note>
<note><pitch><step>G</step><octave>3</octave></pitch><duration>1</duration><voice>5</voice><type>quarter</type><staff>2</staff><notations><glissando type="stop" number="1"/></notations></note>
<note><rest/><duration>2</duration><voice>5</voice><type>half</type><staff>2</staff></note>
</measure></part>
</score-partwise>
''';

List<String> linesOf(Score score) {
  String label(Spanner line) {
    final (:from, :to) = score.glissandoNotes(line);
    final bar = score.indexOf(line.first.measure);
    return '$bar+${line.first.offset.wholeNotes} ${from?.tone}>${to?.tone}';
  }

  return [
    for (final line in score.spanners)
      if (line.kind is Glissando) label(line),
  ];
}

Score roundTrip(Score score) => scoreFromMusicXml(scoreToMusicXml(score));

void main() {
  group('A glissando from a note to a rest', () {
    test('comes back from its own export', () {
      final score = fourShapes();

      expect(linesOf(roundTrip(score)), linesOf(score));
      expect(
        scoreToMusicXml(roundTrip(score)),
        scoreToMusicXml(score),
      );
    });

    test('comes back when its stop was on another staff', () {
      final score = scoreFromMusicXml(crossStaff);

      expect(linesOf(score), contains('0+0 C4>null'));
      expect(linesOf(roundTrip(score)), linesOf(score));
    });

    test('takes no line from the next glissando under MuseScore 4 rules', () {
      expect(
        museScoreGlissandi(capturedBefore.readAsStringSync()),
        ['C5@0.0 G5@3.0'],
        reason: 'one number for both lines closes the first on the second',
      );
      expect(museScoreGlissandi(scoreToMusicXml(fourShapes())), [
        'E5@2.0 G5@3.0',
      ]);
    });

    test('leaves a line that follows its cross-staff start to MuseScore', () {
      final exported = scoreToMusicXml(scoreFromMusicXml(crossStaff));

      expect(museScoreGlissandi(exported), ['E4@2.0 G4@3.0']);
    });

    test('shares a number with the same shape in a later bar', () {
      const bars = 20;
      var score = sessionWith([
        for (var bar = 0; bar < bars; bar++)
          [
            chordOf(bar * 10 + 1, 'C5'),
            rest(bar * 10 + 2, NoteValue.quarter),
            chordOf(bar * 10 + 3, 'E5'),
            chordOf(bar * 10 + 4, 'G5'),
          ],
      ]).score;
      for (var bar = 0; bar < bars; bar++) {
        score = withSpanner(
          score,
          const Glissando(),
          pointAt(score, bar, Moment.zero),
          pointAt(score, bar, at(1, 4)),
        );
        score = withSpanner(
          score,
          const Glissando(),
          pointAt(score, bar, at(2, 4)),
          pointAt(score, bar, at(3, 4)),
        );
      }

      expect(linesOf(roundTrip(score)), linesOf(score));
      expect(museScoreGlissandi(scoreToMusicXml(score)), hasLength(bars));
    });

    test('is left out when the part has no number free for it', () {
      final tones = [
        for (final octave in [2, 3, 4])
          for (final step in 'CDEFGAB'.split('')) '$step$octave',
      ].take(17).join(' ');
      var score = sessionWith([
        [
          chordOf(100, tones),
          chordOf(200, tones),
          rest(3, NoteValue.quarter),
          rest(4, NoteValue.quarter),
        ],
      ]).score;
      for (var i = 0; i < 16; i++) {
        score = withSpanner(
          score,
          Glissando(from: NoteId(1000 + i), to: NoteId(2000 + i)),
          pointAt(score, 0, Moment.zero),
          pointAt(score, 0, at(1, 4)),
        );
      }
      score = withSpanner(
        score,
        const Glissando(from: NoteId(1016)),
        pointAt(score, 0, Moment.zero),
        pointAt(score, 0, at(2, 4)),
      );

      final lines = linesOf(roundTrip(score));

      expect(lines, hasLength(16));
      expect(lines, isNot(contains(endsWith('>null'))));
      expect(museScoreGlissandi(scoreToMusicXml(score)), hasLength(16));
    });
  });
}
