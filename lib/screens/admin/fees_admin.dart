import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data.dart';
import '../../services/audit_service.dart';
import '../../services/pdf_service.dart';
import '../../theme.dart';
import '../../widgets.dart';

String _me() => FirebaseAuth.instance.currentUser?.uid ?? '';
String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
String _nice(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : DateFormat('dd MMM yyyy').format(d);
}

void _snack(BuildContext c, String t) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(t)));

const _modes = ['Cash', 'UPI', 'Bank', 'Cheque'];

/// A fee charged to one student (app2_fees). Never deleted: a wrong fee is cancelled.
class _Fee {
  final String id;
  final Map<String, dynamic> m;
  _Fee(this.id, this.m);
  String get studentKey => (m['studentKey'] ?? '').toString();
  String get name => (m['studentName'] ?? '').toString();
  String get admissionNo => (m['admissionNo'] ?? '').toString();
  String get className => (m['className'] ?? '').toString();
  String get bus => busOf(m);
  String get title => (m['title'] ?? '').toString();
  String get dueDate => (m['dueDate'] ?? '').toString();
  int get amount => (m['amount'] as num?)?.toInt() ?? 0;
}

/// A payment received against a fee (app2_payments). Never deleted: a wrong payment is voided.
class _Pay {
  final String id;
  final Map<String, dynamic> m;
  _Pay(this.id, this.m);
  int get amount => (m['amount'] as num?)?.toInt() ?? 0;
  bool get voided => m['voided'] == true;
  String get receiptNo => (m['receiptNo'] ?? '').toString();
  String get paidOn => (m['paidOn'] ?? '').toString();
  String get mode => (m['mode'] ?? '').toString();
  String get note => (m['note'] ?? '').toString();
}

class _Line {
  final _Fee fee;
  final int paid;
  _Line(this.fee, this.paid);
  int get balance => fee.amount - paid;
}

/// A student that can be charged a fee (roster entry merged with the activated profile).
class _Stu {
  final String key, name, admissionNo, className, bus;
  _Stu(this.key, this.name, this.admissionNo, this.className, this.bus);
}

Future<List<_Stu>> _loadStudents() async {
  final roster = await db.collection('app2_roster').get();
  final students = await db.collection('app2_students').get();
  final all = <String, Map<String, dynamic>>{for (final d in roster.docs) d.id: d.data()};
  for (final d in students.docs) {
    final p = d.data();
    final e = (p['email'] ?? '').toString().toLowerCase();
    final key = e.isEmpty ? d.id : e;
    all[key] = {...?all[key], ...p};
  }
  final out = <_Stu>[
    for (final e in all.entries)
      if ((e.value['status'] ?? 'active').toString() != 'inactive' && (e.value['name'] ?? '').toString().isNotEmpty)
        _Stu(e.key, e.value['name'].toString(), (e.value['admissionNo'] ?? '').toString(), (e.value['className'] ?? '').toString(), busOf(e.value)),
  ];
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

class FeesAdmin extends StatefulWidget {
  const FeesAdmin({super.key});
  @override
  State<FeesAdmin> createState() => _FeesAdminState();
}

class _FeesAdminState extends State<FeesAdmin> {
  String _q = '', _bus = 'all', _show = 'all';
  List<_Line> _shown = const [];

  bool _match(_Line l) {
    if (_bus != 'all' && l.fee.bus != _bus) return false;
    if (_show == 'pending' && l.balance <= 0) return false;
    if (_show == 'paid' && l.balance > 0) return false;
    final q = _q.trim().toLowerCase();
    return q.isEmpty || l.fee.name.toLowerCase().contains(q) || l.fee.admissionNo.toLowerCase().contains(q) || l.fee.title.toLowerCase().contains(q);
  }

  Future<void> _pdf() async {
    if (_shown.isEmpty) {
      _snack(context, 'Nothing to export.');
      return;
    }
    final billed = _shown.fold<int>(0, (a, l) => a + l.fee.amount);
    final paid = _shown.fold<int>(0, (a, l) => a + l.paid);
    await PdfService.shareTable(
      fileName: 'fees_${_ymd(DateTime.now())}.pdf',
      title: 'Bus fees report',
      subtitle: '${_bus == 'all' ? 'All buses' : busInfo(_bus).label}  |  ${{'all': 'All fees', 'pending': 'Pending only', 'paid': 'Paid only'}[_show]}',
      headers: const ['Student', 'Adm no', 'Class', 'Bus', 'Fee', 'Due date', 'Amount', 'Paid', 'Balance'],
      rows: [
        for (final l in _shown)
          [l.fee.name, l.fee.admissionNo, l.fee.className, busInfo(l.fee.bus).label, l.fee.title, _nice(l.fee.dueDate), rs(l.fee.amount), rs(l.paid), rs(l.balance)],
      ],
      summary: [
        ['Total billed', rs(billed)],
        ['Total received', rs(paid)],
        ['Total pending', rs(billed - paid)],
      ],
    );
    Audit.log('fee.report_pdf', target: 'app2_fees', details: {'rows': _shown.length});
  }

  Future<void> _add() async {
    final students = await _loadStudents();
    if (!mounted) return;
    final msg = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _AddFeeSheet(students: students),
    );
    if (msg != null && mounted) _snack(context, msg);
  }

  Future<void> _open(_Line l) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _FeeSheet(fee: l.fee),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text('Fees', style: serif(22)),
          actions: [IconButton(tooltip: 'PDF report', icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: _pdf)],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: kYellow,
          foregroundColor: kOnGold,
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add fee'),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('app2_fees').snapshots(),
          builder: (c, fs) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('app2_payments').snapshots(),
            builder: (c, ps) {
              if (fs.hasError || ps.hasError) {
                return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Could not load fees. Check the connection and publish the updated Firestore rules.', textAlign: TextAlign.center, style: TextStyle(color: kRed))));
              }
              if (!fs.hasData || !ps.hasData) return const Center(child: CircularProgressIndicator());
              final paidBy = <String, int>{};
              for (final d in ps.data!.docs) {
                final m = d.data();
                if (m['voided'] == true) continue;
                final id = (m['feeId'] ?? '').toString();
                paidBy[id] = (paidBy[id] ?? 0) + ((m['amount'] as num?)?.toInt() ?? 0);
              }
              final lines = <_Line>[
                for (final d in fs.data!.docs)
                  if (d.data()['status'] != 'cancelled') _Line(_Fee(d.id, d.data()), paidBy[d.id] ?? 0),
              ];
              lines.sort((a, b) {
                final c1 = a.fee.dueDate.compareTo(b.fee.dueDate);
                return c1 != 0 ? c1 : a.fee.name.toLowerCase().compareTo(b.fee.name.toLowerCase());
              });
              _shown = lines.where(_match).toList();
              final billed = _shown.fold<int>(0, (a, l) => a + l.fee.amount);
              final paid = _shown.fold<int>(0, (a, l) => a + l.paid);
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(children: [
                    TextField(
                      onChanged: (v) => setState(() => _q = v),
                      decoration: const InputDecoration(hintText: 'Search student, admission no, fee', prefixIcon: Icon(Icons.search_rounded)),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final o in [('all', 'All buses'), for (final b in kBuses) (b.id, b.label)])
                          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(o.$2), selected: _bus == o.$1, onSelected: (_) => setState(() => _bus = o.$1))),
                        const SizedBox(width: 8),
                        for (final o in const [('all', 'All'), ('pending', 'Pending'), ('paid', 'Paid')])
                          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(o.$2), selected: _show == o.$1, onSelected: (_) => setState(() => _show = o.$1))),
                      ]),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    _Total('Billed', rupee(billed), kBlue),
                    const SizedBox(width: 8),
                    _Total('Received', rupee(paid), kGreen),
                    const SizedBox(width: 8),
                    _Total('Pending', rupee(billed - paid), billed - paid > 0 ? kAmber : kGreen),
                  ]),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _shown.isEmpty
                      ? Center(child: Text(lines.isEmpty ? 'No fees yet. Tap "Add fee".' : 'No fee matches.', style: const TextStyle(color: kMuted)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                          itemCount: _shown.length,
                          itemBuilder: (c, i) {
                            final l = _shown[i];
                            final cleared = l.balance <= 0;
                            return Card2(
                              onTap: () => _open(l),
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(l.fee.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('${l.fee.title}  •  ${busInfo(l.fee.bus).label}', style: const TextStyle(color: kMuted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('Due ${_nice(l.fee.dueDate)}  •  ${rupee(l.fee.amount)}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
                                  ]),
                                ),
                                const SizedBox(width: 8),
                                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                  StatusChip(cleared ? 'Paid' : (l.paid > 0 ? 'Part paid' : 'Pending'), cleared ? kGreen : kAmber),
                                  if (!cleared) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${rupee(l.balance)} due', style: const TextStyle(color: kAmber, fontSize: 12.5, fontWeight: FontWeight.w600))),
                                  if (!cleared)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: kYellow, foregroundColor: kOnGold, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                                        onPressed: () => _open(l),
                                        child: const Text('Receive'),
                                      ),
                                    ),
                                ]),
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

class _Total extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Total(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(color: color.o(.12), borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: kMuted, fontSize: 11.5)),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}

/// Add a fee for one student, for every student of a bus, or for everybody.
class _AddFeeSheet extends StatefulWidget {
  final List<_Stu> students;
  const _AddFeeSheet({required this.students});
  @override
  State<_AddFeeSheet> createState() => _AddFeeSheetState();
}

class _AddFeeSheetState extends State<_AddFeeSheet> {
  String _target = 'one'; // one | bus1 | bus2 | all
  _Stu? _picked;
  final _title = TextEditingController();
  final _amount = TextEditingController();
  DateTime _due = DateTime.now().add(const Duration(days: 30));
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  List<_Stu> get _targets {
    if (_target == 'one') return _picked == null ? const [] : [_picked!];
    if (_target == 'all') return widget.students;
    return widget.students.where((s) => s.bus == _target).toList();
  }

  Future<void> _save() async {
    final amt = int.tryParse(_amount.text.trim()) ?? 0;
    final list = _targets;
    if (_title.text.trim().isEmpty) return setState(() => _err = 'Enter the fee name, e.g. "Term 1 bus fee".');
    if (amt <= 0) return setState(() => _err = 'Enter the amount in rupees.');
    if (list.isEmpty) return setState(() => _err = _target == 'one' ? 'Choose a student.' : 'No students found for this choice.');
    if (list.length > 450) return setState(() => _err = 'Too many students at once. Choose one bus at a time.');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final batch = db.batch();
      for (final s in list) {
        batch.set(db.collection('app2_fees').doc(), {
          'studentKey': s.key,
          'studentName': s.name,
          'admissionNo': s.admissionNo,
          'className': s.className,
          'bus': s.bus,
          'title': _title.text.trim(),
          'amount': amt,
          'dueDate': _ymd(_due),
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': _me(),
        });
      }
      await batch.commit();
      Audit.log('fee.create', target: 'app2_fees', details: {'title': _title.text.trim(), 'amount': amt, 'students': list.length, 'target': _target});
      if (mounted) Navigator.pop(context, 'Fee added for ${list.length} student${list.length == 1 ? '' : 's'}.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = 'Could not save (${e is FirebaseException ? e.code : e}).';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add fee', style: serif(22)),
            const SizedBox(height: 12),
            const Text('Charge', style: TextStyle(color: kMuted, fontSize: 12.5)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, children: [
              for (final o in [('one', 'One student'), for (final b in kBuses) (b.id, 'All of ${b.label}'), ('all', 'Everyone')])
                ChoiceChip(label: Text(o.$2), selected: _target == o.$1, onSelected: (_) => setState(() => _target = o.$1)),
            ]),
            const SizedBox(height: 10),
            if (_target == 'one')
              Autocomplete<_Stu>(
                displayStringForOption: (s) => '${s.name}${s.admissionNo.isEmpty ? '' : ' (${s.admissionNo})'}',
                optionsBuilder: (v) {
                  final q = v.text.trim().toLowerCase();
                  if (q.isEmpty) return const Iterable<_Stu>.empty();
                  return widget.students.where((s) => s.name.toLowerCase().contains(q) || s.admissionNo.toLowerCase().contains(q)).take(8);
                },
                onSelected: (s) => setState(() => _picked = s),
                fieldViewBuilder: (c, ctl, fn, onSub) => TextField(
                  controller: ctl,
                  focusNode: fn,
                  decoration: const InputDecoration(labelText: 'Student (type name or admission no)'),
                ),
              )
            else
              Text('${_targets.length} students will be charged.', style: const TextStyle(color: kMuted)),
            const SizedBox(height: 10),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Fee name (e.g. Term 1 bus fee)')),
            const SizedBox(height: 10),
            TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text('Due date: ${_nice(_ymd(_due))}'),
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _due, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setState(() => _due = d);
              },
            ),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: kRed))),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kYellow, foregroundColor: kOnGold, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving...' : 'Save fee'),
              ),
            ),
          ]),
        ),
      );
}

/// One fee: its payments, a form to record a payment, receipts and cancel.
class _FeeSheet extends StatefulWidget {
  final _Fee fee;
  const _FeeSheet({required this.fee});
  @override
  State<_FeeSheet> createState() => _FeeSheetState();
}

class _FeeSheetState extends State<_FeeSheet> {
  final _amt = TextEditingController();
  final _note = TextEditingController();
  String _mode = _modes.first;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _amt.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _record(int balance, int paidSoFar) async {
    final amt = int.tryParse(_amt.text.trim()) ?? 0;
    if (amt <= 0) return setState(() => _err = 'Enter the amount received.');
    if (amt > balance) return setState(() => _err = 'The amount is more than the balance (${rupee(balance)}).');
    setState(() {
      _busy = true;
      _err = null;
    });
    final f = widget.fee;
    try {
      final counter = db.doc('app2_counters/receipt');
      final payRef = db.collection('app2_payments').doc();
      var receipt = '';
      await db.runTransaction((tx) async {
        final s = await tx.get(counter);
        final n = ((s.data()?['n'] as num?)?.toInt() ?? 0) + 1;
        receipt = 'RC-${n.toString().padLeft(5, '0')}';
        tx.set(counter, {'n': n});
        tx.set(payRef, {
          'feeId': f.id,
          'feeTitle': f.title,
          'studentKey': f.studentKey,
          'studentName': f.name,
          'admissionNo': f.admissionNo,
          'className': f.className,
          'bus': f.bus,
          'amount': amt,
          'mode': _mode,
          'note': _note.text.trim(),
          'receiptNo': receipt,
          'paidOn': _ymd(DateTime.now()),
          'voided': false,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': _me(),
        });
      });
      Audit.log('payment.record', target: 'app2_payments', targetId: payRef.id, details: {'receipt': receipt, 'amount': amt, 'feeId': f.id, 'student': f.name});
      _amt.clear();
      _note.clear();
      if (mounted) {
        setState(() => _busy = false);
        _snack(context, 'Payment saved. Receipt $receipt.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = 'Could not save (${e is FirebaseException ? e.code : e}).';
      });
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
          ],
        ),
      ) ??
      false;

  Future<void> _void(_Pay p) async {
    if (!await _confirm('Void this payment?', '${p.receiptNo}  ${rupee(p.amount)}\nIt stays in the history but no longer counts as received.')) return;
    await db.doc('app2_payments/${p.id}').update({'voided': true, 'voidedAt': FieldValue.serverTimestamp(), 'voidedBy': _me()});
    Audit.log('payment.void', target: 'app2_payments', targetId: p.id, details: {'receipt': p.receiptNo, 'amount': p.amount});
  }

  Future<void> _cancelFee(int paid) async {
    if (paid > 0) return setState(() => _err = 'Void the payments first, then cancel the fee.');
    if (!await _confirm('Cancel this fee?', 'It will no longer appear in the fees list.')) return;
    await db.doc('app2_fees/${widget.fee.id}').update({'status': 'cancelled', 'cancelledAt': FieldValue.serverTimestamp(), 'cancelledBy': _me()});
    Audit.log('fee.cancel', target: 'app2_fees', targetId: widget.fee.id, details: {'title': widget.fee.title, 'student': widget.fee.name});
    if (mounted) Navigator.pop(context);
  }

  Future<void> _receipt(_Pay p, int paid) => PdfService.shareReceipt(
        receiptNo: p.receiptNo,
        date: _nice(p.paidOn),
        student: widget.fee.name,
        admissionNo: widget.fee.admissionNo,
        className: widget.fee.className,
        bus: busInfo(widget.fee.bus).label,
        feeTitle: widget.fee.title,
        feeAmount: widget.fee.amount,
        amount: p.amount,
        paidToDate: paid,
        mode: p.mode,
        note: p.note,
      );

  @override
  Widget build(BuildContext context) {
    final f = widget.fee;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('app2_payments').where('feeId', isEqualTo: f.id).snapshots(),
        builder: (c, s) {
          final pays = <_Pay>[for (final d in s.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]) _Pay(d.id, d.data())];
          pays.sort((a, b) => a.paidOn.compareTo(b.paidOn));
          final paid = pays.where((p) => !p.voided).fold<int>(0, (a, p) => a + p.amount);
          final balance = f.amount - paid;
          return SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.name, style: serif(22)),
              Text('${f.title}  •  ${busInfo(f.bus).label}${f.admissionNo.isEmpty ? '' : '  •  ${f.admissionNo}'}', style: const TextStyle(color: kMuted)),
              const SizedBox(height: 12),
              Row(children: [
                _Total('Fee', rupee(f.amount), kBlue),
                const SizedBox(width: 8),
                _Total('Paid', rupee(paid), kGreen),
                const SizedBox(width: 8),
                _Total('Balance', rupee(balance), balance > 0 ? kAmber : kGreen),
              ]),
              const SizedBox(height: 4),
              Text('Due ${_nice(f.dueDate)}', style: const TextStyle(color: kMuted, fontSize: 12.5)),
              if (balance > 0) ...[
                const SectionLabel('Record payment'),
                TextField(controller: _amt, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Amount received (₹)', hintText: 'Balance ${rupee(balance)}')),
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [
                  for (final m in _modes) ChoiceChip(label: Text(m), selected: _mode == m, onSelected: (_) => setState(() => _mode = m)),
                ]),
                const SizedBox(height: 8),
                TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kYellow, foregroundColor: kOnGold, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _busy ? null : () => _record(balance, paid),
                    child: Text(_busy ? 'Saving...' : 'Save payment'),
                  ),
                ),
              ],
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: kRed))),
              const SectionLabel('Payments'),
              if (pays.isEmpty) const Text('No payment yet.', style: TextStyle(color: kMuted)),
              for (final p in pays)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${p.receiptNo}  •  ${_nice(p.paidOn)}  •  ${p.mode}\n${rupee(p.amount)}${p.voided ? '  (voided)' : ''}',
                        style: TextStyle(color: p.voided ? kMuted : kInk, decoration: p.voided ? TextDecoration.lineThrough : null, fontSize: 13),
                      ),
                    ),
                    if (!p.voided) ...[
                      IconButton(tooltip: 'Receipt PDF', icon: const Icon(Icons.picture_as_pdf_rounded, color: kYellow), onPressed: () => _receipt(p, paid)),
                      IconButton(tooltip: 'Void payment', icon: const Icon(Icons.block_rounded, color: kRed), onPressed: () => _void(p)),
                    ],
                  ]),
                ),
              const SizedBox(height: 8),
              TextButton.icon(onPressed: () => _cancelFee(paid), icon: const Icon(Icons.cancel_outlined, color: kRed), label: const Text('Cancel this fee', style: TextStyle(color: kRed))),
            ]),
          );
        },
      ),
    );
  }
}
