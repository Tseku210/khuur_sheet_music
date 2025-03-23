enum TimeSignatureType {
  twoFour(_timeSigTwoPathKey, _timeSigFourPathKey, 2, 4),
  twoTwo(_timeSigTwoPathKey, _timeSigTwoPathKey, 2, 2),
  threeFour(_timeSigThreePathKey, _timeSigFourPathKey, 3, 4),
  threeEight(_timeSigThreePathKey, _timeSigEightPathKey, 3, 8),
  fourFour(_timeSigFourPathKey, _timeSigFourPathKey, 4, 4),
  fourTwo(_timeSigFourPathKey, _timeSigTwoPathKey, 4, 2),
  fiveFour(_timeSigFivePathKey, _timeSigFourPathKey, 5, 4),
  sixEight(_timeSigSixPathKey, _timeSigEightPathKey, 6, 8),
  sevenEight(_timeSigSevenPathKey, _timeSigEightPathKey, 7, 8),
  nineEight(_timeSigNinePathKey, _timeSigEightPathKey, 9, 8);

  const TimeSignatureType(
    this.numeratorPathKey,
    this.denominatorPathKey,
    this.beats,
    this.beatUnit,
  );

  final String numeratorPathKey;
  final String denominatorPathKey;
  final int beats;
  final int beatUnit;

  // static const _timeSigZeroPathKey = 'uniE080';
  // static const _timeSigOnePathKey = 'uniE081';
  static const _timeSigTwoPathKey = 'uniE082';
  static const _timeSigThreePathKey = 'uniE083';
  static const _timeSigFourPathKey = 'uniE084';
  static const _timeSigFivePathKey = 'uniE085';
  static const _timeSigSixPathKey = 'uniE086';
  static const _timeSigSevenPathKey = 'uniE087';
  static const _timeSigEightPathKey = 'uniE088';
  static const _timeSigNinePathKey = 'uniE089';
  // static const _timeSigCommonTimePathKey = 'uniE08A';
}
