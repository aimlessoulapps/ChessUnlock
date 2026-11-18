// Standalone regression probe: run with Dart's actual compiler mode constants,
// including an AOT product build where assertions are disabled.
import 'dart:io';
import 'package:chessUnlock/services/ad_unit_configuration.dart';

void main(List<String> args) {
  if (args.length != 1 ||
      !['debug', 'profile', 'release'].contains(args.single)) {
    throw ArgumentError('Pass the independently expected build mode.');
  }
  final expectedMode = args.single;
  if (AdUnitConfiguration.mode.name != expectedMode) {
    throw StateError('Expected $expectedMode, got ${AdUnitConfiguration.mode}');
  }
  final production = expectedMode == 'release';
  if (AdUnitConfiguration.testAds == production) {
    throw StateError('Incorrect test-ad policy for $expectedMode');
  }
  const productionIds = {
    false: [
      'ca-app-pub-8108010703558411/8690297125',
      'ca-app-pub-8108010703558411/3654747815',
      'ca-app-pub-8108010703558411/6064133780',
      'ca-app-pub-8108010703558411/5706196084',
      'ca-app-pub-8108010703558411/1847579539',
    ],
    true: [
      'ca-app-pub-8108010703558411/7621912982',
      'ca-app-pub-8108010703558411/9468192173',
      'ca-app-pub-8108010703558411/4804177952',
      'ca-app-pub-8108010703558411/3295655166',
      'ca-app-pub-8108010703558411/5800977815',
    ],
  };
  const testIds = {
    false: [
      'ca-app-pub-3940256099942544/2247696110',
      'ca-app-pub-3940256099942544/2247696110',
      'ca-app-pub-3940256099942544/2247696110',
      'ca-app-pub-3940256099942544/1033173712',
      'ca-app-pub-3940256099942544/5224354917',
    ],
    true: [
      'ca-app-pub-3940256099942544/3986624511',
      'ca-app-pub-3940256099942544/3986624511',
      'ca-app-pub-3940256099942544/3986624511',
      'ca-app-pub-3940256099942544/4411468910',
      'ca-app-pub-3940256099942544/1712485313',
    ],
  };
  for (final ios in [false, true]) {
    final actual = [
      for (final placement in NativePlacement.values)
        AdUnitConfiguration.native(placement, ios: ios),
      AdUnitConfiguration.interstitial(ios: ios),
      AdUnitConfiguration.rewarded(ios: ios),
    ];
    final expected = (production ? productionIds : testIds)[ios]!;
    for (var i = 0; i < expected.length; i++) {
      if (actual[i] != expected[i]) {
        throw StateError(
            '$expectedMode ios=$ios placement=$i: ${actual[i]} != ${expected[i]}');
      }
    }
  }
  stdout.writeln('PASS $expectedMode: all 10 Android/iOS placement IDs');
}
