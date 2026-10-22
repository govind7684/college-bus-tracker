# College Bus – Carmel Polytechnic College, Punnapra

## Setup
1. `flutter create --org com.carmel --project-name college_bus .`  (inside this folder; keeps lib/, pubspec, assets)
2. `flutter pub get`
3. `dart pub global activate flutterfire_cli && flutterfire configure`  → generates `lib/firebase_options.dart`
4. Android: in `android/app/src/main/AndroidManifest.xml` add inside <manifest>:
   `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>`
   `<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>`
   `<uses-permission android:name="android.permission.INTERNET"/>`
   `<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>`
   `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>`
   `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`
   `<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>`
   and set `minSdkVersion 23` in android/app/build.gradle.
   iOS: add NSLocationWhenInUseUsageDescription to Info.plist.
5. App icon: `dart run flutter_launcher_icons`
6. Firebase console: enable Email/Password auth, create Firestore, publish `firestore.rules`.
7. Create a driver: create the user in Authentication, then add a doc `app2_users/<uid>` with `{name, role:"driver", bus:"bus1"}` (use `bus:"bus2"` for the second bus; missing = bus1).
8. Log in as driver → Route tab → add stops (MORNING order, college last) → Save. Saving snaps every stop to the road (OSRM), numbers the stops and stores road distance + driving time per stop. Use the Forward / Return switch for the return itinerary.

## Firestore
- Per bus: `buses/bus1_live`, `buses/bus1_route`, `buses/bus2_live`, `buses/bus2_route`
  (live GPS / trip state, and stops + OSRM geometry; optional `plate` field on the route doc sets the number plate shown).
  Bus 1 still reads the old `bus/live` + `bus/bus2_route` documents until its own documents exist, so no migration is needed.
- `app2_students/<uid>` `{uid, name, email, stop, bus}` (missing `bus` = bus1), `app2_users/<uid>` `{name, role, bus}`
- `app2_attendance/<uid>_<yyyy-MM-dd>`: `morningStatus/eveningStatus`, plus per journey `…Bus` (bus actually ridden),
  `…Contingency` (true = emergency switch), `…Stop` (stop boarded). Contingency riders appear in the destination bus
  driver's "Special contingency log" for that journey.
- `app2_announcements`
- Publish the updated `firestore.rules` (drivers can only write their own bus's documents).

## Login
Firebase Auth keeps the session on the device. The only thing that logs out is the Log out button.
Passwords are never stored in Firestore – only the profile (uid, name, email, bus, stop) is.

## Navigate button (Google Maps turn-by-turn) and Call buttons
Navigate opens the native Google Maps app in navigation mode (`google.navigation:q=lat,lng&mode=d`) to the NEXT stop
(first stop if the trip has not started), and falls back to the Google Maps web link if the app is missing.
So Android 11+ can see Google Maps and the dialler, add this inside `<manifest>` (NOT inside `<application>`) in
`android/app/src/main/AndroidManifest.xml`:

```xml
<queries>
  <package android:name="com.google.android.apps.maps"/>
  <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="google.navigation"/></intent>
  <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
  <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>
</queries>
```
iOS: add `comgooglemaps` under `LSApplicationQueriesSchemes` in Info.plist.

Fleet contacts live in `kBuses` (lib/data.dart): Bus 1 +91 98479 81461, Bus 2 +91 77367 31853.

## Stop progress rules
- Standard rule (Bus 2, and every return journey): a stop is Passed when the bus reaches or crosses it, and so is every
  stop behind it (position along the road geometry of THAT journey; the return journey never uses forward coordinates).
- Bus 1 morning run only: while the bus is before its second stop (e.g. Ochira -> Mukkada) the status shows the first stop
  ("Heading to Ochira") and nothing is Passed yet. Once it passes the second stop, or any later one, that stop and all
  behind it are Passed. (`Live.firstStopRule` in lib/data.dart.)
- Progress is saved on the phone (SharedPreferences): the driver's running trip (bus, direction, progress) and the last
  live state of each bus. After the app is closed / killed / restarted the trip is resumed and every stop behind the bus
  is Passed immediately.

## Road snapping
Stops are snapped to the main road centre line using OSRM with the direction of travel (`bearings` + `radiuses`), so a
stop at a junction lands on the main road, not on a side lane or canal road. Saving also detects detour legs (road
distance far larger than the gap between two stops) and moves the stop to the nearby road position with the shortest way.
If a detour remains the editor / Save message names the stops to adjust.

## Stage 1 - Administrator role, closed student registration, stop-progress hardening
Publish the new `firestore.rules` (Firebase Console > Firestore > Rules) before running the app.

**Administrator account** (done once in the Firebase Console):
1. Authentication > Users > Add user (email + password).
2. Firestore > `app2_users` > add a document whose id is that user's UID with fields `name` (string), `role` = `admin`.
3. In the app: Welcome > Driver/Student login > "Institution login" and sign in.
Drivers stay as before (`role` = `driver`, `bus` = `bus1` / `bus2`). Setting `active` = false (or `status` = `inactive`)
on any staff document blocks that account.

**Students can no longer sign up freely.** The institution adds each student to `app2_roster` first; the document id
is the student's email in lower case, e.g. `ajay@example.com`, with fields:
`name`, `admissionNo`, `bus` (`bus1`/`bus2`), `status` = `approved`, optional `className`, `phone`, `guardianName`,
`guardianPhone`, `stop`. The student then taps "Activate account", enters the email, admission number and a password.
Unregistered emails are rejected (and their login is deleted again). Existing students keep working unchanged.
Set `status` = `inactive` on `app2_students/<uid>` to deactivate a student (nothing is ever deleted).
(Until the student-management screen arrives in Stage 2, roster entries are added in the Firestore console.)

**Tracking:** a stop only becomes Passed after two consecutive GPS fixes agree (one noisy point cannot skip a stop; a
re-check after an app restart applies at once), stale cached GPS fixes are ignored, and every passed stop is written once
to `app2_trips/<bus>_<date>_<direction>` (forward and return trips have separate histories; replays cannot duplicate).
Admin actions go to `app2_audit` through `lib/services/audit_service.dart`.
Tests: `flutter test test/stop_progress_test.dart`.

## Stage 2 - Admin management screens
Institution login now opens a dashboard with three menus:
- **Students**: search / filter (bus, status), add a student (writes `app2_roster`), edit details, change bus, deactivate
  (never deleted), CSV export (copied to the clipboard) and CSV import (paste rows: name,email,admissionNo,className,bus,phone).
- **Drivers**: list, edit, assign bus, activate / deactivate, add by Firebase UID (create the login in Authentication first).
- **Buses & routes**: plate, contact, driver, active students, trip status and the saved stops (stops are still edited by the
  bus's driver in the Route tab).
Every change is written to `app2_audit`.
