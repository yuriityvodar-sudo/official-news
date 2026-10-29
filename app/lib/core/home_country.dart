import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The phone's region for For you (#170): the country set in iOS Settings →
/// General → Language & Region → Region, as two capital letters, asked of
/// iOS itself (`official_news/region` in the Runner). Flutter's own locale
/// is the first preferred language, whose region can be another: "en-GB" on
/// a phone set to Germany (Yurii, #201). Null elsewhere (Android keeps no
/// region apart from its languages) and when iOS gives none: the server is
/// then asked (`GET /locate`). Read on the phone and never stored on the
/// server, which sees it only as `for=`.
Future<String?> phoneRegion() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return null;
  try {
    final region = await _channel.invokeMethod<String>('region');
    return region != null && RegExp(r'^[A-Z]{2}$').hasMatch(region)
        ? region
        : null;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

const _channel = MethodChannel('official_news/region');

/// Where the app reads the phone's region; tests set their own.
Future<String?> Function() readPhoneRegion = phoneRegion;
