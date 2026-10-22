import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Palette: dark olive + warm cream + bus-yellow (like the "Carmel Bus Tracker" reference).
const kBg = Color(0xFF22211C);
const kBg2 = Color(0xFF2A2923);
const kCard = Color(0xFF302F28);
const kLine = Color(0xFF45443B);
const kInk = Color(0xFFF0EBDC); // main text (cream)
const kMuted = Color(0xFFA8A28E);
const kOnGold = Color(0xFF1F1E19); // text on yellow
const kYellow = Color(0xFFE5AB2E);
const kAmber = Color(0xFFF0B44A);
const kGreen = Color(0xFF86CF86);
const kBlue = Color(0xFF86AEDB);
const kRed = Color(0xFFE8776F);
const kMint = Color(0xFF1DF2A0); // splash loading line
const kNavy = Color(0xFF0A1120); // welcome / login background
const kGold = Color(0xFFF9C31F); // welcome button + accents

/// Native aspect ratio of assets/images/bus_sunset_wide.jpg (the whole bus, nothing cropped).
const kHeroAspect = 903 / 677;
const kHeroAsset = 'assets/images/bus_sunset_wide.jpg';

const kSerif = 'serif';

extension ColorX on Color {
  /// Same as withOpacity but not deprecated.
  Color o(double v) => withAlpha((v * 255).round().clamp(0, 255).toInt());
}

TextStyle serif(double size, {FontWeight w = FontWeight.w700, Color color = kInk, double? height, double? spacing}) =>
    TextStyle(fontFamily: kSerif, fontSize: size, fontWeight: w, color: color, height: height, letterSpacing: spacing);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  OutlineInputBorder border(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: const ColorScheme.dark(
      primary: kYellow,
      onPrimary: kOnGold,
      secondary: kYellow,
      onSecondary: kOnGold,
      surface: kCard,
      onSurface: kInk,
      error: kRed,
    ),
    textTheme: base.textTheme.apply(bodyColor: kInk, displayColor: kInk),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kInk,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kCard,
      hintStyle: const TextStyle(color: kMuted),
      border: border(kLine),
      enabledBorder: border(kLine),
      focusedBorder: border(kYellow, 1.3),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kYellow,
        foregroundColor: kOnGold,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        side: const BorderSide(color: kLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerColor: kLine,
    drawerTheme: const DrawerThemeData(backgroundColor: kBg2),
  );
}
