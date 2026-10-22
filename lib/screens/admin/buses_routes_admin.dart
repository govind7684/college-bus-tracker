import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../data.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Fleet overview: each bus with its plate, contact, driver(s), student count, current trip and saved route stops.
/// (Stops and road geometry are edited by the bus's driver in the Route tab; the history of trips is kept.)
class BusesRoutesAdmin extends StatelessWidget {
  const BusesRoutesAdmin({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Buses & routes', style: serif(22))),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('app2_students').snapshots(),
          builder: (c, ss) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('app2_users').snapshots(),
            builder: (c, us) {
              if (!ss.hasData || !us.hasData) return const Center(child: CircularProgressIndicator());
              return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
                for (final b in kBuses)
                  _BusCard(
                    b,
                    students: ss.data!.docs.where((d) => busOf(d.data()) == b.id && (d.data()['status'] ?? 'active') == 'active').length,
                    drivers: [
                      for (final d in us.data!.docs)
                        if ((d.data()['role'] ?? 'driver').toString().toLowerCase() != 'admin' && busOf(d.data()) == b.id) (d.data()['name'] ?? 'Driver').toString(),
                    ],
                  ),
              ]);
            },
          ),
        ),
      );
}

class _BusCard extends StatelessWidget {
  final BusInfo bus;
  final int students;
  final List<String> drivers;
  const _BusCard(this.bus, {required this.students, required this.drivers});

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.doc('buses/${bus.id}_route').snapshots(),
        builder: (c, rs) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.doc('buses/${bus.id}_live').snapshots(),
          builder: (c, ls) {
            final route = parseRoute(rs.data?.data());
            final live = ls.data?.data();
            final running = live?['tripActive'] == true;
            return Card2(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.directions_bus_rounded, color: kYellow),
                  const SizedBox(width: 10),
                  Expanded(child: Text('${bus.label}  •  ${bus.plate}', style: serif(18))),
                  StatusChip(running ? 'trip running' : 'idle', running ? kGreen : kMuted),
                ]),
                const SizedBox(height: 10),
                Text('Contact: ${bus.phoneText}', style: const TextStyle(color: kMuted, fontSize: 13)),
                Text('Driver: ${drivers.isEmpty ? 'not assigned' : drivers.join(', ')}', style: const TextStyle(color: kMuted, fontSize: 13)),
                Text('Active students: $students', style: const TextStyle(color: kMuted, fontSize: 13)),
                const SizedBox(height: 10),
                Text('Route (${route.stops.length} stops)', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (route.stops.isEmpty)
                  const Text('No route saved yet. The driver creates it in the Route tab.', style: TextStyle(color: kMuted, fontSize: 12.5))
                else
                  for (var i = 0; i < route.stops.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('${i + 1}. ${route.stops[i].name}', style: const TextStyle(fontSize: 13.5)),
                    ),
              ]),
            );
          },
        ),
      );
}
