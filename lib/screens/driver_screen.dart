import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../background.dart';
import '../data.dart';
import '../settings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'info_screens.dart';
import 'map_editor.dart';
import 'student_screen.dart' show confirmLogout;
import 'tracking_screen.dart';

class DriverScreen extends StatefulWidget {
  final String busId; // the bus this driver runs (app2_users/<uid>.bus, default Bus 1)
  const DriverScreen({super.key, required this.busId});
  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Repo.resumeIfNeeded(widget.busId); // keep sharing location if the app was reopened during a trip
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // app came back: re-take the GPS fix now and re-evaluate which stops are behind the bus
      Repo.resumeIfNeeded(widget.busId);
      Repo.refreshNow();
    }
  }

  Future<void> _onBack() async {
    if (_tab != 0) {
      setState(() => _tab = 0); // back from any panel -> home panel
      return;
    }
    await goToPhoneHome(); // stays logged in; GPS sharing keeps running
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: AppSettings.rev,
        builder: (context, _, __) => PopScope(
          canPop: kIsWeb,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _onBack();
          },
          child: Scaffold(
            body: IndexedStack(index: _tab, children: [
              _HomeTab(busId: widget.busId, onLogout: () => confirmLogout(context, before: () async {
                    if (Repo.isTracking) await Repo.endTrip();
                  })),
              _RegisterTab(busId: widget.busId),
              _RouteTab(busId: widget.busId),
              const _UpdatesTab(),
            ]),
            bottomNavigationBar: GlassNav(
              index: _tab,
              onTap: (i) => setState(() => _tab = i),
              items: const [
                NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
                NavItem(Icons.fact_check_outlined, Icons.fact_check, 'Register'),
                NavItem(Icons.alt_route, Icons.alt_route, 'Route'),
                NavItem(Icons.campaign_outlined, Icons.campaign, 'Updates'),
              ],
            ),
          ),
        ),
      );
}

// ---------- attendance rows shared by Home (next stop) and Register ----------
class _Row {
  final String name, stop;
  final String status; // 'present' | 'skip' | 'none' | 'moved' (a student of THIS bus who switched to the other bus)
  final dynamic time;
  final String? from; // contingency rider: the bus the student normally belongs to
  final String? to; // 'moved': the bus the student switched to
  _Row(this.name, this.stop, this.status, this.time, {this.from, this.to});
  bool get contingency => from != null;
}

/// Register rows for one student on bus [busId] and journey [j]. [profile] is the student's record (or the
/// attendance doc when the student record is missing); [mark] is today's attendance doc, if any.
List<_Row> _rowsFor(Map<String, dynamic> profile, Map<String, dynamic>? mark, String j, String busId) {
  final assigned = busOf(profile);
  final name = (profile['name'] ?? '').toString();
  if (mark == null) {
    return assigned == busId ? [_Row(name, (profile['stop'] ?? '').toString(), 'none', null)] : <_Row>[];
  }
  final status = mark['${j}Status'] as String;
  final ride = (mark['${j}Bus'] ?? assigned).toString();
  final stop = (mark['${j}Stop'] ?? mark['stop'] ?? profile['stop'] ?? '').toString();
  final time = mark['${j}Time'];
  if (status == 'present' && ride != assigned) {
    if (ride == busId) return [_Row(name, stop, 'present', time, from: assigned)]; // contingency rider joining this bus
    if (assigned == busId) return [_Row(name, stop, 'moved', time, to: ride)]; // our student left for the other bus
    return <_Row>[];
  }
  return assigned == busId ? [_Row(name, stop, status, time)] : <_Row>[];
}

List<_Row> _buildRows(QuerySnapshot<Map<String, dynamic>>? att, QuerySnapshot<Map<String, dynamic>>? st, String j, String busId) {
  final marks = <String, Map<String, dynamic>>{};
  for (final d in att?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
    final m = d.data();
    final v = m['${j}Status'];
    if (v == 'present' || v == 'skip') marks[(m['uid'] ?? d.id).toString()] = m;
  }
  final rows = <_Row>[];
  final seen = <String>{};
  for (final d in st?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]) {
    final m = d.data();
    final uid = (m['uid'] ?? d.id).toString();
    seen.add(uid);
    rows.addAll(_rowsFor(m, marks[uid], j, busId));
  }
  marks.forEach((uid, m) {
    if (!seen.contains(uid)) rows.addAll(_rowsFor(m, m, j, busId));
  });
  return rows;
}

// ---------------- HOME PANEL (trip control) ----------------
class _HomeTab extends StatefulWidget {
  final String busId;
  final VoidCallback onLogout;
  const _HomeTab({required this.busId, required this.onLogout});
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  String? _manual; // null = automatic by time of day
  String? _err;
  bool _busy = false;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _me = db.doc('app2_users/${Repo.uid}').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _att = Repo.todayRegister();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _students = Repo.students();

  Future<void> _toggle(Live live, String dir) async {
    setState(() { _busy = true; _err = null; });
    try {
      if (live.tripActive) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('End trip?'),
            content: const Text('Students will stop seeing live updates.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End trip', style: TextStyle(color: kRed))),
            ],
          ),
        );
        if (ok == true) await Repo.endTrip();
      } else {
        final e = await Repo.startTrip(widget.busId, dir);
        _err = e;
        if (e == null) HapticFeedback.mediumImpact();
      }
    } catch (e) {
      _err = 'Failed: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => LiveRoute(
        busId: widget.busId,
        builder: (c, route, live) {
          final dir = live.tripActive ? live.rawDirection : (_manual ?? autoDirection());
          final stops = route.journey(dir);
          final nxt = live.nextIn(route);
          final navTo = live.navStop(route); // real next stop while running, else the first stop
          final active = live.tripActive;
          final h = DateTime.now().hour;
          return SafeArea(
            bottom: false,
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _me,
                    builder: (c, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(h < 12 ? 'Good morning,' : (h < 17 ? 'Good afternoon,' : 'Good evening,'), style: serif(22, w: FontWeight.w400, color: kInk.o(.9))),
                      Text((s.data?.data()?['name'] ?? 'Driver').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(38, height: 1.1)),
                      const SizedBox(height: 6),
                      StatusChip('DRIVER • ${busInfo(widget.busId).label.toUpperCase()}', kYellow),
                    ]),
                  ),
                ),
                CircleBtn(icon: Icons.settings_outlined, tooltip: 'Settings', onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen(isDriver: true)))),
                const SizedBox(width: 8),
                CircleBtn(icon: Icons.logout, tooltip: 'Log out', onTap: widget.onLogout),
              ]),
              const SizedBox(height: 18),
              // trip card with the bus photo
              Container(
                decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(26), border: Border.all(color: kLine)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Column(children: [
                    // whole bus photo (its own aspect ratio, nothing cropped); status chips sit BELOW it
                    BusPhoto(busId: widget.busId, cacheWidth: 900),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(children: [
                        StatusChip(active ? 'Trip running' : 'Ready', active ? kGreen : kBlue),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: kBg2, borderRadius: BorderRadius.circular(20)),
                          child: Text('${live.speed.round()} km/h', style: const TextStyle(fontWeight: FontWeight.w800, color: kYellow)),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(route.plateFor(widget.busId), style: serif(22))),
                          Text(dir == 'morning' ? 'Morning' : 'Evening', style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          stops.length < 2 ? 'Add your stops in the Route tab first' : '${stops.first.name} → ${stops.last.name}',
                          style: TextStyle(color: stops.length < 2 ? kAmber : kMuted, fontSize: 13.5),
                        ),
                        const SizedBox(height: 14),
                        GradientButton(
                          label: active ? 'End trip' : 'Start ${dir == 'morning' ? 'morning' : 'evening'} trip',
                          icon: active ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                          busy: _busy,
                          colors: active ? const [Color(0xFFF08A82), Color(0xFFD9534B)] : const [Color(0xFFEDB63F), kYellow],
                          fg: active ? Colors.white : kOnGold,
                          onPressed: (!active && stops.length < 2) ? null : () => _toggle(live, dir),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: kRed))),
              if (!active) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(backgroundColor: kCard, selectedBackgroundColor: kYellow, selectedForegroundColor: kOnGold),
                    segments: [
                      ButtonSegment(value: 'auto', label: Text('Auto (${autoDirection() == 'morning' ? 'AM' : 'PM'})')),
                      const ButtonSegment(value: 'morning', label: Text('Morning')),
                      const ButtonSegment(value: 'evening', label: Text('Evening')),
                    ],
                    selected: {_manual ?? 'auto'},
                    onSelectionChanged: (s) => setState(() => _manual = s.first == 'auto' ? null : s.first),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _waitingCard(stops, nxt, dir, live),
              _gpsCard(live),
              Row(children: [
                Expanded(child: _tile(Icons.directions_bus_outlined, 'Live view', () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => TrackingScreen(busId: widget.busId))), color: kBlue)),
                const SizedBox(width: 10),
                Expanded(child: _tile(Icons.navigation_rounded, 'Navigate', navTo == null ? null : () => _navigate(navTo), color: kGreen)),
                const SizedBox(width: 10),
                Expanded(
                  child: _tile(Icons.build_circle_outlined, live.breakdown ? 'Clear' : 'Breakdown',
                      () => live.breakdown ? Repo.reportBreakdown(widget.busId, false, '') : _breakdownDialog(),
                      color: kRed),
                ),
              ]),
              if (!kIsWeb) ...[const SizedBox(height: 12), _bgTip(live)],
            ]),
          );
        },
      );

  /// Who is waiting at the next stop / who will not be on the bus today.
  Widget _waitingCard(List<Stop> stops, int nxt, String dir, Live live) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _att,
        builder: (c, att) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _students,
          builder: (c, st) {
            final rows = _buildRows(att.data, st.data, dir, widget.busId);
            final riding = rows.where((r) => r.status == 'present').length;
            final skipping = rows.where((r) => r.status == 'skip').length;
            final none = rows.where((r) => r.status == 'none').length;
            final hasNext = live.running && nxt < stops.length;
            final here = hasNext ? rows.where((r) => r.stop == stops[nxt].name).toList() : <_Row>[];
            final hereRiding = here.where((r) => r.status != 'skip' && r.status != 'moved').length;
            final hereSkip = here.where((r) => r.status == 'skip').length;
            return Card2(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.groups_2_outlined, color: kYellow),
                  const SizedBox(width: 10),
                  Expanded(child: Text(hasNext ? 'Next stop: ${stops[nxt].name}' : "Today's students", style: serif(17))),
                ]),
                const SizedBox(height: 8),
                if (hasNext)
                  Text('${here.isEmpty ? 'No students' : '$hereRiding waiting'}${hereSkip > 0 ? ' • $hereSkip skipping' : ''} at this stop', style: const TextStyle(color: kInk, fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  StatusChip('$riding riding', kGreen),
                  StatusChip('$skipping skipping', kAmber),
                  StatusChip('$none not marked', kMuted),
                ]),
              ]),
            );
          },
        ),
      );

  Widget _tile(IconData icon, String label, VoidCallback? onTap, {Color color = kBlue}) => Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Container(
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: SizedBox(
                height: 84,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: color, size: 26),
                  const SizedBox(height: 6),
                  Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _bgTip(Live live) => Card2(
        onTap: () => Geolocator.openAppSettings(),
        child: Row(children: [
          Icon(live.tripActive ? Icons.check_circle_outline : Icons.info_outline, color: live.tripActive ? kGreen : kAmber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              live.tripActive
                  ? 'Sharing continues in the background. You can press Back or switch apps.'
                  : 'For tracking with the screen off: set Location to "Allow all the time" and turn off battery restrictions. Tap to open settings.',
              style: const TextStyle(fontSize: 12.5, color: kMuted),
            ),
          ),
        ]),
      );

  Widget _gpsCard(Live l) {
    final age = l.updated == null ? null : DateTime.now().difference(l.updated!).inSeconds;
    Widget row(String k, String v, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Text(k, style: const TextStyle(color: kMuted)),
            const Spacer(),
            Text(v, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          ]),
        );
    final active = l.tripActive && age != null && age < 120;
    const modes = ['Battery saver', 'Balanced', 'High accuracy'];
    return Card2(
      child: Column(children: [
        Row(children: [
          Icon(Icons.my_location, color: active ? kGreen : kMuted, size: 20),
          const SizedBox(width: 8),
          Text('GPS status', style: serif(17)),
        ]),
        const Divider(height: 18),
        row('Status', l.tripActive ? (active ? 'Sharing location' : 'Waiting for GPS…') : 'Off', color: active ? kGreen : null),
        row('Mode', modes[AppSettings.gpsMode]),
        row('Location', l.hasFix ? '${l.lat.toStringAsFixed(5)}, ${l.lng.toStringAsFixed(5)}' : '--'),
        row('Accuracy', l.accuracy == 0 ? '--' : '±${l.accuracy.toStringAsFixed(0)} m'),
        row('Last update', l.updated == null ? '--' : fmtTime(l.updated!)),
        if (l.tripActive)
          row('GPS fixes', '${l.fixes} used, ${l.fixesRejected} rejected', color: l.fixes == 0 ? kRed : null),
      ]),
    );
  }

  /// Google Maps turn-by-turn navigation to [s] (native app first, web link if the app is missing).
  Future<void> _navigate(Stop s) async {
    final msg = ScaffoldMessenger.of(context);
    final ok = await openTurnByTurn(s.lat, s.lng);
    if (!ok) msg.showSnackBar(const SnackBar(content: Text('Could not open Google Maps.')));
  }

  Future<void> _breakdownDialog() async {
    final note = await showDialog<String>(context: context, builder: (_) => const _BreakdownDialog());
    if (note != null) await Repo.reportBreakdown(widget.busId, true, note);
  }
}

// ---------------- LIVE STUDENT LOG REGISTER (current journey only) ----------------
class _RegisterTab extends StatefulWidget {
  final String busId;
  const _RegisterTab({required this.busId});
  @override
  State<_RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends State<_RegisterTab> {
  late final Stream<Live> _live = Repo.liveStream(widget.busId);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _att = Repo.todayRegister();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _students = Repo.students();

  @override
  Widget build(BuildContext context) => StreamBuilder<Live>(
        stream: _live,
        builder: (c, ls) {
          final live = ls.data;
          final j = (live != null && live.running) ? live.direction : autoDirection();
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _att,
            builder: (c, att) {
              if (att.hasError) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Register unavailable: ${att.error}\n\nFix: publish firestore.rules in Firebase and make sure the document app2_users/<your driver UID> exists.',
                      style: const TextStyle(color: kRed),
                    ),
                  ),
                );
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _students,
                builder: (c, st) {
                  final rows = _buildRows(att.data, st.data, j, widget.busId);
                  int rank(_Row r) => r.status == 'present' ? 0 : (r.status == 'skip' ? 1 : (r.status == 'moved' ? 2 : 3));
                  int byName(_Row a, _Row b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
                  final contingency = rows.where((r) => r.contingency).toList()..sort(byName);
                  final roster = rows.where((r) => !r.contingency).toList()
                    ..sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : byName(a, b));
                  final riding = rows.where((r) => r.status == 'present').length;
                  final skipping = rows.where((r) => r.status == 'skip').length;
                  final notMarked = rows.where((r) => r.status == 'none').length;
                  return Column(children: [
                    ScreenTitle(
                      title: 'Student log',
                      subtitle: '${busInfo(widget.busId).label} • ${j == 'morning' ? 'Morning' : 'Evening'} • ${todayKey()} • live',
                    ),
                    Expanded(
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 20), children: [
                        Row(children: [
                          Expanded(child: _count('$riding', 'Riding', kGreen)),
                          const SizedBox(width: 10),
                          Expanded(child: _count('$skipping', 'Skipping', kAmber)),
                          const SizedBox(width: 10),
                          Expanded(child: _count('$notMarked', 'Not marked', kMuted)),
                        ]),
                        const SizedBox(height: 14),
                        if (contingency.isNotEmpty) ...[
                          SectionLabel('Special contingency log', trailing: StatusChip('${contingency.length}', kBlue)),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Text('Students whose own bus broke down or was missed and who switched to this bus for this trip.', style: TextStyle(color: kMuted, fontSize: 12.5)),
                          ),
                          for (final r in contingency) _tile(r),
                          const SectionLabel('Roster'),
                        ],
                        if (roster.isEmpty) const Card2(child: Text('No students yet.', style: TextStyle(color: kMuted))),
                        for (final r in roster) _tile(r),
                      ]),
                    ),
                  ]);
                },
              );
            },
          );
        },
      );

  Widget _count(String n, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kLine)),
        child: Column(children: [
          Text(n, style: serif(26, color: color)),
          Text(label, style: const TextStyle(color: kMuted, fontSize: 12)),
        ]),
      );

  Widget _tile(_Row r) {
    final present = r.status == 'present', skip = r.status == 'skip', moved = r.status == 'moved';
    final color = r.contingency || moved ? kBlue : (present ? kGreen : (skip ? kAmber : kMuted));
    final label = r.contingency
        ? 'Emergency switch'
        : (moved ? 'Moved to ${busInfo(r.to ?? 'bus1').label}' : (present ? 'Riding' : (skip ? 'Skipping today' : 'Not marked')));
    final icon = r.contingency || moved ? Icons.swap_horiz_rounded : (present ? Icons.check : (skip ? Icons.do_not_disturb_on_outlined : Icons.remove));
    final stop = r.stop.isEmpty ? 'No stop selected' : r.stop;
    return Card2(
      border: r.contingency ? kBlue.o(.6) : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        CircleAvatar(radius: 18, backgroundColor: color.o(.16), child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.name.isEmpty ? 'Student' : r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(r.contingency ? '$stop • from ${busInfo(r.from!).label}' : stop, style: const TextStyle(color: kMuted, fontSize: 12)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
          if (r.time is Timestamp) Text(fmtTime((r.time as Timestamp).toDate()), style: const TextStyle(color: kMuted, fontSize: 11.5)),
        ]),
      ]),
    );
  }
}

// ---------------- ROUTE EDITOR (forward + return) ----------------
class _RouteTab extends StatefulWidget {
  final String busId;
  const _RouteTab({required this.busId});
  @override
  State<_RouteTab> createState() => _RouteTabState();
}

class _RouteTabState extends State<_RouteTab> {
  List<Stop> _fwd = [], _ret = [];
  List<double> _fwdGeo = [], _retGeo = [];
  bool _retSame = true, _loaded = false, _busy = false;
  int _dir = 0; // 0 = forward (morning), 1 = return (evening)
  String? _msg;

  @override
  void initState() {
    super.initState();
    Repo.routeStream(widget.busId).first.then((r) {
      if (!mounted) return;
      setState(() {
        _fwd = [...r.stops];
        _fwdGeo = r.geo;
        _ret = [...r.retStops];
        _retGeo = r.retGeo;
        _retSame = r.retSame;
        _loaded = true;
      });
    }).catchError((e) {
      if (mounted) setState(() { _loaded = true; _msg = 'Could not load route: $e'; });
    });
  }

  bool get _mirror => _dir == 1 && _retSame;
  List<Stop> get _list => _dir == 0 ? _fwd : _ret;

  /// " • 1.8 km • 4 min" – road distance and driving time from the previous stop.
  String _leg(Stop s) => s.distFromPrev <= 0
      ? ''
      : ' • ${(s.distFromPrev / 1000).toStringAsFixed(1)} km • ${durText(s.durFromPrev > 0 ? s.durFromPrev : s.distFromPrev / kDefaultMps)}';

  String _total(List<Stop> l) {
    final m = l.fold(0.0, (a, s) => a + s.distFromPrev);
    if (l.length < 2 || m <= 0) return '${l.length} stops';
    final t = l.fold(0.0, (a, s) => a + s.durFromPrev);
    return '${l.length} stops • ${(m / 1000).toStringAsFixed(1)} km • ~${durText(t > 0 ? t : m / kDefaultMps)}';
  }

  Future<void> _editOnMap() async {
    final res = await Navigator.push<MapEditResult>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapEditorScreen(
          title: _dir == 0 ? 'Forward route' : 'Return route',
          stops: List.of(_list),
          geometry: _dir == 0 ? _fwdGeo : _retGeo,
          refGeometry: _dir == 0 ? (_retSame ? const [] : _retGeo) : _fwdGeo,
        ),
      ),
    );
    if (res == null || !mounted) return;
    setState(() {
      if (_dir == 0) { _fwd = res.stops; _fwdGeo = res.geo; } else { _ret = res.stops; _retGeo = res.geo; }
      _msg = 'Changes kept. Press "Save route" to publish them.';
    });
  }

  Future<void> _save() async {
    setState(() { _busy = true; _msg = null; });
    var note = 'Saved.';
    // Snap every stop to the road (OSRM), route through them in sequence order, and write the
    // sequence number, stop-to-stop distance and driving time back onto each stop.
    Future<(List<Stop>, List<double>)> prep(List<Stop> stops) async {
      try {
        // directional snapping onto the main road + route + automatic detour repair
        final (snapped, r) = await Geo.plan(stops);
        final warn = Geo.detourNote(snapped, r);
        if (warn != null) note = 'Saved. Check: $warn';
        return (withLegs(snapped, r.legs, r.durations), r.geo);
      } catch (_) {
        note = 'Saved, but road routing failed (no internet?) – straight-line estimates will be used.';
        final legs = straightLegs(stops);
        return (withLegs(stops, legs, estDurations(legs)), <double>[]);
      }
    }

    try {
      final f = await prep(_fwd);
      var rs = <Stop>[];
      var rg = <double>[];
      if (!_retSame && _ret.length >= 2) {
        final r = await prep(_ret);
        rs = r.$1;
        rg = r.$2;
      }
      final sameNow = _retSame || _ret.length < 2;
      await Repo.saveRoute(busId: widget.busId, fwd: f.$1, fwdGeo: f.$2, retSame: sameNow, ret: rs, retGeo: rg);
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          _fwd = f.$1; _fwdGeo = f.$2;
          if (!sameNow) { _ret = rs; _retGeo = rg; }
        });
      }
      if (note == 'Saved.') note = 'Saved ${_fwd.length} forward stops${sameNow ? '' : ' and ${_ret.length} return stops'} with road distances and times.';
    } catch (e) {
      note = 'Could not save: $e';
    }
    if (mounted) setState(() { _busy = false; _msg = note; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final shown = _mirror ? _fwd.reversed.toList() : _list;
    return Column(children: [
      ScreenTitle(title: 'Route stops', subtitle: '${busInfo(widget.busId).label} • forward and return journeys'),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(backgroundColor: kCard, selectedBackgroundColor: kYellow, selectedForegroundColor: kOnGold),
              segments: const [
                ButtonSegment(value: 0, label: Text('Forward (morning)'), icon: Icon(Icons.arrow_forward, size: 16)),
                ButtonSegment(value: 1, label: Text('Return (evening)'), icon: Icon(Icons.arrow_back, size: 16)),
              ],
              selected: {_dir},
              onSelectionChanged: (s) => setState(() => _dir = s.first),
            ),
          ),
          if (_dir == 1)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Same stops as forward, in reverse', style: TextStyle(fontSize: 14)),
              value: _retSame,
              activeThumbColor: kYellow,
              onChanged: (v) => setState(() {
                _retSame = v;
                if (!v && _ret.isEmpty) {
                  _ret = _fwd.reversed.map((s) => s.copyWith(distFromPrev: 0)).toList();
                  _retGeo = reversePairs(_fwdGeo);
                }
              }),
            ),
          Text(
            _mirror ? 'The return trip uses the forward stops backwards. Switch off to give it its own stops.' : 'Stops in travel order. Hold and drag ≡ to reorder. Saving snaps stops to the road and recalculates numbers, distances and times.',
            style: const TextStyle(color: kMuted, fontSize: 12.5),
          ),
          if (shown.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_total(shown), style: const TextStyle(color: kYellow, fontSize: 12.5, fontWeight: FontWeight.w700))),
        ]),
      ),
      Expanded(
        child: shown.isEmpty
            ? const Center(child: Text('No stops yet. Tap "Edit on map".', style: TextStyle(color: kMuted)))
            : _mirror
                ? ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                    for (var i = 0; i < shown.length; i++)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: CircleAvatar(radius: 14, backgroundColor: kLine, child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
                        title: Text(shown[i].name),
                      ),
                  ])
                : ReorderableListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    buildDefaultDragHandles: false,
                    onReorderItem: (o, n) => setState(() {
                      final l = _list;
                      l.insert(n, l.removeAt(o));
                    }),
                    children: [
                      for (var i = 0; i < shown.length; i++)
                        ListTile(
                          key: ObjectKey(shown[i]),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: CircleAvatar(radius: 14, backgroundColor: kYellow, child: Text('${i + 1}', style: const TextStyle(color: kOnGold, fontSize: 12, fontWeight: FontWeight.w800))),
                          title: Text(shown[i].name),
                          subtitle: Text(
                            '${shown[i].localName.isNotEmpty ? '${shown[i].localName} • ' : ''}${shown[i].lat.toStringAsFixed(4)}, ${shown[i].lng.toStringAsFixed(4)}${_leg(shown[i])}',
                            style: const TextStyle(color: kMuted, fontSize: 12),
                          ),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.delete_outline, color: kRed), onPressed: () => setState(() => _list.removeAt(i))),
                            ReorderableDragStartListener(index: i, child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle, color: kMuted))),
                          ]),
                        ),
                    ],
                  ),
      ),
      if (_msg != null) Padding(padding: const EdgeInsets.all(8), child: Text(_msg!, style: const TextStyle(color: kAmber), textAlign: TextAlign.center)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Edit on map'),
              onPressed: _mirror ? null : _editOnMap,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Save route'),
            ),
          ),
        ]),
      ),
    ]);
  }
}

// ---------------- ANNOUNCEMENTS ----------------
class _UpdatesTab extends StatefulWidget {
  const _UpdatesTab();
  @override
  State<_UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends State<_UpdatesTab> {
  final _t = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _t.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      await Repo.postAnnouncement(text);
      _t.clear();
      HapticFeedback.lightImpact();
      msg.showSnackBar(const SnackBar(content: Text('Announcement posted')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Could not post: $e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const ScreenTitle(title: 'Updates', subtitle: 'Post announcements for students and parents'),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 20), children: [
            TextField(controller: _t, maxLines: 3, decoration: const InputDecoration(hintText: 'Write an update… (e.g. Bus will be 10 minutes late)')),
            const SizedBox(height: 10),
            GradientButton(label: 'Post update', icon: Icons.send_rounded, busy: _busy, onPressed: _post),
            const SizedBox(height: 18),
            const AnnouncementList(),
          ]),
        ),
      ]);
}

class _BreakdownDialog extends StatefulWidget {
  const _BreakdownDialog();
  @override
  State<_BreakdownDialog> createState() => _BreakdownDialogState();
}

class _BreakdownDialogState extends State<_BreakdownDialog> {
  final _t = TextEditingController();

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Report breakdown'),
        content: TextField(controller: _t, decoration: const InputDecoration(hintText: 'Details (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, _t.text.trim()), child: const Text('Report', style: TextStyle(color: kRed))),
        ],
      );
}
