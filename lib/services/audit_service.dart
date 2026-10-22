import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Append-only audit trail (`app2_audit`). Every important change (account, assignment, route, fee, payment,
/// refund, expense, document) calls [Audit.log]. Who / when / what record / what changed are stored;
/// passwords, tokens and other secrets are never stored (they are stripped from `details`).
class Audit {
  static const _secret = ['pass', 'secret', 'token', 'key', 'pin'];

  static Object? _clean(Object? v) {
    if (v is Map) {
      return {
        for (final e in v.entries)
          if (!_secret.any((s) => e.key.toString().toLowerCase().contains(s))) e.key.toString(): _clean(e.value),
      };
    }
    if (v is Iterable) return v.map(_clean).toList();
    if (v is num || v is bool || v == null) return v;
    return v.toString();
  }

  /// [action] e.g. 'student.create', 'payment.record'; [target] the collection, [targetId] the record id.
  /// Never throws: a failing audit write must not block the real work.
  static Future<void> log(String action, {String? target, String? targetId, Map<String, dynamic>? details}) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await FirebaseFirestore.instance.collection('app2_audit').add({
        'action': action,
        'target': target,
        'targetId': targetId,
        'details': _clean(details ?? const {}),
        'actorUid': u.uid,
        'actorEmail': u.email,
        'at': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> recent({int limit = 50}) =>
      FirebaseFirestore.instance.collection('app2_audit').orderBy('at', descending: true).limit(limit).snapshots();
}
