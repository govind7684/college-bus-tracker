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

const _expenseCats = ['Fuel', 'Maintenance', 'Repairs', 'Salary', 'Insurance', 'Tax', 'Other'];
const _receivedCats = ['Donation', 'Grant', 'Other'];

/// One line of the statement: a fee payment (from app2_payments) or a manual entry (app2_ledger).
class _Entry {
  final String date, type, title, category, party;
  final int amount;
  final String? ledgerId; // null for fee payments
  _Entry(this.date, this.type, this.title, this.category, this.party, this.amount, this.ledgerId);
  bool get received => type == 'received';
}

/// Money received and expenses for a date range, with a PDF statement.
/// Fee payments recorded in the Fees screen appear here automatically as "received".
class AccountsAdmin extends StatefulWidget {
  const AccountsAdmin({super.key});
  @override
  State<AccountsAdmin> createState() => _AccountsAdminState();
}

class _AccountsAdminState extends State<AccountsAdmin> {
  late DateTimeRange _range = _thisMonth();
  String _type = 'all'; // all | received | expense
  List<_Entry> _shown = const [];

  static DateTimeRange _thisMonth() {
    final n = DateTime.now();
    return DateTimeRange(start: DateTime(n.year, n.month, 1), end: DateTime(n.year, n.month + 1, 0));
  }

  Future<void> _pick() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDateRange: _range);
    if (r != null) setState(() => _range = r);
  }

  String get _rangeText => '${_nice(_ymd(_range.start))} to ${_nice(_ymd(_range.end))}';

  Future<void> _add() async {
    final msg = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => const _EntrySheet(),
    );
    if (msg != null && mounted) _snack(context, msg);
  }

  Future<void> _tap(_Entry e) async {
    if (e.ledgerId == null) {
      _snack(context, 'Fee payments are managed in the Fees screen.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Void this entry?'),
        content: Text('${e.title}\n${rupee(e.amount)}\nIt stays in the history but no longer counts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Void')),
        ],
      ),
    );
    if (ok != true) return;
    await db.doc('app2_ledger/${e.ledgerId}').update({'voided': true, 'voidedAt': FieldValue.serverTimestamp(), 'voidedBy': _me()});
    Audit.log('ledger.void', target: 'app2_ledger', targetId: e.ledgerId, details: {'title': e.title, 'amount': e.amount});
  }

  Future<void> _pdf() async {
    if (_shown.isEmpty) {
      _snack(context, 'Nothing to export.');
      return;
    }
    final rec = _shown.where((e) => e.received).fold<int>(0, (a, e) => a + e.amount);
    final exp = _shown.where((e) => !e.received).fold<int>(0, (a, e) => a + e.amount);
    await PdfService.shareTable(
      fileName: 'accounts_${_ymd(_range.start)}_to_${_ymd(_range.end)}.pdf',
      title: 'Received and expenses',
      subtitle: _rangeText,
      headers: const ['Date', 'Type', 'Details', 'Category', 'Paid by / to', 'Received', 'Expense'],
      rows: [
        for (final e in _shown) [_nice(e.date), e.received ? 'Received' : 'Expense', e.title, e.category, e.party, e.received ? rs(e.amount) : '', e.received ? '' : rs(e.amount)],
      ],
      summary: [
        ['Total received', rs(rec)],
        ['Total expenses', rs(exp)],
        ['Balance', rs(rec - exp)],
      ],
    );
    Audit.log('ledger.report_pdf', target: 'app2_ledger', details: {'from': _ymd(_range.start), 'to': _ymd(_range.end), 'rows': _shown.length});
  }

  @override
  Widget build(BuildContext context) {
    final from = _ymd(_range.start), to = _ymd(_range.end);
    return Scaffold(
      appBar: AppBar(
        title: Text('Received & expenses', style: serif(22)),
        actions: [IconButton(tooltip: 'PDF statement', icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: _pdf)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kYellow,
        foregroundColor: kOnGold,
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add entry'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('app2_ledger').where('date', isGreaterThanOrEqualTo: from).where('date', isLessThanOrEqualTo: to).snapshots(),
        builder: (c, ls) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('app2_payments').where('paidOn', isGreaterThanOrEqualTo: from).where('paidOn', isLessThanOrEqualTo: to).snapshots(),
          builder: (c, ps) {
            if (ls.hasError || ps.hasError) {
              return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Could not load the accounts. Check the connection and publish the updated Firestore rules.', textAlign: TextAlign.center, style: TextStyle(color: kRed))));
            }
            if (!ls.hasData || !ps.hasData) return const Center(child: CircularProgressIndicator());
            final all = <_Entry>[
              for (final d in ps.data!.docs)
                if (d.data()['voided'] != true)
                  _Entry(
                    (d.data()['paidOn'] ?? '').toString(),
                    'received',
                    'Fee: ${d.data()['feeTitle'] ?? ''} - ${d.data()['studentName'] ?? ''}',
                    'Fees',
                    (d.data()['mode'] ?? '').toString(),
                    (d.data()['amount'] as num?)?.toInt() ?? 0,
                    null,
                  ),
              for (final d in ls.data!.docs)
                if (d.data()['voided'] != true)
                  _Entry(
                    (d.data()['date'] ?? '').toString(),
                    (d.data()['type'] ?? 'expense').toString(),
                    (d.data()['title'] ?? '').toString(),
                    (d.data()['category'] ?? '').toString(),
                    (d.data()['party'] ?? '').toString(),
                    (d.data()['amount'] as num?)?.toInt() ?? 0,
                    d.id,
                  ),
            ];
            all.sort((a, b) => b.date.compareTo(a.date));
            final rec = all.where((e) => e.received).fold<int>(0, (a, e) => a + e.amount);
            final exp = all.where((e) => !e.received).fold<int>(0, (a, e) => a + e.amount);
            _shown = _type == 'all' ? all : all.where((e) => _type == 'received' ? e.received : !e.received).toList();
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.date_range_rounded), label: Text(_rangeText, overflow: TextOverflow.ellipsis), onPressed: _pick)),
                    const SizedBox(width: 8),
                    TextButton(onPressed: () => setState(() => _range = _thisMonth()), child: const Text('This month')),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    for (final o in const [('all', 'All'), ('received', 'Received'), ('expense', 'Expenses')])
                      Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(o.$2), selected: _type == o.$1, onSelected: (_) => setState(() => _type = o.$1))),
                  ]),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  _Tile('Received', rupee(rec), kGreen),
                  const SizedBox(width: 8),
                  _Tile('Expenses', rupee(exp), kRed),
                  const SizedBox(width: 8),
                  _Tile('Balance', rupee(rec - exp), rec - exp >= 0 ? kBlue : kAmber),
                ]),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _shown.isEmpty
                    ? const Center(child: Text('No entries in this period.', style: TextStyle(color: kMuted)))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                        itemCount: _shown.length,
                        itemBuilder: (c, i) {
                          final e = _shown[i];
                          final col = e.received ? kGreen : kRed;
                          return Card2(
                            onTap: () => _tap(e),
                            child: Row(children: [
                              Icon(e.received ? Icons.south_west_rounded : Icons.north_east_rounded, color: col),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  Text('${_nice(e.date)}  •  ${e.category}${e.party.isEmpty ? '' : '  •  ${e.party}'}', style: const TextStyle(color: kMuted, fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ]),
                              ),
                              Text('${e.received ? '+' : '-'}${rupee(e.amount)}', style: TextStyle(color: col, fontWeight: FontWeight.w800)),
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
}

class _Tile extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Tile(this.label, this.value, this.color);
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

/// Add a manual expense or a manual "received" entry (donation, grant, ...).
class _EntrySheet extends StatefulWidget {
  const _EntrySheet();
  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  String _type = 'expense';
  String _cat = _expenseCats.first;
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _party = TextEditingController();
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _party.dispose();
    super.dispose();
  }

  List<String> get _cats => _type == 'expense' ? _expenseCats : _receivedCats;

  Future<void> _save() async {
    final amt = int.tryParse(_amount.text.trim()) ?? 0;
    if (_title.text.trim().isEmpty) return setState(() => _err = 'Enter what this is for.');
    if (amt <= 0) return setState(() => _err = 'Enter the amount in rupees.');
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final ref = await db.collection('app2_ledger').add({
        'type': _type,
        'title': _title.text.trim(),
        'category': _cat,
        'party': _party.text.trim(),
        'amount': amt,
        'date': _ymd(_date),
        'voided': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _me(),
      });
      Audit.log('ledger.create', target: 'app2_ledger', targetId: ref.id, details: {'type': _type, 'title': _title.text.trim(), 'amount': amt});
      if (mounted) Navigator.pop(context, _type == 'expense' ? 'Expense saved.' : 'Received entry saved.');
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
            Text('Add entry', style: serif(22)),
            const SizedBox(height: 12),
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('Expense'), selected: _type == 'expense', onSelected: (_) => setState(() { _type = 'expense'; _cat = _expenseCats.first; })),
              ChoiceChip(label: const Text('Received'), selected: _type == 'received', onSelected: (_) => setState(() { _type = 'received'; _cat = _receivedCats.first; })),
            ]),
            const SizedBox(height: 10),
            TextField(controller: _title, decoration: InputDecoration(labelText: _type == 'expense' ? 'What was it for? (e.g. Diesel Bus 1)' : 'Details (e.g. Alumni donation)')),
            const SizedBox(height: 10),
            TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (₹)')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _cat,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final c in _cats) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _cat = v ?? _cats.first),
            ),
            const SizedBox(height: 10),
            TextField(controller: _party, decoration: InputDecoration(labelText: _type == 'expense' ? 'Paid to (optional)' : 'Received from (optional)')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded),
              label: Text('Date: ${_nice(_ymd(_date))}'),
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setState(() => _date = d);
              },
            ),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: kRed))),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kYellow, foregroundColor: kOnGold, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Saving...' : 'Save entry'),
              ),
            ),
          ]),
        ),
      );
}
