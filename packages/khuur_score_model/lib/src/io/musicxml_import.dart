/// MusicXML import.
library;

import 'package:xml/xml.dart';

import '../score.dart';
import 'json.dart';
import 'musicxml_assemble.dart';
import 'musicxml_overrides.dart';
import 'musicxml_read.dart';

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
  final score = withOverrides(assemble(read), read);
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
