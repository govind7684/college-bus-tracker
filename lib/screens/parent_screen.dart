import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets.dart';

/// Read-only parent view (no login): pick Bus 1 or Bus 2, see trip status, speed, next stop, ETA and the
/// vertical stop timeline. Back returns to where the user came from.
class ParentScreen extends StatefulWidget {
  const ParentScreen({super.key});
  @override
  State<ParentScreen> createState() => _ParentScreenState();
}

class _ParentScreenState extends State<ParentScreen> {
  String _bus = 'bus1';

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            Row(children: [
              CircleBtn(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.maybePop(context)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Parent view', style: serif(26)),
                  const Text('Live bus status • read-only', style: TextStyle(color: kMuted, fontSize: 12.5)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            BusSwitcher(value: _bus, onChanged: (b) => setState(() => _bus = b)),
            const SizedBox(height: 12),
            LiveRoute(busId: _bus, builder: (c, r, l) => TrackerBody(busId: _bus, route: r, live: l)),
          ]),
        ),
      );
}
