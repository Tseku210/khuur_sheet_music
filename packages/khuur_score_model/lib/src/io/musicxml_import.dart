/// MusicXML import.
library;

import 'package:xml/xml.dart';

import '../edit/edits.dart';
import '../edit/session.dart';
import '../score.dart';
import 'json.dart';
import 'musicxml_assemble.dart';
import 'musicxml_overrides.dart';
import 'musicxml_read.dart';
import 'musicxml_records.dart';

/// Reads a `score-partwise` MusicXML document into a [Score].
///
/// It reads what `scoreToMusicXml` writes, so exporting the result gives
/// the same document, and the common notation of files from other
/// programs. What the model has no place for is left out.
///
/// Throws [ScoreFormatException] when [xml] is not well-formed, is not a
/// `score-partwise` document, or holds music the model cannot represent.
/// Its `path` names the element, as `/score-partwise/part/measure[2]/note`.
Score scoreFromMusicXml(String xml) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(
      xml.startsWith('﻿') ? xml.substring(1) : xml,
    );
  } on XmlException catch (e) {
    throw ScoreFormatException('/', 'not well-formed XML: ${e.message}');
  }
  final root = document.childElements.firstOrNull;
  final name = root?.name.local;
  if (root == null || name != 'score-partwise') {
    throw ScoreFormatException(
      root == null ? '/' : '/$name',
      name == 'score-timewise'
          ? 'only score-partwise documents are read, not score-timewise'
          : 'expected a score-partwise document',
    );
  }
  final read = readDocument(root);
  final score = _withMeasureRepeats(withOverrides(assemble(read), read), read);
  // The JSON loader checks every rule of a stored score, so a file that
  // slips past the reader's own checks is refused here, not handed on as
  // a score that later edits or saves would choke on.
  try {
    scoreFromJson(scoreToJson(score));
  } on ScoreFormatException catch (e) {
    throw ScoreFormatException(
      '/',
      'import built an invalid score: ${e.path}: ${e.message}',
    );
  }
  return score;
}

/// [score] with the measure-repeat signs [document] states, each set as
/// `SetMeasureRepeat` sets it, so a covered bar's notes give way to its
/// whole-bar rest. A `<measure-repeat>` start opens a run of signs on its
/// staff, or on every staff of its part without a number, and a stop, or
/// the part's end, closes it. A run of two-bar repeats takes its bars in
/// pairs from its start. A sign of another count, or one the model refuses
/// because it does not stand, is dropped and its bar keeps its notes.
Score _withMeasureRepeats(Score score, DocumentRecord document) {
  var session = EditSession.start(score);
  for (final (p, part) in document.parts.indexed) {
    final staves = score.parts[p].staves;
    for (final (k, staff) in staves.indexed) {
      int? open;
      var from = 0;
      final runs = <({int from, int bars})?>[];
      for (final (bar, record) in part.bars.indexed) {
        for (final mark in record.measureRepeats) {
          if (mark.staff == null || mark.staff == k) {
            open = mark.bars;
            from = bar;
          }
        }
        runs.add(open == null ? null : (from: from, bars: open));
      }
      for (final (bar, run) in runs.indexed) {
        final set = switch (run) {
          (from: _, bars: 1) => true,
          (:final from, bars: 2) =>
            (bar - from).isEven &&
                bar + 1 < runs.length &&
                runs[bar + 1] == run,
          _ => false,
        };
        if (set) {
          final edit = SetMeasureRepeat(
            score.measures[bar].id,
            bars: run!.bars,
            staff: staff.id,
          );
          if (session.run(edit) case Applied(session: final next)) {
            session = next;
          }
        }
      }
    }
  }
  return session.score;
}
