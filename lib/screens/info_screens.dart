import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../background.dart' show callFleet;
import '../data.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';

Widget _page(BuildContext context, String title, String subtitle, Widget body) => Scaffold(
      body: Column(children: [
        ScreenTitle(title: title, subtitle: subtitle, back: true),
        Expanded(child: body),
      ]),
    );

Widget _chips(List<String> labels, int selected, ValueChanged<int> onSelect) => Wrap(spacing: 8, children: [
      for (var i = 0; i < labels.length; i++)
        ChoiceChip(
          label: Text(labels[i]),
          selected: selected == i,
          selectedColor: kYellow,
          backgroundColor: kCard,
          labelStyle: TextStyle(fontWeight: FontWeight.w700, color: selected == i ? kOnGold : kMuted),
          side: const BorderSide(color: kLine),
          showCheckmark: false,
          onSelected: (_) => onSelect(i),
        ),
    ]);

// ---------------- BUS DETAILS ----------------
class BusDetailsScreen extends StatelessWidget {
  final String busId;
  const BusDetailsScreen({super.key, required this.busId});

  Widget _kv(String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(color: kMuted, fontSize: 12)),
          const SizedBox(height: 2),
          Text(v.isEmpty ? '—' : v, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) => _page(
        context,
        'Bus details',
        'Carmel Polytechnic College • ${busInfo(busId).label}',
        LiveRoute(busId: busId, builder: (c, r, l) {
          final plan = r.plan(l.direction);
          final stops = plan.stops;
          final n = stops.length;
          final nxt = l.nextIn(r);
          final dest = n > 0 ? l.remaining(r, n - 1) : null;
          final near = n == 0 ? '—' : (!l.running ? 'Not running right now' : (nxt > 0 && nxt <= n ? 'Near ${stops[nxt - 1].name}' : 'Before ${stops.first.name}'));
          final canMap = l.hasFix && l.running;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              // the photo's own aspect ratio: the whole bus is visible, nothing is cropped
              child: BusPhoto(busId: busId),
            ),
            const SizedBox(height: 14),
            Card2(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.directions_bus_rounded, color: kOnGold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(r.plateFor(busId), style: serif(21))),
                  StatusChip(l.breakdown ? 'Breakdown' : l.running ? 'On route' : 'Not running', l.breakdown ? kRed : l.running ? kGreen : kMuted),
                ]),
                const Divider(height: 26),
                Row(children: [_kv('Driver name', l.driverName), _kv('Contact', busInfo(busId).phoneText)]),
                const SizedBox(height: 14),
                Row(children: [
                  _kv('Route', n >= 2 ? '${stops.first.name} → ${stops.last.name}' : '—'),
                  _kv('Stops', n == 0 ? '—' : '$n stops • ${(plan.totalMeters / 1000).toStringAsFixed(1)} km • ~${durText(plan.totalSeconds)}'),
                ]),
              ]),
            ),
            const SectionLabel('Current location'),
            Card2(
              child: Row(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(color: kBlue.o(.16), shape: BoxShape.circle),
                  child: const Icon(Icons.location_on, color: kBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(near, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(dest == null ? 'Distance not available' : '${kmText(dest)} from ${n > 0 ? stops.last.name : 'college'}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
                  ]),
                ),
              ]),
            ),
            if (busInfo(busId).phone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: kGreen, side: const BorderSide(color: kGreen)),
                  icon: const Icon(Icons.call_rounded),
                  label: Text('Call ${busInfo(busId).label} • ${busInfo(busId).phoneText}'),
                  onPressed: () => callFleet(busId),
                ),
              ),
            GradientButton(
              label: 'Open in Maps app',
              icon: Icons.location_on_outlined,
              onPressed: canMap ? () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${l.lat},${l.lng}'), mode: LaunchMode.externalApplication) : null,
            ),
          ]);
        }),
      );
}

// ---------------- BUS SCHEDULE (today's trips) ----------------
class TripsScreen extends StatelessWidget {
  final String busId;
  const TripsScreen({super.key, required this.busId});

  @override
  Widget build(BuildContext context) => _page(
        context,
        'Bus schedule',
        '${busInfo(busId).label} • ${DateFormat('EEEE, d MMM').format(DateTime.now())}',
        LiveRoute(busId: busId, builder: (c, r, l) {
          Widget trip(String dir, String title) {
            final plan = r.plan(dir);
            final s = plan.stops;
            String status;
            Color color;
            if (l.isToday && l.rawDirection == dir) {
              status = l.running ? 'On route' : 'Completed';
              color = kGreen;
            } else {
              status = 'Scheduled';
              color = kMuted;
            }
            return Card2(
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: kYellow, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.directions_bus_rounded, color: kOnGold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: serif(17)),
                    const SizedBox(height: 2),
                    Text(s.length >= 2 ? '${s.first.name} → ${s.last.name}' : 'Route not set', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 13)),
                    if (s.length >= 2) Text('${s.length} stops • ${(plan.totalMeters / 1000).toStringAsFixed(1)} km • ~${durText(plan.totalSeconds)}', style: const TextStyle(color: kMuted, fontSize: 12)),
                  ]),
                ),
                StatusChip(status, color),
              ]),
            );
          }

          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            trip('morning', 'Morning trip'),
            trip('evening', 'Evening trip'),
          ]);
        }),
      );
}

// ---------------- UPDATES (tab: bus alerts + announcements) ----------------
class NotificationsContent extends StatefulWidget {
  final String busId;
  const NotificationsContent({super.key, required this.busId});
  @override
  State<NotificationsContent> createState() => _NotificationsContentState();
}

class _NotificationsContentState extends State<NotificationsContent> {
  int _f = 0; // 0 all, 1 bus, 2 announcements

  @override
  Widget build(BuildContext context) => Column(children: [
        const ScreenTitle(title: 'Updates', subtitle: 'Alerts & announcements'),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            _chips(const ['All', 'Bus', 'Announcements'], _f, (i) => setState(() => _f = i)),
            const SizedBox(height: 12),
            if (_f != 2)
              LiveRoute(busId: widget.busId, builder: (c, r, l) {
                final stops = r.journey(l.direction);
                final items = <Widget>[];
                if (l.breakdown) {
                  items.add(NotifTile(icon: Icons.build_rounded, color: kRed, title: 'Bus breakdown', subtitle: l.breakdownNote.isEmpty ? 'The bus has reported a breakdown.' : l.breakdownNote, time: 'Now'));
                }
                if (l.running) {
                  final nxt = l.nextIn(r);
                  items.add(NotifTile(
                    icon: Icons.directions_bus_rounded,
                    color: kGreen,
                    title: 'Bus is on the way',
                    subtitle: stops.isEmpty ? 'Trip in progress.' : (nxt < stops.length ? 'Next stop: ${stops[nxt].name}' : 'Arriving at ${stops.last.name}'),
                    time: 'Live',
                  ));
                } else if (l.doneIn(r)) {
                  items.add(const NotifTile(icon: Icons.flag_rounded, color: kBlue, title: 'Trip completed', subtitle: 'The bus has reached its destination.', time: 'Today'));
                }
                if (items.isEmpty) items.add(const Card2(child: Text('No bus alerts right now.', style: TextStyle(color: kMuted))));
                return Column(children: items);
              }),
            if (_f != 1) const AnnouncementList(),
          ]),
        ),
      ]);
}

// ---------------- SETTINGS ----------------
class SettingsScreen extends StatelessWidget {
  final bool isDriver;
  const SettingsScreen({super.key, this.isDriver = false});

  static const _modes = [
    ('Battery saver', 'Updates every ~5 s. Lowest battery use, less precise.'),
    ('Balanced', 'Updates every ~2 s. Good accuracy, moderate battery.'),
    ('High accuracy', 'Updates every second with navigation-grade GPS. Best accuracy.'),
  ];

  @override
  Widget build(BuildContext context) => _page(
        context,
        'Settings',
        'Preferences',
        ValueListenableBuilder<int>(
          valueListenable: AppSettings.rev,
          builder: (c, _, __) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            const SectionLabel('Display'),
            Card2(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('24-hour time', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Example: ${fmtTime(DateTime(2026, 1, 1, 17, 45))}', style: const TextStyle(color: kMuted)),
                value: AppSettings.use24h,
                activeThumbColor: kYellow,
                onChanged: (v) => AppSettings.setUse24h(v),
              ),
            ),
            if (isDriver) ...[
              const SectionLabel('GPS accuracy'),
              for (var i = 2; i >= 0; i--)
                Card2(
                  border: AppSettings.gpsMode == i ? kYellow : null,
                  onTap: () => AppSettings.setGpsMode(i),
                  child: Row(children: [
                    Icon(AppSettings.gpsMode == i ? Icons.radio_button_checked : Icons.radio_button_off, color: AppSettings.gpsMode == i ? kYellow : kMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_modes[i].$1, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(_modes[i].$2, style: const TextStyle(color: kMuted, fontSize: 12.5)),
                      ]),
                    ),
                  ]),
                ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Applies the next time you start a trip. For the most accurate tracking keep "High accuracy" and allow location "all the time".', style: TextStyle(color: kMuted, fontSize: 12)),
              ),
            ],
            const SectionLabel('About'),
            const Card2(
              child: Text('College Bus\nCarmel Polytechnic College, Punnapra', style: TextStyle(color: kMuted, height: 1.5)),
            ),
          ]),
        ),
      );
}
