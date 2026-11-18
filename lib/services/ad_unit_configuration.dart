/// Ad IDs are selected only by Dart's compiler build mode. There are deliberately
/// no CHESSUNLOCK_TEST_ADS or ad-unit environment overrides: release artifacts
/// must always use the fixed production units, including when old QA flags are
/// accidentally supplied. This is not an assertion (assertions vanish in release).
enum AdBuildMode { debug, profile, release }

enum NativePlacement {
  home,
  puzzle,
  settings;

  bool get usesMediaLayout => this != NativePlacement.puzzle;
}

class AdUnitConfiguration {
  static const mode = bool.fromEnvironment('dart.vm.product')
      ? AdBuildMode.release
      : bool.fromEnvironment('dart.vm.profile')
          ? AdBuildMode.profile
          : AdBuildMode.debug;
  static const testAds = mode != AdBuildMode.release;

  static String native(NativePlacement placement, {required bool ios}) {
    if (testAds) {
      return ios
          ? 'ca-app-pub-3940256099942544/3986624511'
          : 'ca-app-pub-3940256099942544/2247696110';
    }
    return switch (placement) {
      NativePlacement.home => ios
          ? 'ca-app-pub-8108010703558411/7621912982'
          : 'ca-app-pub-8108010703558411/8690297125',
      NativePlacement.puzzle => ios
          ? 'ca-app-pub-8108010703558411/9468192173'
          : 'ca-app-pub-8108010703558411/3654747815',
      NativePlacement.settings => ios
          ? 'ca-app-pub-8108010703558411/4804177952'
          : 'ca-app-pub-8108010703558411/6064133780',
    };
  }

  static String interstitial({required bool ios}) => testAds
      ? (ios
          ? 'ca-app-pub-3940256099942544/4411468910'
          : 'ca-app-pub-3940256099942544/1033173712')
      : (ios
          ? 'ca-app-pub-8108010703558411/3295655166'
          : 'ca-app-pub-8108010703558411/5706196084');

  static String rewarded({required bool ios}) => testAds
      ? (ios
          ? 'ca-app-pub-3940256099942544/1712485313'
          : 'ca-app-pub-3940256099942544/5224354917')
      : (ios
          ? 'ca-app-pub-8108010703558411/5800977815'
          : 'ca-app-pub-8108010703558411/1847579539');
}
