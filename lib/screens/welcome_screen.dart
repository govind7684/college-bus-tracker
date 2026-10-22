import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'login_screen.dart';
import 'parent_screen.dart';

/// First screen when logged out: navy night-to-sunset layout with the whole bus visible,
/// "Your College Bus, In Your Hands." and the START TRACKING button.
/// Scrolls on short screens, so nothing is ever clipped.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _go(BuildContext c, Widget w) {
    HapticFeedback.selectionClick();
    Navigator.push(c, MaterialPageRoute<void>(builder: (_) => w));
  }

  Widget _logo() => Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
        Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 60, height: 60,
            decoration: BoxDecoration(border: Border.all(color: kGold, width: 2.5), borderRadius: BorderRadius.circular(4)),
            child: Transform.rotate(angle: -math.pi / 4, child: const Icon(Icons.directions_bus_rounded, color: kGold, size: 30)),
          ),
        ),
        const SizedBox(width: 24),
        Flexible(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('CARMEL', style: TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w800, letterSpacing: 3, height: 1.05)),
            ),
            const SizedBox(height: 4),
            Text('POLYTECHNIC COLLEGE', style: TextStyle(color: Colors.white.o(.85), fontSize: 12, letterSpacing: 3.2, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 26, height: 1.5, color: kGold),
              const SizedBox(width: 10),
              Text('PUNNAPRA', style: TextStyle(color: Colors.white.o(.85), fontSize: 12, letterSpacing: 5, fontWeight: FontWeight.w500)),
              const SizedBox(width: 10),
              Container(width: 26, height: 1.5, color: kGold),
            ]),
          ]),
        ),
      ]);

  /// The whole bus (nothing cropped), fading into the navy background above and below it.
  Widget _busPhoto() => Stack(children: [
        ClipRect(
          child: Align(
            alignment: const Alignment(0, -.2),
            heightFactor: .74, // shows ~10%..84% of the photo: the bus sits at ~17%..73%
            child: AspectRatio(aspectRatio: 903 / 1095, child: Image.asset('assets/images/bus_sunset.jpg', fit: BoxFit.cover, cacheWidth: 1100)),
          ),
        ),
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kNavy, Color(0x000A1120), Color(0x000A1120), kNavy],
                  stops: [0, .24, .8, 1],
                ),
              ),
            ),
          ),
        ),
      ]);

  Widget _link(BuildContext c, IconData icon, String label, Widget page) => TextButton.icon(
        onPressed: () => _go(c, page),
        icon: Icon(icon, color: Colors.white.o(.8), size: 22),
        label: Text(label, style: TextStyle(color: Colors.white.o(.9), fontSize: 14.5, letterSpacing: .3)),
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kNavy,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0E1A33), kNavy, Color(0xFF060A13)]),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(children: [
                      Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 0), child: _logo()),
                      _busPhoto(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('TRACK YOUR BUS.\nREACH ON TIME.', style: TextStyle(color: kGold, fontSize: 12.5, letterSpacing: 2.6, height: 1.45, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Container(width: 54, height: 2, color: kGold),
                          const SizedBox(height: 16),
                          const Text.rich(
                            TextSpan(children: [
                              TextSpan(text: 'Your College Bus,\n'),
                              TextSpan(text: 'In Your Hands.', style: TextStyle(color: kGold)),
                            ]),
                            style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, height: 1.15),
                          ),
                          const SizedBox(height: 10),
                          Text('Live location. Real-time updates.\nSafer journeys.', style: TextStyle(color: Colors.white.o(.7), fontSize: 15, height: 1.4)),
                        ]),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
                        child: Material(
                          color: kGold,
                          borderRadius: BorderRadius.circular(40),
                          elevation: 6,
                          shadowColor: kGold.o(.5),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(40),
                            onTap: () => _go(context, const LoginScreen(isDriver: false)),
                            child: const SizedBox(
                              height: 62,
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.location_on, color: kOnGold, size: 26),
                                SizedBox(width: 18),
                                Text('START TRACKING', style: TextStyle(color: kOnGold, fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2.4)),
                                SizedBox(width: 18),
                                Icon(Icons.arrow_forward, color: kOnGold, size: 24),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        _link(context, Icons.drive_eta_outlined, 'Driver login', const LoginScreen(isDriver: true)),
                        Container(width: 1, height: 26, color: Colors.white.o(.25)),
                        _link(context, Icons.groups_outlined, 'Parent view', const ParentScreen()),
                      ]),
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 16),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          for (var i = 0; i < 3; i++)
                            Container(width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 5), decoration: BoxDecoration(color: i == 0 ? kGold : Colors.white.o(.3), shape: BoxShape.circle)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
