import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../background.dart';
import '../data.dart';
import '../settings.dart';
import '../services/photo_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'info_screens.dart';

typedef Me = Map<String, dynamic>;

/// The ONLY place a user is logged out: the explicit Log out button (after confirmation).
Future<void> confirmLogout(BuildContext context, {Future<void> Function()? before}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text('You will need to sign in again next time.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out', style: TextStyle(color: kRed))),
      ],
    ),
  );
  if (ok == true) {
    if (before != null) await before();
    await FirebaseAuth.instance.signOut();
  }
}

/// Bottom sheet listing [stops]; returns the chosen stop name.
Future<String?> pickStopSheet(BuildContext context, List<Stop> stops, {String title = 'Select your boarding stop'}) =>
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: kBg2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .92,
        builder: (_, ctl) => Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: kLine, borderRadius: BorderRadius.circular(4))),
          Padding(padding: const EdgeInsets.all(16), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          Expanded(
            child: ListView(controller: ctl, children: [
              for (final s in stops)
                ListTile(
                  leading: const Icon(Icons.location_on_outlined, color: kYellow),
                  title: Text(s.name),
                  onTap: () => Navigator.pop(context, s.name),
                ),
            ]),
          ),
        ]),
      ),
    );

class StudentScreen extends StatefulWidget {
  const StudentScreen({super.key});
  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  int _tab = 0;
  bool _prompted = false;
  String? _view; // bus being watched; null = my own bus
  late final Stream<DocumentSnapshot<Me>> _me = db.doc('app2_students/${Repo.uid}').snapshots();

  @override
  void initState() {
    super.initState();
    // make sure the profile record exists in Firestore (covers a sign-up that happened offline)
    Repo.ensureStudentProfile().then<void>((_) {}, onError: (Object _) {});
  }

  /// Boarding stop on [bus] (the stops of both journeys, without duplicates).
  Future<void> _pickStop(String bus) async {
    final msg = ScaffoldMessenger.of(context);
    List<Stop> stops;
    try {
      final rd = await Repo.routeOnce(bus);
      final seen = <String>{};
      stops = [...rd.stops, ...rd.retStops].where((s) => s.name.isNotEmpty && seen.add(s.name)).toList();
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Could not load stops: $e')));
      return;
    }
    if (stops.isEmpty) {
      msg.showSnackBar(const SnackBar(content: Text('No stops found yet. Ask the driver to save the route.')));
      return;
    }
    if (!mounted) return;
    final chosen = await pickStopSheet(context, stops);
    if (chosen != null) await _saveStop(chosen);
  }

  Future<void> _saveStop(String name) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      await db.doc('app2_students/${Repo.uid}').set({'uid': Repo.uid, 'stop': name}, SetOptions(merge: true));
      HapticFeedback.mediumImpact();
      msg.showSnackBar(SnackBar(content: Text('Your stop: $name')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Could not save stop: $e')));
    }
  }

  Future<void> _confirmStop(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set as your stop?'),
        content: Text(name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Set')),
        ],
      ),
    );
    if (ok == true) await _saveStop(name);
  }

  /// Changes the bus the student is assigned to; the old boarding stop belongs to the old route, so it is cleared.
  Future<void> _changeBus(String bus) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      await db.doc('app2_students/${Repo.uid}').set({'uid': Repo.uid, 'bus': bus, 'stop': null}, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _view = null);
      msg.showSnackBar(SnackBar(content: Text('You are now on ${busInfo(bus).label}. Select your boarding stop.')));
      await _pickStop(bus);
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Could not change bus: $e')));
    }
  }

  void _push(Widget w) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: AppSettings.rev,
        builder: (context, _, __) => StreamBuilder<DocumentSnapshot<Me>>(
          stream: _me,
          builder: (c, s) {
            final me = s.data?.data() ?? <String, dynamic>{};
            final mine = busOf(me);
            final view = _view ?? mine;
            if (s.hasData && s.data!.exists && me['stop'] == null && !_prompted) {
              _prompted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _pickStop(mine);
              });
            }
            final tabs = <Widget>[
              _HomeTab(
                me: me,
                mine: mine,
                view: view,
                onView: (b) => setState(() => _view = b == mine ? null : b),
                onPick: () => _pickStop(mine),
                onStopTap: _confirmStop,
              ),
              NotificationsContent(busId: mine),
              _ProfileTab(me: me, mine: mine, onPick: () => _pickStop(mine), onBus: _changeBus, push: _push),
            ];
            return PopScope(
              canPop: kIsWeb,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                if (_tab != 0) {
                  setState(() => _tab = 0); // back from any panel -> home panel
                } else if (_view != null) {
                  setState(() => _view = null); // back from the other bus's read-only view -> my bus
                } else {
                  goToPhoneHome(); // stays logged in, app keeps running
                }
              },
              child: Scaffold(
                body: IndexedStack(index: _tab, children: tabs),
                bottomNavigationBar: GlassNav(
                  index: _tab,
                  onTap: (i) => setState(() => _tab = i),
                  items: const [
                    NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
                    NavItem(Icons.notifications_none_rounded, Icons.notifications_rounded, 'Updates'),
                    NavItem(Icons.person_outline, Icons.person, 'Profile'),
                  ],
                ),
              ),
            );
          },
        ),
      );
}

String _greeting() {
  final h = DateTime.now().hour;
  return h < 12 ? 'Good morning,' : (h < 17 ? 'Good afternoon,' : 'Good evening,');
}

// ---------------- HOME PANEL ----------------
/// Status first (trip status, speed, next stop, ETA), then today's ride, then the vertical stop timeline.
/// The Bus 1 / Bus 2 switch shows the other bus in the same read-only layout the parents get.
class _HomeTab extends StatelessWidget {
  final Me me;
  final String mine, view;
  final ValueChanged<String> onView;
  final VoidCallback onPick;
  final void Function(String stopName) onStopTap;
  const _HomeTab({required this.me, required this.mine, required this.view, required this.onView, required this.onPick, required this.onStopTap});

  @override
  Widget build(BuildContext context) {
    final name = (me['name'] ?? 'Student').toString();
    final own = view == mine;
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_greeting(), style: serif(20, w: FontWeight.w400, color: kInk.o(.9))),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: serif(34, height: 1.1)),
          ]),
        ),
        BusSwitcher(value: view, mine: mine, onChanged: onView),
        if (!own)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 4),
            child: Row(children: [
              const Icon(Icons.visibility_outlined, size: 16, color: kBlue),
              const SizedBox(width: 6),
              Text('Viewing ${busInfo(view).label} • read-only', style: const TextStyle(color: kBlue, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
        const SizedBox(height: 12),
        LiveRoute(
          busId: view,
          builder: (c, r, l) => TrackerBody(
            busId: view,
            route: r,
            live: l,
            myStop: own ? me['stop'] as String? : null,
            onStopTap: own ? onStopTap : null,
            afterSummary: own ? _RideCard(key: const ValueKey('ride'), me: me, live: l, onPick: onPick) : null,
          ),
        ),
      ]),
    );
  }
}

/// "Today's ride" for the CURRENT journey only (morning or evening, never both):
/// Mark = I will ride, Skip = I will not be on the bus, plus the emergency "Switch to the other bus".
class _RideCard extends StatefulWidget {
  final Me me;
  final Live live;
  final VoidCallback onPick;
  const _RideCard({super.key, required this.me, required this.live, required this.onPick});
  @override
  State<_RideCard> createState() => _RideCardState();
}

class _RideCardState extends State<_RideCard> {
  late final Stream<DocumentSnapshot<Me>> _att = Repo.attDoc(Repo.uid).snapshots();
  bool _busy = false;

  Future<void> _set(String j, String status) async {
    setState(() => _busy = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      await Repo.markAttendance(j, widget.me, status: status);
      HapticFeedback.mediumImpact();
      msg.showSnackBar(SnackBar(content: Text(status == 'present' ? 'Marked: you are riding today' : 'Skipped: the driver knows you will not be on the bus')));
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Emergency bus switch: the bus broke down or was missed. The student picks a stop on the other
  /// bus's route; the mark becomes a Special Contingency Log entry for that bus's driver.
  Future<void> _switchBus(String j, String other) async {
    final msg = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final r = await Repo.routeOnce(other);
      final stops = r.journey(j).where((s) => s.name.isNotEmpty).toList();
      if (stops.isEmpty) {
        msg.showSnackBar(SnackBar(content: Text('${busInfo(other).label} has no stops for this trip yet.')));
      } else if (mounted) {
        final chosen = await pickStopSheet(context, stops, title: 'Where will you board ${busInfo(other).label}?');
        if (chosen != null) {
          await Repo.markAttendance(j, widget.me, rideBus: other, stop: chosen);
          HapticFeedback.mediumImpact();
          msg.showSnackBar(SnackBar(content: Text('Switched: the ${busInfo(other).label} driver will see you in the contingency log.')));
        }
      }
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Could not switch bus: $e')));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.live;
    final j = l.running ? l.direction : autoDirection();
    final mine = busOf(widget.me);
    final other = otherBus(mine);
    final stop = widget.me['stop'] as String?;
    return StreamBuilder<DocumentSnapshot<Me>>(
      stream: _att,
      builder: (c, s) {
        final data = s.data?.data();
        final st = data?['${j}Status'];
        final t = data?['${j}Time'];
        final riding = st == 'present', skipping = st == 'skip';
        final rideBus = (data?['${j}Bus'] ?? mine).toString();
        final contingency = riding && data?['${j}Contingency'] == true;
        final boarding = contingency ? (data?['${j}Stop'] ?? '').toString() : stop;
        return Card2(
          border: contingency ? kBlue.o(.7) : (riding ? kGreen.o(.6) : (skipping ? kAmber.o(.6) : null)),
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text("Today's ride", style: serif(18))),
              StatusChip(j == 'morning' ? 'Morning' : 'Evening', kBlue),
            ]),
            const SizedBox(height: 6),
            if (contingency)
              Row(children: [
                const Icon(Icons.swap_horiz_rounded, size: 17, color: kBlue),
                const SizedBox(width: 4),
                Expanded(child: Text('Boarding at $boarding on ${busInfo(rideBus).label}', style: const TextStyle(color: kBlue, fontSize: 13.5))),
              ])
            else
              GestureDetector(
                onTap: widget.onPick,
                child: Row(children: [
                  const Icon(Icons.location_on_outlined, size: 17, color: kMuted),
                  const SizedBox(width: 4),
                  Expanded(child: Text(stop == null ? 'Select your boarding stop' : 'Boarding at $stop', style: TextStyle(color: stop == null ? kAmber : kMuted, fontSize: 13.5))),
                  Text(stop == null ? 'Select' : 'Change', style: const TextStyle(color: kYellow, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            const SizedBox(height: 12),
            if (riding || skipping)
              Row(children: [
                Icon(contingency ? Icons.swap_horiz_rounded : (riding ? Icons.check_circle_rounded : Icons.do_not_disturb_on_rounded), color: contingency ? kBlue : (riding ? kGreen : kAmber), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      contingency ? 'Riding ${busInfo(rideBus).label} (emergency switch)' : (riding ? 'You are riding' : 'You will not be on the bus'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      '${riding ? 'Marked' : 'Skipped'}${t is Timestamp ? ' at ${fmtTime(t.toDate())}' : ''}${skipping ? ' • the driver knows' : ''}',
                      style: const TextStyle(color: kMuted, fontSize: 12.5),
                    ),
                  ]),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _set(j, contingency ? 'present' : (riding ? 'skip' : 'present')),
                  child: Text(contingency ? 'Switch back' : (riding ? 'Skip instead' : 'I am riding'), style: const TextStyle(color: kYellow)),
                ),
              ])
            else
              Row(children: [
                Expanded(
                  child: GradientButton(
                    label: 'Mark',
                    icon: Icons.check,
                    busy: _busy,
                    onPressed: () {
                      if (stop == null) {
                        widget.onPick();
                      } else {
                        _set(j, 'present');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(side: BorderSide(color: kAmber.o(.7)), foregroundColor: kAmber),
                      icon: const Icon(Icons.do_not_disturb_on_outlined, size: 20),
                      label: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      onPressed: _busy
                          ? null
                          : () {
                              if (stop == null) {
                                widget.onPick();
                              } else {
                                _set(j, 'skip');
                              }
                            },
                    ),
                  ),
                ),
              ]),
            if (!contingency) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), foregroundColor: kBlue),
                  onPressed: _busy ? null : () => _switchBus(j, other),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text('Bus broke down or missed? Switch to ${busInfo(other).label}', style: const TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }
}

class _ProfileTab extends StatelessWidget {
  final Me me;
  final String mine;
  final VoidCallback onPick;
  final ValueChanged<String> onBus;
  final void Function(Widget) push;
  const _ProfileTab({required this.me, required this.mine, required this.onPick, required this.onBus, required this.push});

  Widget _row(IconData icon, String label, VoidCallback onTap) => Card2(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          Icon(icon, color: kYellow),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          const Icon(Icons.chevron_right, color: kMuted),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final name = (me['name'] ?? 'Student').toString();
    final email = (me['email'] ?? FirebaseAuth.instance.currentUser?.email ?? '').toString();
    return Column(children: [
      const ScreenTitle(title: 'Profile', subtitle: 'Carmel Polytechnic College'),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), children: [
          Center(
            child: PhotoAvatar(name: name, photoB64: me['photoB64']?.toString(), radius: 40, editable: true),
          ),
          const SizedBox(height: 10),
          Center(child: Text(name, style: serif(24))),
          Center(child: Text(email, style: const TextStyle(color: kMuted))),
          const SizedBox(height: 18),
          Card2(
            onTap: onPick,
            border: me['stop'] == null ? kAmber : null,
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: kBlue.o(.16), shape: BoxShape.circle),
                child: const Icon(Icons.location_on, color: kBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your boarding stop', style: TextStyle(color: kMuted, fontSize: 12)),
                  Text((me['stop'] ?? 'Tap to select your stop').toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
              ),
              Text(me['stop'] == null ? 'Select' : 'Change', style: const TextStyle(color: kYellow, fontWeight: FontWeight.w800)),
            ]),
          ),
          Card2(
            child: Row(children: [
              const Icon(Icons.directions_bus_rounded, color: kYellow),
              const SizedBox(width: 12),
              const Expanded(child: Text('My bus', style: TextStyle(fontWeight: FontWeight.w700))),
              for (final b in kBuses)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(b.label),
                    selected: mine == b.id,
                    selectedColor: kYellow,
                    backgroundColor: kBg2,
                    showCheckmark: false,
                    labelStyle: TextStyle(fontWeight: FontWeight.w700, color: mine == b.id ? kOnGold : kMuted),
                    side: const BorderSide(color: kLine),
                    onSelected: (_) {
                      if (mine != b.id) onBus(b.id);
                    },
                  ),
                ),
            ]),
          ),
          _row(Icons.badge_outlined, 'Bus details', () => push(BusDetailsScreen(busId: mine))),
          _row(Icons.calendar_month_outlined, 'Bus schedule', () => push(TripsScreen(busId: mine))),
          _row(Icons.settings_outlined, 'Settings', () => push(const SettingsScreen())),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: kRed, side: const BorderSide(color: kRed), minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            onPressed: () => confirmLogout(context),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('You stay logged in until you press Log out.', textAlign: TextAlign.center, style: TextStyle(color: kMuted, fontSize: 12)),
          ),
        ]),
      ),
    ]);
  }
}
