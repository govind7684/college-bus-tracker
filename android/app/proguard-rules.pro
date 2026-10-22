# Absolute broad protection for shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class dev.flutter.plugins.sharedpreferences.** { *; }

# General safety rule for all native Flutter plugin registries
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.embedding.** { *; }
# Tell R8 to ignore missing Google Play Core dynamic feature splitting classes
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
