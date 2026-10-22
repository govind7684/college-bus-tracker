import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'background.dart' show callFleet;
import 'data.dart';
import 'settings.dart';
import 'theme.dart';

// ======================= basic building blocks =======================

class Card2 extends StatelessWidget {
  final Widget child;
  final Color? border;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const Card2({super.key, required this.child, this.border, this.padding = const EdgeInsets.all(14), this.onTap});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: border ?? kLine),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(borderRadius: BorderRadius.circular(22), onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 6),
        child: Row(children: [
          Expanded(child: Text(text, style: serif(19))),
          if (trailing != null) trailing!,
        ]),
      );
}

class StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const StatusChip(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.o(.16), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11.5)),
      );
}

/// Yellow primary button.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final List<Color> colors;
  final Color fg;
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.colors = const [Color(0xFFEDB63F), kYellow],
    this.fg = kOnGold,
  });
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null && !busy ? .5 : 1,
        child: Container(
          height: 54,
          decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(18)),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: busy ? null : onPressed,
              child: Center(
                child: busy
                    ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, color: fg, size: 21), const SizedBox(width: 8)],
                        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
                      ]),
              ),
            ),
          ),
        ),
      );
}

class CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool dot;
  const CircleBtn({super.key, required this.icon, required this.onTap, this.tooltip, this.dot = false});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: Colors.white.o(.10),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 42, height: 42,
              child: Stack(alignment: Alignment.center, children: [
                Icon(icon, size: 21, color: kInk),
                if (dot) Positioned(top: 9, right: 10, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: kYellow, shape: BoxShape.circle))),
              ]),
            ),
          ),
        ),
      );
}

/// Serif page title with optional back button / actions (Routes, Profile, Settings...).
class ScreenTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool back;
  final List<Widget> actions;
  const ScreenTitle({super.key, required this.title, this.subtitle, this.back = false, this.actions = const []});
  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
          child: Row(children: [
            if (back) ...[CircleBtn(icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: () => Navigator.maybePop(context)), const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(30)),
                if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: const TextStyle(color: kMuted, fontSize: 13))),
              ]),
            ),
            ...actions,
          ]),
        ),
      );
}

/// The bus's photo at its own aspect ratio (whole bus, nothing cropped). Bus 1 and Bus 2 have their own photo.
class BusPhoto extends StatelessWidget {
  final String busId;
  final int cacheWidth;
  const BusPhoto({super.key, required this.busId, this.cacheWidth = 1000});
  @override
  Widget build(BuildContext context) {
    final b = busInfo(busId);
    return AspectRatio(aspectRatio: b.aspect, child: Image.asset(b.asset, fit: BoxFit.cover, cacheWidth: cacheWidth));
  }
}

/// Bus photo header. The photo is shown whole (its own aspect ratio, nothing cropped) and the title sits
/// BELOW it, so no text or button ever covers the bus. The back button lives in its own row above the photo.
class HeroHeader extends StatelessWidget {
  final String title, subtitle;
  final String busId;
  final VoidCallback? onBack;
  const HeroHeader({super.key, required this.title, required this.subtitle, this.busId = 'bus1', this.onBack});
  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (onBack != null) ...[
              CircleBtn(icon: Icons.arrow_back_rounded, onTap: onBack!, tooltip: 'Back'),
              const SizedBox(height: 10),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BusPhoto(busId: busId),
            ),
            const SizedBox(height: 14),
            Text(title, style: serif(30, height: 1.1)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(letterSpacing: 2.2, fontSize: 12, fontWeight: FontWeight.w600, color: kMuted)),
          ]),
        ),
      );
}

class NavItem {
  final IconData icon, active;
  final String label;
  const NavItem(this.icon, this.active, this.label);
}

/// Bottom navigation bar: gold line above the active item.
class GlassNav extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const GlassNav({super.key, required this.items, required this.index, required this.onTap});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kBg2,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(top: BorderSide(color: Colors.white.o(.07))),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkResponse(
                    onTap: () => onTap(i),
                    radius: 34,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(width: 26, height: 2.5, margin: const EdgeInsets.only(bottom: 7), color: i == index ? kYellow : Colors.transparent),
                      Icon(i == index ? items[i].active : items[i].icon, color: i == index ? kInk : kMuted, size: 23),
                      const SizedBox(height: 2),
                      Text(items[i].label, style: TextStyle(fontSize: 11, fontWeight: i == index ? FontWeight.w800 : FontWeight.w500, color: i == index ? kInk : kMuted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      );
}

// ======================= live data =======================

/// Subscribes ONCE per bus (streams are created in initState) and hands that bus's route + live data to [builder].
class LiveRoute extends StatefulWidget {
  final String busId;
  final Widget Function(BuildContext, RouteData, Live) builder;
  const LiveRoute({super.key, required this.busId, required this.builder});
  @override
  State<LiveRoute> createState() => _LiveRouteState();
}

class _LiveRouteState extends State<LiveRoute> with WidgetsBindingObserver {
  late Stream<RouteData> _rs = Repo.routeStream(widget.busId);
  late Stream<Live> _ls = Repo.liveStream(widget.busId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(LiveRoute old) {
    super.didUpdateWidget(old);
    if (old.busId != widget.busId) {
      _rs = Repo.routeStream(widget.busId);
      _ls = Repo.liveStream(widget.busId);
    }
  }

  /// Back from the background: recompute passed stops, distances and ETA from the bus position straight away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<RouteData>(
        stream: _rs,
        builder: (c, rs) => StreamBuilder<Live>(
          stream: _ls,
          builder: (c, ls) {
            if (rs.hasError || ls.hasError) {
              return Card2(child: Text('Could not load live data.\n${rs.error ?? ls.error}', style: const TextStyle(color: kRed, fontSize: 12)));
            }
            if (!rs.hasData || !ls.hasData) {
              return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 3, color: kYellow)));
            }
            return widget.builder(c, rs.data!, ls.data!);
          },
        ),
      );
}

/// Distances are always shown in km (one decimal).
String kmText(double m) => m < 100 ? '<0.1 km' : '${(m / 1000).toStringAsFixed(1)} km';

/// "8 min" / "1 hr 5 min" from a duration in minutes.
String minsText(int mins) => mins < 1 ? 'Arriving' : (mins < 60 ? '$mins min' : '${mins ~/ 60} hr ${mins % 60} min');

/// Bus 1 / Bus 2 selector. [mine] marks the bus the user is assigned to.
class BusSwitcher extends StatelessWidget {
  final String value;
  final String? mine;
  final ValueChanged<String> onChanged;
  const BusSwitcher({super.key, required this.value, required this.onChanged, this.mine});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            backgroundColor: kCard,
            selectedBackgroundColor: kYellow,
            selectedForegroundColor: kOnGold,
            visualDensity: VisualDensity.compact,
          ),
          segments: [
            for (final b in kBuses)
              ButtonSegment<String>(
                value: b.id,
                icon: const Icon(Icons.directions_bus_rounded, size: 16),
                label: Text(mine == b.id ? '${b.label} (mine)' : b.label),
              ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      );
}

// ======================= tracker (status + vertical stop timeline) =======================

/// Live status card + slim vertical stop timeline for ONE bus. Read-only; no map.
/// [afterSummary] is placed between the status card and the timeline (the student's "Today's ride" card).
/// [detailed] adds covered / average / top speed (driver live view).
class TrackerBody extends StatelessWidget {
  final String busId;
  final RouteData route;
  final Live live;
  final String? myStop;
  final void Function(String stopName)? onStopTap;
  final bool detailed;
  final bool photo; // small bus photo in the status card (off where a full hero banner is already shown)
  final Widget? afterSummary;
  const TrackerBody({
    super.key,
    required this.busId,
    required this.route,
    required this.live,
    this.myStop,
    this.onStopTap,
    this.detailed = false,
    this.photo = true,
    this.afterSummary,
  });

  @override
  Widget build(BuildContext context) {
    final stops = route.journey(live.direction);
    if (stops.isEmpty) {
      return Column(children: [
        if (afterSummary != null) afterSummary!,
        const Card2(child: Text('Route not configured yet. The driver needs to add the stops.', style: TextStyle(color: kMuted))),
      ]);
    }
    final nxt = live.nextIn(route); // every stop behind the bus is "passed"
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _summary(stops, nxt),
      if (live.breakdown)
        Card2(
          border: kRed,
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: kRed),
            const SizedBox(width: 10),
            Expanded(child: Text('Bus breakdown reported. ${live.breakdownNote}', style: const TextStyle(fontSize: 14))),
          ]),
        ),
      if (afterSummary != null) afterSummary!,
      _timeline(stops, nxt),
    ]);
  }

  Widget _stat(IconData icon, String value, String label, {int flex = 1}) => Expanded(
        flex: flex,
        child: Column(children: [
          Icon(icon, color: kYellow, size: 18),
          const SizedBox(height: 4),
          Text(value, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.15)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: kMuted, fontSize: 11), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      );

  Widget _summary(List<Stop> stops, int nxt) {
    final l = live, r = route;
    final n = stops.length;
    final last = n - 1;
    final run = l.running;
    final done = l.doneIn(r);
    final hasNext = run && nxt < n;
    final dNext = hasNext ? l.remaining(r, nxt) : null;
    final etaNext = hasNext ? l.eta(r, nxt) : null;
    final dist = l.remaining(r, last);
    final etaEnd = l.eta(r, last);
    final minsEnd = etaEnd?.difference(DateTime.now()).inMinutes;
    final badge = l.breakdown ? 'Breakdown' : run ? 'On route' : (done ? 'Completed' : 'Not running');
    final badgeColor = l.breakdown ? kRed : (run || done) ? kGreen : kMuted;
    final heading = l.headingTo(r);
    final dirLabel = l.direction == 'morning' ? 'Morning journey' : 'Evening return';

    return Card2(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (photo) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 92, child: BusPhoto(busId: busId, cacheWidth: 300)),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.plateFor(busId), maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(18)),
              const SizedBox(height: 2),
              Text('${busInfo(busId).label} • $dirLabel', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12)),
              const SizedBox(height: 6),
              StatusChip(badge, badgeColor),
            ]),
          ),
          if (busInfo(busId).phone.isNotEmpty)
            IconButton(
              tooltip: 'Call ${busInfo(busId).label} (${busInfo(busId).phoneText})',
              onPressed: () => callFleet(busId),
              icon: const Icon(Icons.call_rounded, color: kGreen),
            ),
        ]),
        const SizedBox(height: 12),
        Text('${stops.first.name} → ${stops[last].name}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12.5)),
        if (heading != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kYellow, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        if (run && nxt > 0 && nxt < n)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Between ${stops[nxt - 1].name} and ${stops[nxt].name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12)),
          ),
        if (done)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Reached destination', style: TextStyle(color: kGreen, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        if (l.stale)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.gps_off, color: kAmber, size: 15),
              SizedBox(width: 6),
              Expanded(child: Text('GPS signal lost – showing last known position', style: TextStyle(color: kAmber, fontSize: 12))),
            ]),
          ),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _stat(Icons.speed, run ? '${l.speed.round()} km/h' : '0 km/h', 'Speed'),
          _stat(Icons.my_location, hasNext ? stops[nxt].name : '—', dNext == null ? 'Next stop' : 'Next • ${kmText(dNext)}', flex: 2),
          _stat(Icons.schedule, etaNext == null ? '--' : fmtTime(etaNext), 'ETA'),
        ]),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: (nxt / n).clamp(0.0, 1.0).toDouble(), minHeight: 3, backgroundColor: kLine, valueColor: const AlwaysStoppedAnimation(kYellow)),
        ),
        const SizedBox(height: 6),
        Text(nxt == 0 ? '$n stops' : 'Passed $nxt of $n stops • last: ${stops[nxt - 1].name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12)),
        if (run)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '${dist == null ? '--' : kmText(dist)} to ${stops[last].name}${etaEnd == null ? '' : ' • arrives ${fmtTime(etaEnd)}'}${minsEnd == null ? '' : ' (${minsText(minsEnd)})'}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
          ),
        if (detailed) ...[
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _stat(Icons.route, dist == null ? '--' : kmText(dist), 'Distance left'),
            _stat(Icons.flag_outlined, etaEnd == null ? '--' : fmtTime(etaEnd), 'Arrival'),
            _stat(Icons.timer_outlined, done ? 'Done' : (minsEnd == null ? '--' : minsText(minsEnd)), 'Trip time'),
          ]),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _stat(Icons.straighten, '${l.covered.toStringAsFixed(1)} km', 'Covered'),
            _stat(Icons.av_timer, l.avg <= 0 ? '--' : '${l.avg.round()} km/h', 'Avg (moving)'),
            _stat(Icons.bolt, '${l.top.round()} km/h', 'Top speed'),
          ]),
        ],
      ]),
    );
  }

  Widget _timeline(List<Stop> stops, int nxt) {
    final plan = route.plan(live.direction);
    return Card2(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(child: Text(live.direction == 'morning' ? 'Morning stops' : 'Return stops', style: serif(16))),
            Text('${stops.length} stops • ${(plan.totalMeters / 1000).toStringAsFixed(1)} km', style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        for (var i = 0; i < stops.length; i++) _row(i, stops, nxt),
      ]),
    );
  }

  /// One timeline row: slim marker (check = passed, bus = next, hollow dot = upcoming) + 1.5 px connector.
  Widget _row(int i, List<Stop> stops, int nxt) {
    final l = live;
    final n = stops.length;
    final passed = i < nxt;
    final isNext = l.running && i == nxt && nxt < n;
    final mine = myStop != null && stops[i].name == myStop;
    final dist = l.remaining(route, i);
    final eta = l.eta(route, i);
    final local = stops[i].localName;

    String sub;
    if (i == 0) {
      sub = 'Boarding point';
    } else if (i == n - 1) {
      sub = 'Destination';
    } else if (mine) {
      sub = 'Your stop';
    } else {
      sub = local.isNotEmpty && local != stops[i].name ? local : '';
    }
    if (dist != null && !passed && (mine || isNext)) sub = sub.isEmpty ? '${kmText(dist)} away' : '$sub • ${kmText(dist)} away';

    Widget right;
    if (passed) {
      right = Text(i == n - 1 ? 'Reached' : 'Passed', style: const TextStyle(color: kGreen, fontWeight: FontWeight.w700, fontSize: 12));
    } else if (eta != null) {
      right = Text(fmtTime(eta), style: const TextStyle(color: kMuted, fontSize: 12.5));
    } else {
      right = const SizedBox();
    }

    final Widget marker;
    if (isNext) {
      marker = Container(
        width: 22, height: 22,
        decoration: BoxDecoration(color: kYellow, shape: BoxShape.circle, boxShadow: [BoxShadow(color: kYellow.o(.35), blurRadius: 6)]),
        child: const Icon(Icons.directions_bus_rounded, size: 13, color: kOnGold),
      );
    } else if (passed) {
      marker = Container(
        width: 14, height: 14,
        decoration: const BoxDecoration(color: kGreen, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 10, color: kOnGold),
      );
    } else {
      marker = Container(
        width: 10, height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF8C8A80), width: 1.5)),
      );
    }

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 24,
          child: Column(children: [
            Padding(padding: const EdgeInsets.only(top: 6), child: SizedBox(height: 22, child: Center(child: marker))),
            if (i != n - 1)
              Expanded(child: Center(child: Container(width: 1.5, color: passed ? kGreen.o(.7) : const Color(0xFF4F4D44)))),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: mine ? kYellow.o(.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onStopTap == null ? null : () => onStopTap!(stops[i].name),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(stops[i].name, style: TextStyle(fontSize: 14.5, fontWeight: mine || isNext ? FontWeight.w800 : FontWeight.w600, color: passed ? kInk.o(.7) : kInk)),
                        if (sub.isNotEmpty) Text(sub, style: TextStyle(color: mine ? kYellow : kMuted, fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    right,
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ======================= notifications =======================

class NotifTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle, time;
  const NotifTile({super.key, required this.icon, required this.color, required this.title, required this.subtitle, required this.time});
  @override
  Widget build(BuildContext context) => Card2(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.o(.18)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
                Text(time, style: const TextStyle(color: kMuted, fontSize: 11.5)),
              ]),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 13, height: 1.3)),
            ]),
          ),
        ]),
      );
}

class AnnouncementList extends StatefulWidget {
  const AnnouncementList({super.key});
  @override
  State<AnnouncementList> createState() => _AnnouncementListState();
}

class _AnnouncementListState extends State<AnnouncementList> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _s = Repo.announcements();
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _s,
        builder: (c, s) {
          if (s.hasError) return Card2(child: Text('Could not load announcements.\n${s.error}', style: const TextStyle(color: kRed, fontSize: 12)));
          final docs = s.data?.docs ?? [];
          if (docs.isEmpty) return const Card2(child: Text('No announcements yet.', style: TextStyle(color: kMuted)));
          return Column(children: [
            for (final d in docs)
              NotifTile(
                icon: Icons.campaign_rounded,
                color: kAmber,
                title: 'College notice',
                subtitle: (d.data()['text'] ?? '').toString(),
                time: d.data()['createdAt'] is Timestamp ? fmtTime((d.data()['createdAt'] as Timestamp).toDate()) : '',
              ),
          ]);
        },
      );
}
