import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

/// The phone's region for For you (#170): the country set in iOS Settings →
/// General → Language & Region (Android: the system's locale), as two
/// capital letters; null when the phone has none. It is read on the phone
/// and never stored on the server, which sees it only as `for=`.
String? phoneRegion() =>
    regionOf(Platform.localeName) ??
    regionOf(PlatformDispatcher.instance.locale.toLanguageTag());

/// Where the app reads the phone's region; tests set their own.
String? Function() readPhoneRegion = phoneRegion;

/// The country in a locale name: `cs_CZ`, `en-CZ` and `en_CZ.UTF-8` are CZ,
/// `zh_Hans_CN` is CN. A region of digits (`es_419`, Latin America) is no
/// country, and a language alone (`en`) has none: null.
String? regionOf(String locale) {
  for (final part in locale.split(RegExp('[-_.@]')).skip(1)) {
    if (RegExp(r'^[A-Za-z]{2}$').hasMatch(part)) return part.toUpperCase();
  }
  return null;
}
