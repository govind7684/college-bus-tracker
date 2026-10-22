import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../data.dart';
import '../../services/audit_service.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Drivers (app2_users documents whose role is not 'admin'): view, edit, assign a bus, activate / deactivate.
class DriversAdmin extends StatelessWidget {
  const DriversAdmin({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Drivers', style: serif(22))),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: kYellow, foregroundColor: kOnGold,
          onPressed: () => _edit(context, null, null), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Add driver'),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('app2_users').snapshots(),
          builder: (c, s) {
            if (s.hasError) return const Center(child: Text('Could not load drivers.', style: TextStyle(color: kRed)));
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final docs = s.data!.docs.where((d) => (d.data()['role'] ?? 'driver').toString().toLowerCase() != 'admin').toList();
            if (docs.isEmpty) return const Center(child: Text('No drivers yet. Tap "Add driver".', style: TextStyle(color: kMuted)));
            return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
              for (final d in docs) _card(context, d),
            ]);
          },
        ),
      );

  Widget _card(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final active = m['active'] != false;
    final b = busInfo(busOf(m));
    return Card2(
      onTap: () => _edit(context, d.id, m),
      child: Row(children: [
        const CircleAvatar(backgroundColor: kYellow, foregroundColor: kOnGold, child: Icon(Icons.badge_rounded)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((m['name'] ?? 'Driver').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${b.label}  •  ${b.plate}${(m['phone'] ?? '').toString().isEmpty ? '' : '  •  ${m['phone']}'}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
          ]),
        ),
        StatusChip(active ? 'active' : 'inactive', active ? kGreen : kRed),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, String? uid, Map<String, dynamic>? m) async {
    final msg = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _DriverForm(uid: uid, data: m),
    );
    if (msg != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _DriverForm extends StatefulWidget {
  final String? uid;
  final Map<String, dynamic>? data;
  const _DriverForm({required this.uid, required this.data});
  @override
  State<_DriverForm> createState() => _DriverFormState();
}

class _DriverFormState extends State<_DriverForm> {
  final _f = GlobalKey<FormState>();
  late final _uid = TextEditingController(text: widget.uid);
  late final _name = TextEditingController(text: (widget.data?['name'] ?? '').toString());
  late final _phone = TextEditingController(text: (widget.data?['phone'] ?? '').toString());
  late final _lic = TextEditingController(text: (widget.data?['licenceNo'] ?? '').toString());
  late String _bus = busOf(widget.data);
  late bool _active = widget.data?['active'] != false;
  bool _busy = false;
  String? _err;
  bool get _isNew => widget.uid == null;

  @override
  void dispose() {
    for (final c in [_uid, _name, _phone, _lic]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_f.currentState!.validate()) return;
    setState(() { _busy = true; _err = null; });
    final id = _uid.text.trim();
    final data = <String, dynamic>{'name': _name.text.trim(), 'phone': _phone.text.trim(), 'licenceNo': _lic.text.trim(), 'bus': _bus, 'active': _active};
    try {
      if (_isNew) {
        data['role'] = 'driver';
        data['createdAt'] = FieldValue.serverTimestamp();
      }
      await db.doc('app2_users/$id').set(data, SetOptions(merge: true));
      final old = widget.data ?? const {};
      final changed = _isNew ? data : {for (final e in data.entries) if ('${old[e.key] ?? ''}' != '${e.value}') e.key: e.value};
      await Audit.log(_isNew ? 'driver.create' : (changed.containsKey('active') ? 'driver.status' : (changed.containsKey('bus') ? 'driver.assign_bus' : 'driver.update')),
          target: 'app2_users', targetId: id, details: {for (final e in changed.entries) if (e.value is! FieldValue) e.key: e.value});
      if (mounted) Navigator.pop(context, 'Driver saved.');
    } on FirebaseException catch (e) {
      if (mounted) setState(() { _busy = false; _err = 'Could not save (${e.code}).'; });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Form(
            key: _f,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_isNew ? 'Add driver' : 'Edit driver', style: serif(22)),
              if (_isNew)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('First create the driver\'s login in Firebase Console > Authentication, then paste the User UID here.', style: TextStyle(color: kMuted, fontSize: 12.5)),
                ),
              const SizedBox(height: 14),
              TextFormField(controller: _uid, enabled: _isNew, decoration: const InputDecoration(labelText: 'Firebase User UID'), validator: (v) => (v == null || v.trim().length < 10 || v.contains('/')) ? 'Paste the UID from Authentication' : null),
              const SizedBox(height: 10),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
              const SizedBox(height: 10),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 10),
              TextFormField(controller: _lic, decoration: const InputDecoration(labelText: 'Licence number')),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Bus  '),
                for (final b in kBuses)
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(b.label), selected: _bus == b.id, onSelected: (_) => setState(() => _bus = b.id))),
              ]),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Account active'), value: _active, onChanged: (v) => setState(() => _active = v)),
              if (_err != null) Text(_err!, style: const TextStyle(color: kRed)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
            ]),
          ),
        ),
      );
}
