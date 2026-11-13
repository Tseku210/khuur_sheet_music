import 'package:score_layout/score_layout.dart';

/// A copy of some defaults with the default of one SMuFL name changed. A
/// default without a row here fails the test of the copies.
final withDefault =
    <String, EngravingDefaults Function(EngravingDefaults, double)>{
      'arrowShaftThickness': (defaults, value) =>
          defaults.copyWith(arrowShaftThickness: value),
      'barlineSeparation': (defaults, value) =>
          defaults.copyWith(barlineSeparation: value),
      'beamSpacing': (defaults, value) => defaults.copyWith(beamSpacing: value),
      'beamThickness': (defaults, value) =>
          defaults.copyWith(beamThickness: value),
      'bracketThickness': (defaults, value) =>
          defaults.copyWith(bracketThickness: value),
      'dashedBarlineDashLength': (defaults, value) =>
          defaults.copyWith(dashedBarlineDashLength: value),
      'dashedBarlineGapLength': (defaults, value) =>
          defaults.copyWith(dashedBarlineGapLength: value),
      'dashedBarlineThickness': (defaults, value) =>
          defaults.copyWith(dashedBarlineThickness: value),
      'hBarThickness': (defaults, value) =>
          defaults.copyWith(hBarThickness: value),
      'hairpinThickness': (defaults, value) =>
          defaults.copyWith(hairpinThickness: value),
      'legerLineExtension': (defaults, value) =>
          defaults.copyWith(legerLineExtension: value),
      'legerLineThickness': (defaults, value) =>
          defaults.copyWith(legerLineThickness: value),
      'lyricLineThickness': (defaults, value) =>
          defaults.copyWith(lyricLineThickness: value),
      'octaveLineThickness': (defaults, value) =>
          defaults.copyWith(octaveLineThickness: value),
      'pedalLineThickness': (defaults, value) =>
          defaults.copyWith(pedalLineThickness: value),
      'repeatBarlineDotSeparation': (defaults, value) =>
          defaults.copyWith(repeatBarlineDotSeparation: value),
      'repeatEndingLineThickness': (defaults, value) =>
          defaults.copyWith(repeatEndingLineThickness: value),
      'slurEndpointThickness': (defaults, value) =>
          defaults.copyWith(slurEndpointThickness: value),
      'slurMidpointThickness': (defaults, value) =>
          defaults.copyWith(slurMidpointThickness: value),
      'staffLineThickness': (defaults, value) =>
          defaults.copyWith(staffLineThickness: value),
      'stemThickness': (defaults, value) =>
          defaults.copyWith(stemThickness: value),
      'subBracketThickness': (defaults, value) =>
          defaults.copyWith(subBracketThickness: value),
      'textEnclosureThickness': (defaults, value) =>
          defaults.copyWith(textEnclosureThickness: value),
      'thickBarlineThickness': (defaults, value) =>
          defaults.copyWith(thickBarlineThickness: value),
      'thinBarlineThickness': (defaults, value) =>
          defaults.copyWith(thinBarlineThickness: value),
      'tieEndpointThickness': (defaults, value) =>
          defaults.copyWith(tieEndpointThickness: value),
      'tieMidpointThickness': (defaults, value) =>
          defaults.copyWith(tieMidpointThickness: value),
      'tupletBracketThickness': (defaults, value) =>
          defaults.copyWith(tupletBracketThickness: value),
    };
