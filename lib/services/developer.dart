import 'package:cloud_firestore/cloud_firestore.dart';

/// Lecture des applis publiées par les développeurs et des applis retirées.
/// L'inscription et la publication se font sur le site développeur, pas dans l'appli.
class DevSpace {
  static final _db = FirebaseFirestore.instance;

  static const siteUrl = 'https://rody-241.github.io/woustore/dev/';

  /// Les applis validées (publiées par des développeurs), lues par tout le monde.
  static Future<List<Map<String, dynamic>>> publishedApps() async {
    final q = await _db.collection('apps').get();
    return q.docs.map((d) => {...d.data(), 'id': d.id}).toList();
  }

  /// Les applis retirées après signalements.
  static Future<Set<String>> blockedApps() async {
    final q = await _db.collection('moderation').where('blocked', isEqualTo: true).get();
    return q.docs.map((d) => d.id).toSet();
  }

  /// Signaler une appli (une fois par personne).
  static Future<void> report(String appId, String uid, String reason) =>
      _db.collection('reports').doc(appId).collection('items').doc(uid).set({
        'reason': reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
}
