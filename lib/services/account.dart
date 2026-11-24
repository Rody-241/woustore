import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Le projet Firebase de WouStore (valeurs publiques, tirées de google-services.json).
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBbEay6vUZU9nCraZ3pZCmKpbMsweJ4aOM',
  appId: '1:709382251864:android:9d2f16d1bfcecd7581b12d',
  messagingSenderId: '709382251864',
  projectId: 'woustore-c9e0b',
  storageBucket: 'woustore-c9e0b.firebasestorage.app',
);

/// Identifiant « web » demandé par Google pour la connexion depuis Android.
const _serverClientId =
    '709382251864-e6ilrht8qjmic7pjoj36sshq6tf3k5t3.apps.googleusercontent.com';

/// Le compte de l'utilisateur : connexion Google par Firebase.
class Account extends ChangeNotifier {
  Account._();
  static final Account i = Account._();

  bool ready = false;

  final _initDone = Completer<void>();

  /// Terminé quand Firebase est prêt (ou a échoué).
  Future<void> get initDone => _initDone.future;
  User? user;
  String? error;
  bool busy = false;

  Future<void> init() async {
    try {
      await Firebase.initializeApp(options: firebaseOptions);
      await GoogleSignIn.instance.initialize(serverClientId: _serverClientId);
      user = FirebaseAuth.instance.currentUser;
      FirebaseAuth.instance.authStateChanges().listen((u) {
        user = u;
        notifyListeners();
      });
      ready = true;
    } catch (e) {
      error = 'Connexion indisponible : $e';
    }
    if (!_initDone.isCompleted) _initDone.complete();
    notifyListeners();
  }

  String get name => user?.displayName ?? user?.email?.split('@').first ?? 'Utilisateur';

  Future<bool> signIn() async {
    if (!ready || busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      final cred = GoogleAuthProvider.credential(idToken: idToken);
      await FirebaseAuth.instance.signInWithCredential(cred);
      user = FirebaseAuth.instance.currentUser;
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        error = 'La connexion Google a échoué (${e.code.name}).';
      }
      return false;
    } catch (e) {
      error = 'La connexion a échoué : $e';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    await FirebaseAuth.instance.signOut();
    user = null;
    notifyListeners();
  }
}

/// Un avis laissé sur une appli.
class Review {
  Review({
    required this.uid,
    required this.name,
    required this.rating,
    required this.text,
    required this.updatedAt,
    this.version,
  });

  final String uid;
  final String name;
  final int rating;
  final String text;
  final DateTime? updatedAt;
  final String? version;

  factory Review.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Review(
      uid: d.id,
      name: (m['name'] as String?) ?? 'Utilisateur',
      rating: (m['rating'] as num?)?.toInt() ?? 0,
      text: (m['text'] as String?) ?? '',
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
      version: m['version'] as String?,
    );
  }
}

/// Résumé des notes : moyenne, nombre, répartition 5★ → 1★.
class RatingSummary {
  RatingSummary(this.average, this.count, this.byStars);

  final double average;
  final int count;
  final Map<int, int> byStars;
}

/// Lecture et écriture des avis dans Firestore :
/// reviews/{idAppli}/items/{idUtilisateur} — un seul avis par personne et par appli.
class Reviews {
  static CollectionReference<Map<String, dynamic>> _items(String appId) =>
      FirebaseFirestore.instance.collection('reviews').doc(appId).collection('items');

  static Future<RatingSummary> summary(String appId) async {
    final col = _items(appId);
    final agg = await col.aggregate(count(), average('rating')).get();
    final total = agg.count ?? 0;
    final byStars = <int, int>{};
    if (total > 0) {
      for (var s = 5; s >= 1; s--) {
        final c = await col.where('rating', isEqualTo: s).count().get();
        byStars[s] = c.count ?? 0;
      }
    }
    return RatingSummary(agg.getAverage('rating') ?? 0, total, byStars);
  }

  static Future<List<Review>> latest(String appId, {int limit = 20}) async {
    final q = await _items(appId).orderBy('updatedAt', descending: true).limit(limit).get();
    return q.docs.map(Review.fromDoc).where((r) => r.text.isNotEmpty).toList();
  }

  static Future<Review?> mine(String appId) async {
    final u = Account.i.user;
    if (u == null) return null;
    final d = await _items(appId).doc(u.uid).get();
    return d.exists ? Review.fromDoc(d) : null;
  }

  static Future<void> save(String appId, int rating, String text, String? version) async {
    final u = Account.i.user;
    if (u == null) throw StateError('Pas connecté');
    final ref = _items(appId).doc(u.uid);
    final existing = await ref.get();
    await ref.set({
      'name': Account.i.name,
      'rating': rating,
      'text': text.trim(),
      'version': version ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
      if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> delete(String appId, String uid) => _items(appId).doc(uid).delete();
}
