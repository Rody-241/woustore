import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/app_entry.dart';

enum Phase { idle, downloading, installing, installed, error }

class AppState {
  Phase phase = Phase.idle;
  double progress = 0;
  int received = 0;
  int total = 0;
  String? installedVersion;
  int? installedCode;
  DateTime? installedAt;
  String? error;

  bool get busy => phase == Phase.downloading || phase == Phase.installing;
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// Le cœur de WouStore : catalogue, téléchargements et installations.
class Store extends ChangeNotifier {
  Store._();
  static final Store i = Store._();

  static const _ch = MethodChannel('woustore/installer');
  static const catalogUrl =
      'https://raw.githubusercontent.com/Rody-241/woustore/main/catalog.json';

  List<AppEntry> apps = [];
  bool loading = true;
  String? loadError;

  /// absent | off | ask | old | ready
  String shizuku = 'absent';

  /// Icônes réelles des applis installées (lues sur le téléphone).
  final Map<String, Uint8List> iconBytes = {};
  Completer<void>? _shizukuWait;

  final Map<String, AppState> _states = {};
  final Map<String, bool> _cancel = {};
  bool _started = false;

  AppState stateOf(String id) => _states.putIfAbsent(id, () => AppState());

  /// Les applis visibles dans le magasin (sans la fiche de WouStore lui-même).
  List<AppEntry> get visibleApps => apps.where((a) => !a.hidden).toList();

  List<AppEntry> get installedApps =>
      visibleApps.where((a) => stateOf(a.id).installedVersion != null).toList();

  String selfId = 'com.woustore.woustore';

  AppEntry? get selfApp {
    for (final a in apps) {
      if (a.id == selfId) return a;
    }
    return null;
  }

  /// Une version plus récente que celle installée est publiée.
  bool hasUpdate(AppEntry a) {
    final s = stateOf(a.id);
    if (s.installedVersion == null) return false;
    final latest = a.versionCode;
    final mine = s.installedCode;
    if (latest != null && mine != null) {
      if (latest > mine) return true;
      if (latest < mine) return false;
    }
    // Même numéro (ou inconnu) : on compare la date de publication à la date d'installation.
    final pub = a.updatedAt;
    final inst = s.installedAt;
    if (pub == null || inst == null) return false;
    return pub.isAfter(inst.add(const Duration(minutes: 10)));
  }

  List<AppEntry> get updates =>
      installedApps.where(hasUpdate).toList();

  bool get selfUpdate {
    final me = selfApp;
    return me != null && hasUpdate(me);
  }

  Future<void> updateAll() async {
    for (final a in updates) {
      await install(a);
    }
  }

  Future<void> uninstall(AppEntry a) async {
    await _ch.invokeMethod('uninstall', {'package': a.id, 'shizuku': shizuku == 'ready'});
  }

  Future<void> init() async {
    if (_started) return;
    _started = true;
    _ch.setMethodCallHandler(_onNative);
    selfId = await _ch.invokeMethod<String>('selfPackage') ?? selfId;
    await refreshShizuku();
    // Au lancement, seulement la demande de notifications du téléphone.
    await _ch.invokeMethod('askNotifications');
    await load();
  }

  Future<dynamic> _onNative(MethodCall call) async {
    switch (call.method) {
      case 'installResult':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        final id = m['package'] as String;
        final s = stateOf(id);
        if (m['ok'] == true) {
          await _refreshOne(id);
          s.phase = Phase.installed;
          s.error = null;
        } else {
          s.phase = Phase.error;
          s.error = (m['message'] as String?) ?? "L'installation a échoué.";
        }
        notifyListeners();
        break;
      case 'uninstallResult':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        await _refreshOne(m['package'] as String);
        notifyListeners();
        break;
      case 'shizukuChanged':
        await refreshShizuku();
        final w = _shizukuWait;
        if (w != null && !w.isCompleted && shizuku != 'ask') w.complete();
        break;
    }
    return null;
  }

  // ---------- Catalogue ----------

  Future<void> load() async {
    loading = true;
    loadError = null;
    notifyListeners();
    String raw;
    try {
      raw = await _getText(Uri.parse(catalogUrl));
    } catch (_) {
      // Pas de réseau : on utilise le catalogue livré avec l'appli.
      raw = await rootBundle.loadString('assets/catalog.json');
    }
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      apps = (j['apps'] as List)
          .map((e) => AppEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      loadError = 'Le catalogue est illisible.';
    }
    loading = false;
    notifyListeners();
    await refreshInstalled();
    await Future.wait([...apps.map(_resolve), ...apps.map(_loadMeta)]);
    notifyListeners();
  }

  Future<void> _loadMeta(AppEntry a) async {
    try {
      final j = jsonDecode(await _getText(
          Uri.parse('${AppEntry.metaBase}/${a.id}.json'))) as Map<String, dynamic>;
      a.permissions = ((j['permissions'] ?? const []) as List).cast<String>();
      a.minSdk = (j['minSdk'] as num?)?.toInt();
      a.versionCode = (j['versionCode'] as num?)?.toInt();
    } catch (_) {}
  }

  /// Cherche le fichier .apk de la dernière version publiée sur GitHub.
  Future<void> _resolve(AppEntry a) async {
    try {
      final txt = await _getText(Uri.parse(
          'https://api.github.com/repos/${a.github}/releases/latest'));
      final j = jsonDecode(txt) as Map<String, dynamic>;
      final re = RegExp(a.assetPattern);
      final videoRe = RegExp(r'\.(mp4|webm|mkv|3gp)$', caseSensitive: false);
      for (final item in (j['assets'] as List)) {
        final asset = Map<String, dynamic>.from(item as Map);
        if (a.videoUrl == null && videoRe.hasMatch(asset['name'] as String)) {
          a.videoUrl = asset['browser_download_url'] as String;
          a.videoSize = (asset['size'] as num).toInt();
        }
      }
      for (final item in (j['assets'] as List)) {
        final asset = Map<String, dynamic>.from(item as Map);
        final name = asset['name'] as String;
        if (re.hasMatch(name)) {
          a.downloadUrl = asset['browser_download_url'] as String;
          a.size = (asset['size'] as num).toInt();
          a.latestVersion = j['tag_name'] as String?;
          a.releaseNotes = (j['body'] as String?)?.trim();
          a.updatedAt = DateTime.tryParse((j['published_at'] ?? '') as String);
          a.resolveError = null;
          return;
        }
      }
      a.resolveError = "Aucun fichier d'installation trouvé.";
    } catch (_) {
      a.resolveError = 'Pas de connexion.';
    }
  }

  Future<String> _getText(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final rq = await client.getUrl(uri);
      rq.headers.set(HttpHeaders.userAgentHeader, 'WouStore');
      final rs = await rq.close();
      if (rs.statusCode != 200) {
        throw HttpException('HTTP ${rs.statusCode}');
      }
      return await rs.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  // ---------- Téléphone ----------

  Future<void> refreshInstalled() async {
    for (final a in apps) {
      await _refreshOne(a.id);
    }
    notifyListeners();
  }

  Future<void> _refreshOne(String id) async {
    final raw = await _ch.invokeMethod<Map>('installedInfo', {'package': id});
    final info = raw == null ? null : Map<String, dynamic>.from(raw);
    final v = info?['versionName'] as String?;
    final s = stateOf(id);
    s.installedVersion = v;
    s.installedCode = (info?['versionCode'] as num?)?.toInt();
    final at = (info?['updatedAt'] as num?)?.toInt();
    s.installedAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    if (v != null && !iconBytes.containsKey(id)) {
      try {
        final png = await _ch.invokeMethod<Uint8List>('icon', {'package': id});
        if (png != null) iconBytes[id] = png;
      } catch (_) {}
    }
    if (s.busy) return;
    if (v != null) {
      s.phase = Phase.installed;
      s.error = null;
    } else if (s.phase == Phase.installed) {
      s.phase = Phase.idle;
    }
  }

  Future<void> refreshShizuku() async {
    shizuku = await _ch.invokeMethod<String>('shizukuStatus') ?? 'absent';
    notifyListeners();
  }

  Future<void> _askShizuku() async {
    _shizukuWait = Completer<void>();
    await _ch.invokeMethod('shizukuRequest');
    // On attend la réponse (au plus une minute).
    await _shizukuWait!.future.timeout(const Duration(minutes: 1), onTimeout: () {});
    _shizukuWait = null;
    await refreshShizuku();
  }

  Future<void> shizukuAction() async {
    if (shizuku == 'ask') {
      await _ch.invokeMethod('shizukuRequest');
    } else {
      await _ch.invokeMethod('openShizuku');
    }
  }

  Future<void> open(AppEntry a) async {
    await _ch.invokeMethod('open', {'package': a.id});
  }

  void cancel(AppEntry a) => _cancel[a.id] = true;

  // ---------- Installation ----------

  Future<void> install(AppEntry a) async {
    final s = stateOf(a.id);
    if (s.busy) return;
    if (shizuku == 'ask') {
      // Shizuku demande son autorisation au premier « Installer » seulement.
      await _askShizuku();
    }
    s
      ..phase = Phase.downloading
      ..progress = 0
      ..received = 0
      ..total = a.size ?? 0
      ..error = null;
    notifyListeners();

    if (a.downloadUrl == null) {
      await _resolve(a);
      if (a.downloadUrl == null) {
        s
          ..phase = Phase.error
          ..error = a.resolveError ?? 'Fichier introuvable.';
        notifyListeners();
        return;
      }
    }

    final dir = await _ch.invokeMethod<String>('cacheDir');
    final file = File('$dir/${a.id}.apk');
    final client = HttpClient();
    _cancel[a.id] = false;
    try {
      final rq = await client.getUrl(Uri.parse(a.downloadUrl!));
      rq.headers.set(HttpHeaders.userAgentHeader, 'WouStore');
      final rs = await rq.close();
      if (rs.statusCode != 200) throw HttpException('HTTP ${rs.statusCode}');
      final total = rs.contentLength > 0 ? rs.contentLength : (a.size ?? 0);
      s.total = total;
      final sink = file.openWrite();
      var last = DateTime.now();
      try {
        await for (final chunk in rs) {
          if (_cancel[a.id] == true) throw const _Cancelled();
          sink.add(chunk);
          s.received += chunk.length;
          if (total > 0) s.progress = s.received / total;
          final now = DateTime.now();
          if (now.difference(last).inMilliseconds > 150) {
            last = now;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
    } on _Cancelled {
      s.phase = Phase.idle;
      notifyListeners();
      if (await file.exists()) await file.delete();
      return;
    } catch (_) {
      s
        ..phase = Phase.error
        ..error = 'Le téléchargement a échoué. Vérifie ta connexion.';
      notifyListeners();
      return;
    } finally {
      client.close(force: true);
    }

    s
      ..phase = Phase.installing
      ..progress = 1;
    notifyListeners();
    try {
      await _ch.invokeMethod('install', {
        'path': file.path,
        'package': a.id,
        'name': a.name,
        'shizuku': shizuku == 'ready',
      });
      // Le résultat arrive ensuite par « installResult ».
    } on PlatformException catch (e) {
      s
        ..phase = Phase.error
        ..error = e.message ?? "L'installation a échoué.";
      notifyListeners();
    }
  }
}
