enum TimeSignatureType {
  twoFour(_timeSigTwoPathKey, _timeSigFourPathKey),
  twoTwo(_timeSigTwoPathKey, _timeSigTwoPathKey),
  threeFour(_timeSigThreePathKey, _timeSigFourPathKey),
  threeEight(_timeSigThreePathKey, _timeSigEightPathKey),
  fourFour(_timeSigFourPathKey, _timeSigFourPathKey),
  fourTwo(_timeSigFourPathKey, _timeSigTwoPathKey),
  fiveFour(_timeSigFivePathKey, _timeSigFourPathKey),
  sixEight(_timeSigSixPathKey, _timeSigEightPathKey),
  sevenEight(_timeSigSevenPathKey, _timeSigEightPathKey),
  nineEight(_timeSigNinePathKey, _timeSigEightPathKey);

  const TimeSignatureType(this.numeratorPathKey, this.denominatorPathKey);

  final String numeratorPathKey;
  final String denominatorPathKey;

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
