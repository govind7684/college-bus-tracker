import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';

/// Optional student profile picture.
/// The photo is shrunk to about 384 px and stored as text (`photoB64`) in the student's own document
/// (app2_students/<uid>), so no Firebase Storage plan is needed. A student without a photo keeps the
/// letter avatar.
class PhotoService {
  /// Returns null when saved (or cancelled), otherwise an error message.
  static Future<String?> pick(ImageSource source) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return 'Please log in again.';
    try {
      final x = await ImagePicker().pickImage(source: source, maxWidth: 384, maxHeight: 384, imageQuality: 70);
      if (x == null) return null; // cancelled
      final bytes = await x.readAsBytes();
      final b64 = base64Encode(bytes);
      if (b64.length > 200000) return 'The photo is too large. Choose a smaller one.';
      await FirebaseFirestore.instance.doc('app2_students/${u.uid}').update({
        'photoB64': b64,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      return 'Could not save the photo (${e is FirebaseException ? e.code : e}).';
    }
  }

  static Future<String?> remove() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return 'Please log in again.';
    try {
      await FirebaseFirestore.instance.doc('app2_students/${u.uid}').update({
        'photoB64': FieldValue.delete(),
        'photoUpdatedAt': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (e) {
      return 'Could not remove the photo (${e is FirebaseException ? e.code : e}).';
    }
  }
}

/// Round avatar: the photo when there is one, otherwise the first letter of the name.
class PhotoAvatar extends StatelessWidget {
  final String name;
  final String? photoB64;
  final double radius;
  final bool editable;
  const PhotoAvatar({super.key, required this.name, this.photoB64, this.radius = 40, this.editable = false});

  Uint8List? get _bytes {
    final s = photoB64;
    if (s == null || s.isEmpty) return null;
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> _menu(BuildContext context) async {
    final msg = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kBg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(leading: const Icon(Icons.photo_camera_rounded, color: kYellow), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_rounded, color: kYellow), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, 'gallery')),
          if (_bytes != null) ListTile(leading: const Icon(Icons.delete_outline_rounded, color: kRed), title: const Text('Remove photo'), onTap: () => Navigator.pop(context, 'remove')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null) return;
    final err = choice == 'remove' ? await PhotoService.remove() : await PhotoService.pick(choice == 'camera' ? ImageSource.camera : ImageSource.gallery);
    if (err != null) msg.showSnackBar(SnackBar(content: Text(err)));
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: kYellow,
      backgroundImage: b == null ? null : MemoryImage(b),
      child: b == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: serif(radius * 0.85, color: kOnGold)) : null,
    );
    if (!editable) return avatar;
    return GestureDetector(
      onTap: () => _menu(context),
      child: Stack(clipBehavior: Clip.none, children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: kBg2, shape: BoxShape.circle, border: Border.all(color: kYellow, width: 1.5)),
            child: const Icon(Icons.photo_camera_rounded, size: 15, color: kYellow),
          ),
        ),
      ]),
    );
  }
}
