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
    required this.description,
    required this.screenshots,
    required this.iconUrl,
  });

  static const iconBase =
      'https://raw.githubusercontent.com/Rody-241/woustore/main/icons';

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
      description: (j['description'] ?? '') as String,
      screenshots: ((j['screenshots'] ?? const []) as List).cast<String>(),
      iconUrl: (j['iconUrl'] as String?) ?? '$iconBase/${j['id']}.png',
    );
  }

  static Color _parseColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0x3DDC97;
    return Color(0xFF000000 | v);
  }

  String get categoryLine =>
      openSource ? '$category · Open source' : category;
}
