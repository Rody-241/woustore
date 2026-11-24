import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'account.dart';

/// État d'une inscription ou d'une appli soumise.
enum Review3 { pending, approved, rejected }

Review3 _status(String? s) => switch (s) {
      'approved' => Review3.approved,
      'rejected' => Review3.rejected,
      _ => Review3.pending,
    };

/// Un développeur inscrit sur WouStore : developers/{uid}.
class Developer {
  Developer({
    required this.uid,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.status,
    this.reason,
    this.createdAt,
  });

  final String uid;
  final String fullName;
  final String phone;
  final String email;
  final Review3 status;
  final String? reason;
  final DateTime? createdAt;

  factory Developer.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Developer(
      uid: d.id,
      fullName: (m['fullName'] ?? '') as String,
      phone: (m['phone'] ?? '') as String,
      email: (m['email'] ?? '') as String,
      status: _status(m['status'] as String?),
      reason: m['reason'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Une appli proposée par un développeur : submissions/{id}.
class Submission {
  Submission({
    required this.id,
    required this.uid,
    required this.data,
    required this.status,
    this.reason,
    this.createdAt,
  });

  final String id;
  final String uid;

  /// Les mêmes champs qu'une appli du catalogue (name, id, github, category…).
  final Map<String, dynamic> data;
  final Review3 status;
  final String? reason;
  final DateTime? createdAt;

  String get name => (data['name'] ?? '') as String;
  String get package => (data['id'] ?? '') as String;
  String get github => (data['github'] ?? '') as String;

  factory Submission.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Submission(
      id: d.id,
      uid: (m['uid'] ?? '') as String,
      data: Map<String, dynamic>.from((m['app'] ?? const {}) as Map),
      status: _status(m['status'] as String?),
      reason: m['reason'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Tout ce qui concerne l'espace développeur et l'administration, dans Firestore.
class DevSpace {
  static final _db = FirebaseFirestore.instance;

  static String? get _uid => Account.i.user?.uid;

  // ---------- Développeur ----------

  static Future<Developer?> me() async {
    final uid = _uid;
    if (uid == null) return null;
    final d = await _db.collection('developers').doc(uid).get();
    return d.exists ? Developer.fromDoc(d) : null;
  }

  /// Inscription : la fiche, puis la photo de la pièce d'identité (rangée à part,
  /// lisible seulement par le développeur lui-même et par l'administrateur).
  static Future<void> register({
    required String fullName,
    required String phone,
    required Uint8List idPhotoJpeg,
  }) async {
    final uid = _uid!;
    await _db.collection('developer_ids').doc(uid).set({
      'image': base64Encode(idPhotoJpeg),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('developers').doc(uid).set({
      'fullName': fullName.trim(),
      'phone': phone.trim(),
      'email': Account.i.user?.email ?? '',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<List<Submission>> mySubmissions() async {
    final uid = _uid;
    if (uid == null) return const [];
    final q = await _db.collection('submissions').where('uid', isEqualTo: uid).get();
    final list = q.docs.map(Submission.fromDoc).toList();
    list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return list;
  }

  static Future<void> submit(Map<String, dynamic> app) async {
    final ref = _db.collection('submissions').doc();
    final batch = _db.batch();
    batch.set(ref, {
      'uid': _uid,
      'app': app,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Pour l'analyse anti-virus automatique : seulement le dépôt, rien de personnel.
    batch.set(_db.collection('submission_queue').doc(ref.id), {
      'github': app['github'],
      'asset': app['asset'],
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Les applis validées (publiées par des développeurs), lues par tout le monde.
  static Future<List<Map<String, dynamic>>> publishedApps() async {
    final q = await _db.collection('apps').get();
    return q.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }
}
