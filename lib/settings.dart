import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small app settings kept on the phone.
class AppSettings {
  static bool use24h = false;
  static int gpsMode = 2; // 0 = battery saver, 1 = balanced, 2 = high accuracy
  static final ValueNotifier<int> rev = ValueNotifier(0); // bumps when a setting changes (screens rebuild)

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    use24h = p.getBool('use24h') ?? false;
    gpsMode = p.getInt('gpsMode') ?? 2;
  }

  static Future<void> setUse24h(bool v) async {
    use24h = v;
    rev.value++;
    (await SharedPreferences.getInstance()).setBool('use24h', v);
  }

  static Future<void> setGpsMode(int m) async {
    gpsMode = m;
    rev.value++;
    (await SharedPreferences.getInstance()).setInt('gpsMode', m);
  }
}

String fmtTime(DateTime d) => DateFormat(AppSettings.use24h ? 'HH:mm' : 'h:mm a').format(d);
