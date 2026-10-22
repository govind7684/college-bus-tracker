import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data.dart';
import '../../services/audit_service.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../student_screen.dart' show confirmLogout;
import 'accounts_admin.dart';
import 'buses_routes_admin.dart';
import 'drivers_admin.dart';
import 'fees_admin.dart';
import 'students_admin.dart';

/// Institution administrator dashboard: live counts from the real collections.
/// Menu to the management screens (fees, expenses, documents and reports come in later stages).
class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('Institution', style: serif(22)),
          actions: [
            IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout_rounded), onPressed: () => confirmLogout(context)),
          ],
        ),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: const [
            _Menu(),
            _Summary(),
            SizedBox(height: 8),
            _Activity(),
          ]),
        ),
      );
}

class _Menu extends StatelessWidget {
  const _Menu();

  Widget _item(BuildContext context, String label, IconData icon, Widget page) => Expanded(
        child: Card2(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page)),
          child: Column(children: [
            Icon(icon, color: kYellow, size: 28),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _item(context, 'Students', Icons.school_rounded, const StudentsAdmin()),
          const SizedBox(width: 10),
          _item(context, 'Drivers', Icons.badge_rounded, const DriversAdmin()),
          const SizedBox(width: 10),
          _item(context, 'Buses & routes', Icons.directions_bus_rounded, const BusesRoutesAdmin()),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _item(context, 'Fees', Icons.receipt_long_rounded, const FeesAdmin()),
          const SizedBox(width: 10),
          _item(context, 'Received & expenses', Icons.account_balance_wallet_rounded, const AccountsAdmin()),
          const SizedBox(width: 10),
          const Expanded(child: SizedBox()),
        ]),
        const SizedBox(height: 12),
      ]);
}

class _Tile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Tile(this.label, this.value, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Card2(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: color.o(.16), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: serif(24)),
              Text(label, style: const TextStyle(color: kMuted, fontSize: 12.5)),
            ]),
          ),
        ]),
      );
}

class _Summary extends StatelessWidget {
  const _Summary();

  bool _active(Map<String, dynamic> m) => (m['status'] ?? 'active').toString() == 'active' && m['active'] != false;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('app2_students').snapshots(),
        builder: (c, st) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('app2_users').snapshots(),
          builder: (c, us) {
            if (st.hasError || us.hasError) {
              return const Card2(child: Text('Could not load the summary. Check your connection and the published Firestore rules.', style: TextStyle(color: kRed)));
            }
            if (!st.hasData || !us.hasData) {
              return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
            }
            final students = st.data!.docs.map((d) => d.data()).toList();
            final staff = us.data!.docs.map((d) => d.data()).toList();
            final drivers = staff.where((m) => (m['role'] ?? 'driver').toString().toLowerCase() != 'admin').toList();
            final activeStudents = students.where(_active).length;
            final activeDrivers = drivers.where(_active).length;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionLabel('Overview'),
              Row(children: [
                Expanded(child: _Tile('Students', '${students.length}', Icons.school_rounded, kBlue)),
                const SizedBox(width: 10),
                Expanded(child: _Tile('Active students', '$activeStudents', Icons.verified_rounded, kGreen)),
              ]),
              Row(children: [
                Expanded(child: _Tile('Drivers', '${drivers.length}', Icons.badge_rounded, kAmber)),
                const SizedBox(width: 10),
                Expanded(child: _Tile('Active drivers', '$activeDrivers', Icons.verified_user_rounded, kGreen)),
              ]),
              Row(children: [
                Expanded(child: _Tile('Buses', '${kBuses.length}', Icons.directions_bus_rounded, kYellow)),
                const SizedBox(width: 10),
                Expanded(child: _Tile('Routes', '${kBuses.length}', Icons.route_rounded, kYellow)),
              ]),
              const SectionLabel('Students per bus'),
              for (final b in kBuses)
                Card2(
                  child: Row(children: [
                    const Icon(Icons.directions_bus_rounded, color: kYellow),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${b.label}  •  ${b.plate}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text('${students.where((m) => busOf(m) == b.id).length}', style: serif(20)),
                  ]),
                ),
            ]);
          },
        ),
      );
}

class _Activity extends StatelessWidget {
  const _Activity();
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Audit.recent(limit: 15),
        builder: (c, s) {
          if (s.hasError) return const SizedBox.shrink();
          final docs = s.data?.docs ?? const [];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionLabel('Recent activity'),
            if (docs.isEmpty)
              const Card2(child: Text('No activity recorded yet.', style: TextStyle(color: kMuted))),
            for (final d in docs)
              Card2(
                child: Row(children: [
                  const Icon(Icons.history_rounded, size: 18, color: kMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((d.data()['action'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${d.data()['actorEmail'] ?? ''}', style: const TextStyle(color: kMuted, fontSize: 12)),
                    ]),
                  ),
                  Text(
                    (d.data()['at'] as Timestamp?) == null ? '' : DateFormat('d MMM, HH:mm').format((d.data()['at'] as Timestamp).toDate()),
                    style: const TextStyle(color: kMuted, fontSize: 12),
                  ),
                ]),
              ),
          ]);
        },
      );
}
