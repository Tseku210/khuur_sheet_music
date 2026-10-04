import 'package:score_model/score_model.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<MeasureView> viewsOf(Score score) => [
  for (final column in score.measures) score.measureView(column.id),
];

/// The numbers of the bars that fail [holds], for a failure that names them.
List<int> barsWithout(
  List<MeasureView> views,
  bool Function(MeasureView view) holds,
) => [
  for (final view in views)
    if (!holds(view)) view.index + 1,
];

bool sounds(VoiceView voice) =>
    voice.events.any((timed) => timed.event is ChordEvent);

bool everyStaffSounds(MeasureView view) =>
    view.staves.length == 4 &&
    view.staves.every((staff) => staff.voices.any(sounds));

Set<int> versesOf(MeasureView view) => {
  for (final staff in view.staves)
    for (final voice in staff.voices)
      for (final timed in voice.events)
        if (timed.event case ChordEvent(:final lyrics))
          for (final lyric in lyrics) lyric.verse,
};

void main() {
  group('the dense score', () {
    late final Score score;
    late final List<MeasureView> views;

    setUpAll(() {
      score = denseScore();
      views = viewsOf(score);
    });

    test('is 500 bars of four staves, every one with notes', () {
      expect(views, hasLength(500));
      expect(score.staves, hasLength(4));
      expect(barsWithout(views, everyStaffSounds), isEmpty);
    });

    test('has a beamed group in every bar', () {
      expect(
        barsWithout(
          views,
          (view) => view.staves.any(
            (staff) => staff.voices.any((voice) => voice.beams.isNotEmpty),
          ),
        ),
        isEmpty,
      );
    });

    test('has two voices sounding on one staff in every bar', () {
      expect(
        barsWithout(
          views,
          (view) => view.staves.any(
            (staff) => staff.voices.where(sounds).length == 2,
          ),
        ),
        isEmpty,
      );
    });

    test('has one lyric verse in every bar', () {
      expect(
        barsWithout(views, (view) {
          final verses = versesOf(view);
          return verses.length == 1 && verses.contains(1);
        }),
        isEmpty,
      );
    });

    test('has a dynamic in every bar', () {
      expect(
        barsWithout(
          views,
          (view) => view.staves.any(
            (staff) => staff.source.directions.any((d) => d is DynamicMark),
          ),
        ),
        isEmpty,
      );
    });

    test('has a slur starting in every bar, 500 in all', () {
      expect(
        barsWithout(
          views,
          (view) => view.spanners.any(
            (segment) => segment.startsHere && segment.spanner.kind is Slur,
          ),
        ),
        isEmpty,
      );
      expect(score.spanners.where((s) => s.kind is Slur), hasLength(500));
    });

    test('is a score the model loads', () {
      expect(scoreFromJson(scoreToJson(score)).measures, hasLength(500));
    });

    test('takes the gate\'s note as one A4 at the start of voice one of the '
        'top staff of its bar', () {
      final next = scoreAfter(EditSession.start(score), noteInBar(score, 250));

      final top = next.measureView(next.measures[249].id).staves.first;
      expect(
        top.voices.first.events.first.event,
        isA<ChordEvent>().having(
          (chord) => chord.notes.single.tone,
          'tone',
          const Pitch(Step.a, 4),
        ),
      );
    });
  });

  group('the spanner score', () {
    late final Score score;
    late final List<MeasureView> views;

    setUpAll(() {
      score = spannerScore();
      views = viewsOf(score);
    });

    test('is 2,000 bars of four staves, every one with notes', () {
      expect(views, hasLength(2000));
      expect(score.staves, hasLength(4));
      expect(barsWithout(views, everyStaffSounds), isEmpty);
    });

    test('has exactly 2,500 spanners, each drawn in the bars it covers', () {
      expect(score.spanners, hasLength(2500));
      expect(
        views.expand((view) => view.spanners).where((s) => s.startsHere),
        hasLength(2500),
      );
      expect(
        views.expand((view) => view.spanners).where((s) => s.endsHere),
        hasLength(2500),
      );
    });

    test('is a score the model loads', () {
      expect(scoreFromJson(scoreToJson(score)).spanners, hasLength(2500));
    });
  });
}
