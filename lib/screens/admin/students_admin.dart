import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data.dart';
import '../../services/audit_service.dart';
import '../../services/import_export.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// One student as the administrator sees it: the roster entry (registered by the institution) merged with the
/// activated profile (app2_students) when the student has activated their account.
class _Row {
  final String email;
  final Map<String, dynamic> roster; // app2_roster entry (may be empty for older students)
  final String? uid;
  final Map<String, dynamic> profile; // app2_students entry (empty until activated)
  _Row(this.email, this.roster, this.uid, this.profile);

  Map<String, dynamic> get m => {...roster, ...profile};
  String get name => (m['name'] ?? '').toString();
  String get admissionNo => (m['admissionNo'] ?? '').toString();
  String get className => (m['className'] ?? '').toString();
  String get bus => busOf(m);
  bool get activated => uid != null;
  String get status => activated ? (profile['status'] ?? 'active').toString() : 'not activated';
}

class StudentsAdmin extends StatefulWidget {
  const StudentsAdmin({super.key});
  @override
  State<StudentsAdmin> createState() => _StudentsAdminState();
}

class _StudentsAdminState extends State<StudentsAdmin> {
  String _q = '', _bus = 'all', _status = 'all';
  List<_Row> _rows = const [];

  List<_Row> _merge(QuerySnapshot<Map<String, dynamic>> roster, QuerySnapshot<Map<String, dynamic>> students) {
    final byEmail = <String, _Row>{};
    for (final d in roster.docs) {
      byEmail[d.id] = _Row(d.id, d.data(), null, const {});
    }
    for (final d in students.docs) {
      final p = d.data();
      final e = (p['email'] ?? '').toString().toLowerCase();
      final key = e.isEmpty ? d.id : e;
      byEmail[key] = _Row(key, byEmail[key]?.roster ?? const {}, d.id, p);
    }
    final l = byEmail.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return l;
  }

  bool _match(_Row r) {
    if (_bus != 'all' && r.bus != _bus) return false;
    if (_status != 'all' && r.status != _status) return false;
    final q = _q.trim().toLowerCase();
    return q.isEmpty || r.name.toLowerCase().contains(q) || r.email.contains(q) || r.admissionNo.toLowerCase().contains(q) || r.className.toLowerCase().contains(q);
  }

  Future<void> _export() async {
    final rows = _rows.where(_match).toList();
    final csv = Csv.encode(
      ['name', 'email', 'admissionNo', 'className', 'bus', 'stop', 'phone', 'guardianName', 'guardianPhone', 'status'],
      [for (final r in rows) [r.name, r.email, r.admissionNo, r.className, r.bus, r.m['stop'], r.m['phone'], r.m['guardianName'], r.m['guardianPhone'], r.status]],
    );
    await Clipboard.setData(ClipboardData(text: csv));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rows.length} students copied as CSV. Paste into Excel / Sheets.')));
    Audit.log('student.export', target: 'app2_students', details: {'rows': rows.length});
  }

  Future<void> _import() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import students (CSV)'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Paste rows with the columns:\nname, email, admissionNo, className, bus, phone\n(first line may be the header). Existing emails are updated, nobody is deleted.',
                style: TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 10),
            TextField(controller: ctl, minLines: 6, maxLines: 10, decoration: const InputDecoration(hintText: 'Asha Nair,asha@mail.com,CP101,S3 CT,bus1,98470...')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final parsed = Csv.decode(ctl.text);
    final batch = db.batch();
    var n = 0, bad = 0;
    final seen = <String>{};
    for (var i = 0; i < parsed.length; i++) {
      final c = parsed[i];
      if (i == 0 && c.isNotEmpty && c[0].toLowerCase() == 'name') continue;
      String at(int k) => k < c.length ? c[k] : '';
      final email = at(1).toLowerCase();
      if (at(0).isEmpty || !email.contains('@') || at(2).isEmpty || !seen.add(email)) { bad++; continue; }
      batch.set(db.doc('app2_roster/$email'), {
        'name': at(0), 'admissionNo': at(2), 'className': at(3),
        'bus': kBuses.any((b) => b.id == at(4)) ? at(4) : 'bus1',
        'phone': at(5), 'status': 'approved', 'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      n++;
      if (n >= 450) break; // one batch holds at most 500 writes
    }
    try {
      if (n > 0) await batch.commit();
      Audit.log('student.import', target: 'app2_roster', details: {'imported': n, 'skipped': bad});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported $n students${bad > 0 ? ', skipped $bad invalid rows' : ''}.')));
    } on FirebaseException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed (${e.code}).')));
    }
  }

  Future<void> _edit([_Row? r]) async {
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _StudentForm(row: r, all: _rows),
    );
    if (saved != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('Students', style: serif(22)),
          actions: [
            IconButton(tooltip: 'Import CSV', icon: const Icon(Icons.upload_file_rounded), onPressed: _import),
            IconButton(tooltip: 'Export CSV', icon: const Icon(Icons.download_rounded), onPressed: _export),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: kYellow, foregroundColor: kOnGold,
          onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Add student'),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('app2_roster').snapshots(),
          builder: (c, rs) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('app2_students').snapshots(),
            builder: (c, ss) {
              if (rs.hasError || ss.hasError) {
                return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Could not load students. Check the connection and the published Firestore rules.', textAlign: TextAlign.center, style: TextStyle(color: kRed))));
              }
              if (!rs.hasData || !ss.hasData) return const Center(child: CircularProgressIndicator());
              _rows = _merge(rs.data!, ss.data!);
              final shown = _rows.where(_match).toList();
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(children: [
                    TextField(
                      onChanged: (v) => setState(() => _q = v),
                      decoration: const InputDecoration(hintText: 'Search name, email, admission no, class', prefixIcon: Icon(Icons.search_rounded)),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final o in [('all', 'All buses'), for (final b in kBuses) (b.id, b.label)])
                          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(o.$2), selected: _bus == o.$1, onSelected: (_) => setState(() => _bus = o.$1))),
                        const SizedBox(width: 8),
                        for (final o in const [('all', 'Any status'), ('active', 'Active'), ('inactive', 'Inactive'), ('not activated', 'Not activated')])
                          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(o.$2), selected: _status == o.$1, onSelected: (_) => setState(() => _status = o.$1))),
                      ]),
                    ),
                  ]),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(child: Text(_rows.isEmpty ? 'No students yet. Tap "Add student".' : 'No student matches.', style: const TextStyle(color: kMuted)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                          itemCount: shown.length,
                          itemBuilder: (c, i) {
                            final r = shown[i];
                            final col = r.status == 'active' ? kGreen : (r.status == 'inactive' ? kRed : kAmber);
                            return Card2(
                              onTap: () => _edit(r),
                              child: Row(children: [
                                CircleAvatar(backgroundColor: kYellow, foregroundColor: kOnGold, child: Text(r.name.isEmpty ? '?' : r.name[0].toUpperCase())),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('${r.admissionNo.isEmpty ? '-' : r.admissionNo}  •  ${busInfo(r.bus).label}${r.className.isEmpty ? '' : '  •  ${r.className}'}',
                                        style: const TextStyle(color: kMuted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ]),
                                ),
                                StatusChip(r.status, col),
                              ]),
                            );
                          },
                        ),
                ),
              ]);
            },
          ),
        ),
      );
}

class _StudentForm extends StatefulWidget {
  final _Row? row;
  final List<_Row> all;
  const _StudentForm({required this.row, required this.all});
  @override
  State<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<_StudentForm> {
  final _f = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.row?.name);
  late final _email = TextEditingController(text: widget.row?.email);
  late final _adm = TextEditingController(text: widget.row?.admissionNo);
  late final _cls = TextEditingController(text: widget.row?.className);
  late final _phone = TextEditingController(text: (widget.row?.m['phone'] ?? '').toString());
  late final _gn = TextEditingController(text: (widget.row?.m['guardianName'] ?? '').toString());
  late final _gp = TextEditingController(text: (widget.row?.m['guardianPhone'] ?? '').toString());
  late String _bus = widget.row?.bus ?? 'bus1';
  late bool _active = (widget.row?.status ?? 'active') != 'inactive';
  bool _busy = false;
  String? _err;

  bool get _isNew => widget.row == null;

  @override
  void dispose() {
    for (final c in [_name, _email, _adm, _cls, _phone, _gn, _gp]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_f.currentState!.validate()) return;
    final email = _email.text.trim().toLowerCase();
    final adm = _adm.text.trim();
    final clash = widget.all.any((r) => r.admissionNo.toLowerCase() == adm.toLowerCase() && r.email != email && adm.isNotEmpty);
    if (clash) { setState(() => _err = 'Another student already has this admission number.'); return; }
    if (_isNew && widget.all.any((r) => r.email == email)) { setState(() => _err = 'This email is already registered.'); return; }
    setState(() { _busy = true; _err = null; });
    final data = <String, dynamic>{
      'name': _name.text.trim(), 'admissionNo': adm, 'className': _cls.text.trim(), 'phone': _phone.text.trim(),
      'guardianName': _gn.text.trim(), 'guardianPhone': _gp.text.trim(), 'bus': _bus,
    };
    try {
      final r = widget.row;
      await db.doc('app2_roster/$email').set({...data, 'status': 'approved', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      final ruid = r?.uid;
      if (ruid != null) {
        await db.doc('app2_students/$ruid').set({...data, 'status': _active ? 'active' : 'inactive', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
      final changed = <String, dynamic>{
        for (final e in data.entries) if ((r?.m[e.key] ?? '').toString() != e.value.toString()) e.key: e.value,
        if (ruid != null && r?.status != (_active ? 'active' : 'inactive')) 'status': _active ? 'active' : 'inactive',
      };
      await Audit.log(_isNew ? 'student.create' : (changed.containsKey('bus') ? 'student.assign_bus' : 'student.update'),
          target: 'app2_students', targetId: r?.uid ?? email, details: _isNew ? {'email': email, ...data} : changed);
      if (mounted) Navigator.pop(context, _isNew ? 'Student registered. They can now activate their account.' : 'Student saved.');
    } on FirebaseException catch (e) {
      if (mounted) setState(() { _busy = false; _err = 'Could not save (${e.code}). Check the published Firestore rules.'; });
    }
  }

  Widget _tf(TextEditingController c, String label, {bool req = false, TextInputType? type, bool enabled = true, String? Function(String?)? v}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c, enabled: enabled, keyboardType: type,
          decoration: InputDecoration(labelText: label),
          validator: v ?? (req ? (x) => (x == null || x.trim().isEmpty) ? 'Required' : null : null),
        ),
      );

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Form(
            key: _f,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_isNew ? 'Add student' : 'Edit student', style: serif(22)),
              const SizedBox(height: 14),
              _tf(_name, 'Full name', req: true),
              _tf(_email, 'Email (used to activate the account)', type: TextInputType.emailAddress, enabled: _isNew,
                  v: (x) => (x == null || !x.contains('@')) ? 'Enter a valid email' : null),
              _tf(_adm, 'Admission number', req: true),
              _tf(_cls, 'Class'),
              _tf(_phone, 'Student phone', type: TextInputType.phone),
              _tf(_gn, 'Guardian name'),
              _tf(_gp, 'Guardian phone', type: TextInputType.phone),
              Row(children: [
                const Text('Bus  '),
                for (final b in kBuses)
                  Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(b.label), selected: _bus == b.id, onSelected: (_) => setState(() => _bus = b.id))),
              ]),
              if (widget.row?.activated == true)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Account active'),
                  subtitle: const Text('Off = the student cannot use the app. Records and history are kept.', style: TextStyle(fontSize: 12, color: kMuted)),
                  value: _active, onChanged: (v) => setState(() => _active = v),
                ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: const TextStyle(color: kRed))),
              const SizedBox(height: 14),
              ElevatedButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
            ]),
          ),
        ),
      );
}
