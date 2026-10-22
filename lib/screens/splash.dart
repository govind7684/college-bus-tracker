import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Splash artwork with ONE continuous green line that fills smoothly where the loading bar belongs.
/// It runs once (no looping / restarting segments). [resume] continues from the splash's last position
/// (used while the account is still loading), so the hand-over between the two looks like a single bar.
class BootScreen extends StatefulWidget {
  final bool resume;
  const BootScreen({super.key, this.resume = false});
  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: widget.resume ? 450 : 1100))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Artwork is 903x1742; the bar sits at x 311..588, y 1478..1492.
  static const _w = 903.0, _h = 1742.0;

  double get _progress {
    final t = Curves.easeOutCubic.transform(_c.value);
    return widget.resume ? 0.9 + 0.1 * t : 0.9 * t;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kNavy,
        body: LayoutBuilder(builder: (context, box) {
          final scale = max(box.maxWidth / _w, box.maxHeight / _h); // BoxFit.cover
          final dx = (box.maxWidth - _w * scale) / 2;
          final dy = (box.maxHeight - _h * scale) / 2;
          final barH = max(5.0, 13 * scale);
          return Stack(fit: StackFit.expand, children: [
            Image.asset('assets/images/splash_bus.png', fit: BoxFit.cover, cacheWidth: 1100),
            Positioned(
              left: dx + 311 * scale,
              top: dy + 1478 * scale,
              width: 277 * scale,
              height: barH,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => Stack(children: [
                  // track
                  Positioned.fill(
                    child: DecoratedBox(decoration: BoxDecoration(color: Colors.white.o(.16), borderRadius: BorderRadius.circular(barH))),
                  ),
                  // the single green line
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _progress.clamp(0.01, 1.0).toDouble(),
                      child: Container(
                        height: barH,
                        decoration: BoxDecoration(
                          color: kMint,
                          borderRadius: BorderRadius.circular(barH),
                          boxShadow: [BoxShadow(color: kMint.o(.5), blurRadius: 8)],
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        }),
      );
}

/// Shows the splash while [init] runs (Firebase, settings, restoring the saved login) and moves on as
/// soon as it is done – at least ~1.1 s so the line can draw, never a fixed long wait.
class SplashScreen extends StatefulWidget {
  final Future<void> Function() init;
  final Widget next;
  const SplashScreen({super.key, required this.init, required this.next});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await Future.wait<void>([widget.init(), Future<void>.delayed(const Duration(milliseconds: 1100))]);
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => widget.next,
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_error == null) return const BootScreen();
    return Scaffold(
      backgroundColor: kNavy,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 52, color: kMuted),
            const SizedBox(height: 14),
            const Text('Could not start the app', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('$_error', textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 12)),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () {
                setState(() => _error = null);
                _run();
              },
              child: const Text('Retry'),
            ),
          ]),
        ),
      ),
    );
  }
}
