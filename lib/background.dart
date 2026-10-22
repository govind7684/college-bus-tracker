import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data.dart' show busInfo;

/// Sends the app to the background (phone home screen) WITHOUT closing it,
/// so the driver's GPS sharing and login keep running.
Future<void> goToPhoneHome() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.HOME',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
      return;
    } catch (_) {}
  }
  await SystemNavigator.pop();
}

/// Starts Google Maps turn-by-turn navigation to a stop.
/// 1) Android: the native Google Maps app in navigation mode (google.navigation: intent).
/// 2) iOS: the Google Maps app (comgooglemaps://), if installed.
/// 3) Anything else / app missing: the Google Maps web URL, which starts navigation in the browser.
/// Returns false only when even the web fallback could not be opened.
Future<bool> openTurnByTurn(double lat, double lng) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final intent = AndroidIntent(
        action: 'action_view',
        data: 'google.navigation:q=$lat,$lng&mode=d',
        package: 'com.google.android.apps.maps',
      );
      if (await intent.canResolveActivity() ?? false) {
        await intent.launch();
        return true;
      }
    } catch (_) {}
    try {
      if (await launchUrl(Uri.parse('google.navigation:q=$lat,$lng&mode=d'), mode: LaunchMode.externalApplication)) return true;
    } catch (_) {}
  } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      if (await launchUrl(Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving'), mode: LaunchMode.externalApplication)) return true;
    } catch (_) {}
  }
  try {
    return await launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving&dir_action=navigate'),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// Opens the phone dialler with the fleet contact (driver / coordinator) of [busId].
Future<bool> callFleet(String busId) async {
  final phone = busInfo(busId).phone;
  if (phone.isEmpty) return false;
  try {
    return await launchUrl(Uri(scheme: 'tel', path: phone));
  } catch (_) {
    return false;
  }
}
