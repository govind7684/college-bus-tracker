import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data.dart';
import 'settings.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'screens/admin/admin_home.dart';
import 'screens/driver_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/splash.dart';
import 'screens/student_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light));
  // The app starts drawing the splash immediately; Firebase + settings load behind it (see [bootApp]).
  runApp(const CollegeBusApp());
}

/// Cold-start work, run while the splash is visible. Settings and Firebase start together, then the
/// saved login is restored. The login is stored by Firebase Auth (disk on mobile, IndexedDB/local storage
/// on web) and only ever cleared by the explicit Logout button.
Future<void> bootApp() async {
  await Future.wait<void>([
    AppSettings.load(),
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).then<void>((_) {}),
  ]);
  final auth = FirebaseAuth.instance;
  if (kIsWeb) await auth.setPersistence(Persistence.LOCAL); // survive tab/browser close
  // wait (briefly) for Firebase to restore the saved session so the right panel opens directly
  await auth.authStateChanges().first.timeout(const Duration(milliseconds: 1500), onTimeout: () => auth.currentUser);
}

class CollegeBusApp extends StatelessWidget {
  const CollegeBusApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'College Bus',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // On wide screens (web/desktop) keep the phone-style layout centred.
        builder: (context, child) => ColoredBox(
          color: kBg,
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: child)),
        ),
        home: const SplashScreen(init: bootApp, next: AuthGate()),
      );
}

/// Firebase keeps the user signed in until they press Logout.
/// Signed out -> role chooser. Signed in -> admin, driver or student panel (deactivated / unregistered accounts are blocked).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        initialData: FirebaseAuth.instance.currentUser,
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (c, s) {
          if (s.connectionState == ConnectionState.waiting && s.data == null) return const BootScreen(resume: true);
          final u = s.data;
          if (u == null) return const WelcomeScreen();
          return _RoleGate(key: ValueKey(u.uid), user: u);
        },
      );
}

class _RoleGate extends StatefulWidget {
  final User user;
  const _RoleGate({super.key, required this.user});
  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  String? _role;
  String _bus = 'bus1'; // driver: the bus this driver runs
  String _status = 'active';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = widget.user.uid;
    final cached = await Session.role(uid);
    final cachedBus = await Session.bus(uid);
    if (cached != null && mounted) {
      setState(() { _role = cached; _bus = cachedBus ?? 'bus1'; }); // opens instantly
    }
    try {
      final fresh = await Session.fetchAccount(uid);
      if (fresh.role != 'none') {
        await Session.setRole(uid, fresh.role);
        await Session.setBus(uid, fresh.bus);
      }
      if (mounted) setState(() { _role = fresh.role; _bus = fresh.bus; _status = fresh.status; });
    } catch (e) {
      if (mounted && _role == null) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_role == 'none' || (_role != null && _status != 'active')) {
      final unreg = _role == 'none';
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(unreg ? Icons.gpp_maybe_rounded : Icons.block_rounded, size: 52, color: kRed),
              const SizedBox(height: 14),
              Text(unreg ? 'Account not registered' : (_status == 'pending' ? 'Waiting for approval' : 'Account deactivated'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                unreg
                    ? 'This email is not registered by the institution. Please contact the transport office.'
                    : (_status == 'pending'
                        ? 'The institution has not approved this account yet.'
                        : 'This account is not active. Please contact the transport office.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Log out')),
            ]),
          ),
        ),
      );
    }
    if (_role == 'admin') return const AdminHome();
    if (_role == 'driver') return DriverScreen(key: ValueKey(_bus), busId: _bus);
    if (_role == 'student') return const StudentScreen();
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.wifi_off_rounded, size: 52, color: kMuted),
              const SizedBox(height: 14),
              const Text('Could not load your account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Check your internet connection and try again.\n$_error',
                  textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: () { setState(() => _error = null); _load(); }, child: const Text('Retry')),
              TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Log out')),
            ]),
          ),
        ),
      );
    }
    return const BootScreen(resume: true);
  }
}
