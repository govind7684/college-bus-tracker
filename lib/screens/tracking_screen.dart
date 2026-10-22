import 'package:flutter/material.dart';
import '../data.dart';
import '../widgets.dart';

/// Full-screen live view of one bus (driver "Live view"). The bus photo is shown whole, the title sits
/// below it, and Back returns to the previous panel without touching the login or the GPS sharing.
class TrackingScreen extends StatelessWidget {
  final String busId;
  const TrackingScreen({super.key, required this.busId});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: LiveRoute(
          busId: busId,
          builder: (c, r, l) => ListView(padding: EdgeInsets.zero, children: [
            HeroHeader(
              title: 'College Bus Route',
              busId: busId,
              subtitle: '${r.plateFor(busId)}  ·  ${busInfo(busId).label.toUpperCase()}',
              onBack: () => Navigator.maybePop(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: TrackerBody(busId: busId, route: r, live: l, detailed: true, photo: false),
            ),
          ]),
        ),
      );
}
