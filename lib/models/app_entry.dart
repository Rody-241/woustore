import 'package:flutter/material.dart';

/// Une appli du catalogue (fichier catalog.json du dépôt GitHub).
class AppEntry {
  AppEntry({
    required this.id,
    required this.name,
    required this.developer,
    required this.tagline,
    required this.category,
    required this.icon,
    required this.color,
    required this.github,
    required this.assetPattern,
    required this.android,
    required this.featured,
    required this.openSource,
    this.hidden = false,
    this.assetsByAbi = const {},
    this.ageRating,
    this.dataCollected = const [],
    this.dataShared = false,
    this.privacyUrl,
    required this.description,
    required this.screenshots,
    required this.iconUrl,
  });

  static const iconBase =
      'https://raw.githubusercontent.com/Rody-241/woustore/main/icons';
  static const metaBase =
      'https://raw.githubusercontent.com/Rody-241/woustore/main/meta';

  /// Nom du paquet Android, par exemple com.wifensor.wifensor.
  final String id;
  final String name;
  final String developer;
  final String tagline;
  final String category;
  final String icon;
  final Color color;

  /// Dépôt GitHub qui publie l'APK (propriétaire/nom).
  final String github;

  /// Expression qui reconnaît le bon fichier .apk dans la dernière version.
  final String assetPattern;
  final String android;
  final bool featured;
  final bool openSource;

  /// Fichier à prendre selon le type de téléphone, ex. {"armeabi-v7a": "-32bit\\.apk$"}.
  final Map<String, String> assetsByAbi;

  /// Classification par âge (all, 12, 16, 18) et données collectées, déclarées par le développeur.
  final String? ageRating;
  final List<String> dataCollected;
  final bool dataShared;
  final String? privacyUrl;

  /// Retirée du magasin (signalements, ou version dangereuse sans version saine).
  bool blocked = false;

  /// Fiche cachée de la liste (WouStore lui-même, pour ses mises à jour).
  final bool hidden;
  final String description;
  final List<String> screenshots;

  /// Le logo officiel de l'appli (PNG). Par défaut : icons/<id>.png du dépôt WouStore,
  /// extrait automatiquement de l'APK publié par le créateur.
  final String iconUrl;

  // Rempli après lecture de la dernière version sur GitHub.
  String? downloadUrl;
  int? size;
  String? latestVersion;
  String? resolveError;
  String? releaseNotes;

  /// Vidéo d'aperçu : champ « video » du catalogue, sinon le fichier .mp4/.webm
  /// joint par le créateur à sa dernière version sur GitHub.
  String? videoUrl;
  int? videoSize;
  DateTime? updatedAt;

  // Lu dans meta/<id>.json (extrait automatiquement de l'APK).
  List<String>? permissions;
  int? minSdk;

  /// Numéro de version de la dernière version publiée.
  int? versionCode;

  /// Empreinte (SHA-256) du certificat qui signe l'APK publié.
  String? cert;

  /// Analyse VirusTotal du fichier publié : done / pending / disabled / error.
  String? scanStatus;
  int? scanMalicious;
  int? scanEngines;
  String? scanLink;

  factory AppEntry.fromJson(Map<String, dynamic> j) {
    return AppEntry(
      id: j['id'] as String,
      name: j['name'] as String,
      developer: (j['developer'] ?? '') as String,
      tagline: (j['tagline'] ?? '') as String,
      category: (j['category'] ?? '') as String,
      icon: (j['icon'] ?? 'apps') as String,
      color: _parseColor((j['color'] ?? '#3DDC97') as String),
      github: j['github'] as String,
      assetPattern: (j['asset'] ?? r'\.apk$') as String,
      android: (j['android'] ?? '') as String,
      featured: (j['featured'] ?? false) as bool,
      openSource: (j['openSource'] ?? false) as bool,
      hidden: (j['hidden'] ?? false) as bool,
      assetsByAbi: Map<String, String>.from((j['assetsByAbi'] ?? const {}) as Map),
      ageRating: j['ageRating'] as String?,
      dataCollected: ((j['dataCollected'] ?? const []) as List).cast<String>(),
      dataShared: (j['dataShared'] ?? false) as bool,
      privacyUrl: j['privacyUrl'] as String?,
      description: (j['description'] ?? '') as String,
      screenshots: ((j['screenshots'] ?? const []) as List).cast<String>(),
      iconUrl: (j['iconUrl'] as String?) ?? '$iconBase/${j['id']}.png',
    )..videoUrl = j['video'] as String?;
  }

  static Color _parseColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x3DDC97;
    return Color(0xFF000000 | v);
  }

  /// « Android 7.0 et plus », d'après l'APK, sinon d'après le catalogue.
  String get androidLabel {
    const names = {
      21: '5.0', 22: '5.1', 23: '6.0', 24: '7.0', 25: '7.1', 26: '8.0', 27: '8.1',
      28: '9', 29: '10', 30: '11', 31: '12', 32: '12L', 33: '13', 34: '14', 35: '15', 36: '16',
    };
    final n = minSdk == null ? null : names[minSdk];
    if (n != null) return 'Android $n+';
    return android.isEmpty ? '—' : 'Android $android';
  }

  String get categoryLine =>
      openSource ? '$category · Open source' : category;
}
