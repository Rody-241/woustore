import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/app_entry.dart';
import 'account.dart';
import 'developer.dart';

enum Phase { idle, downloading, installing, installed, error }

class AppState {
  Phase phase = Phase.idle;
  double progress = 0;
  int received = 0;
  int total = 0;
  String? installedVersion;
  int? installedCode;
  String? installedCert;
  DateTime? installedAt;
  String? error;

  bool get busy => phase == Phase.downloading || phase == Phase.installing;
}


/// Le cœur de WouStore : catalogue, téléchargements et installations.
class Store extends ChangeNotifier {
  Store._();
  static final Store i = Store._();

  static const _ch = MethodChannel('woustore/installer');
  static const catalogUrl =
      'https://raw.githubusercontent.com/Rody-241/woustore/main/catalog.json';

  List<AppEntry> apps = [];

  /// Catégories du catalogue : (nom, icône, est-ce un jeu).
  List<(String, String, bool)> categories = [];

  List<(String, String, bool)> get appCategories => categories.where((c) => !c.$3).toList();
  List<(String, String, bool)> get gameCategories => categories.where((c) => c.$3).toList();

  /// Seulement les catégories d'applis qui ont au moins une appli.
  List<(String, String, bool)> get usedCategories => appCategories
      .where((c) => visibleApps.any((a) => a.category == c.$1))
      .toList();

  bool isGame(AppEntry a) => gameCategories.any((c) => c.$1 == a.category);

  List<AppEntry> appsIn(String category) =>
      visibleApps.where((a) => a.category == category).toList();

  List<AppEntry> get games => visibleApps.where(isGame).toList();

  /// Version de WouStore installée, pour l'afficher.
  String? get selfVersion => stateOf(selfId).installedVersion;
  bool loading = true;
  String? loadError;

  /// absent | off | ask | old | ready
  String shizuku = 'absent';

  /// Icônes réelles des applis installées (lues sur le téléphone).
  final Map<String, Uint8List> iconBytes = {};
  Completer<void>? _shizukuWait;

  /// Fichier ouvert avec WouStore depuis une autre appli.
  final incoming = ValueNotifier<Map<String, dynamic>?>(null);

  Future<void> checkIncoming() async {
    final raw = await _ch.invokeMethod<Map>('takeIncomingFile');
    if (raw != null) incoming.value = Map<String, dynamic>.from(raw);
  }

  Future<void> watchPackage(String pkg) async {
    await _refreshOne(pkg);
    notifyListeners();
  }

  void markInstalling(String pkg) {
    stateOf(pkg)
      ..phase = Phase.installing
      ..error = null;
    notifyListeners();
  }

  Future<void> openPackage(String pkg) => _ch.invokeMethod('open', {'package': pkg});

  Future<void> openUrl(String url) => _ch.invokeMethod('openUrl', {'url': url});

  final Map<String, AppState> _states = {};
  bool _started = false;

  AppState stateOf(String id) => _states.putIfAbsent(id, () => AppState());

  /// Les applis visibles dans le magasin (sans la fiche de WouStore lui-même).
  List<AppEntry> get visibleApps => apps.where((a) => !a.hidden && !a.blocked).toList();

  List<AppEntry> get installedApps =>
      visibleApps.where((a) => stateOf(a.id).installedVersion != null).toList();

  String selfId = 'com.woustore.woustore';

  /// Types de processeur du téléphone (arm64-v8a, armeabi-v7a…).
  List<String> abis = const ['arm64-v8a'];

  /// Le bon fichier pour ce téléphone.
  String _patternFor(AppEntry a) {
    if (abis.contains('arm64-v8a')) return a.assetPattern;
    for (final abi in abis) {
      final p = a.assetsByAbi[abi];
      if (p != null) return p;
    }
    return a.assetPattern;
  }

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
    // Installée depuis une autre source (autre signature) : la mise à jour échouerait.
    if (otherSource(a)) return false;
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

  /// L'appli installée n'est pas signée par le même créateur que celle du catalogue.
  bool otherSource(AppEntry a) {
    final mine = stateOf(a.id).installedCert;
    final theirs = a.cert;
    return mine != null && theirs != null && mine.toLowerCase() != theirs.toLowerCase();
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
    abis = (await _ch.invokeMethod<List>('abis'))?.cast<String>() ?? abis;
    await refreshShizuku();
    // Au lancement, seulement la demande de notifications du téléphone.
    await _ch.invokeMethod('askNotifications');
    await checkIncoming();
    await load();
    await _resumeDownloads();
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
          s.error = m['message'] as String?; // avertissement éventuel (OBB)
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
      case 'incomingFile':
        incoming.value = Map<String, dynamic>.from(call.arguments as Map);
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
      categories = ((j['categories'] ?? const []) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((m) => (
                m['name'] as String,
                (m['icon'] ?? 'apps') as String,
                m['type'] == 'game',
              ))
          .toList();
      apps = (j['apps'] as List)
          .map((e) => AppEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      loadError = 'Le catalogue est illisible.';
    }
    // Les applis publiées par les développeurs (validées dans Firestore).
    try {
      await Account.i.initDone.timeout(const Duration(seconds: 10));
      if (Account.i.ready) {
        final extra = await DevSpace.publishedApps().timeout(const Duration(seconds: 15));
        for (final m in extra) {
          if (apps.any((a) => a.id == m['id'])) continue;
          try {
            apps.add(AppEntry.fromJson(m));
          } catch (_) {}
        }
        final blocked = await DevSpace.blockedApps().timeout(const Duration(seconds: 15));
        for (final a in apps) {
          if (blocked.contains(a.id)) a.blocked = true;
        }
      }
    } catch (_) {}
    loading = false;
    notifyListeners();
    await refreshInstalled();
    // D'abord les infos préparées par le robot (pas de limite),
    // puis l'API de GitHub seulement pour ce qui manque.
    await Future.wait(apps.map(_loadMeta));
    await Future.wait(apps.where((a) => a.downloadUrl == null).map(_resolve));
    notifyListeners();
  }

  /// Choisit le bon fichier (et la vidéo) dans une version publiée.
  bool _applyRelease(AppEntry a, Map<String, dynamic> rel) {
    final assets = ((rel['assets'] ?? const []) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final re = RegExp(_patternFor(a));
    final videoRe = RegExp(r'\.(mp4|webm|mkv|3gp)$', caseSensitive: false);
    for (final asset in assets) {
      final name = (asset['name'] ?? '') as String;
      final url = (asset['url'] ?? asset['browser_download_url']) as String?;
      if (a.videoUrl == null && videoRe.hasMatch(name)) {
        a.videoUrl = url;
        a.videoSize = (asset['size'] as num?)?.toInt();
      }
    }
    for (final asset in assets) {
      final name = (asset['name'] ?? '') as String;
      if (re.hasMatch(name)) {
        a.downloadUrl = (asset['url'] ?? asset['browser_download_url']) as String?;
        a.size = (asset['size'] as num?)?.toInt();
        a.latestVersion = (rel['tag'] ?? rel['tag_name']) as String?;
        a.releaseNotes = ((rel['notes'] ?? rel['body']) as String?)?.trim();
        a.updatedAt = DateTime.tryParse(((rel['publishedAt'] ?? rel['published_at']) ?? '') as String);
        a.resolveError = null;
        return true;
      }
    }
    return false;
  }

  Future<void> _loadMeta(AppEntry a) async {
    try {
      final j = jsonDecode(await _getText(
          Uri.parse('${AppEntry.metaBase}/${a.id}.json'))) as Map<String, dynamic>;
      a.permissions = ((j['permissions'] ?? const []) as List).cast<String>();
      a.minSdk = (j['minSdk'] as num?)?.toInt();
      a.versionCode = (j['versionCode'] as num?)?.toInt();
      final rel = j['release'] as Map?;
      if (rel != null) _applyRelease(a, Map<String, dynamic>.from(rel));
      // Le vrai numéro de version de l'appli (ex. 2.0.0) plutôt que l'étiquette GitHub.
      final vn = j['versionName'] as String?;
      if (vn != null && vn.isNotEmpty) a.latestVersion = vn;
      a.cert = j['cert'] as String?;
      if (j['blocked'] != null) a.blocked = true;
      final scan = j['scan'] as Map?;
      if (scan != null) {
        a.scanStatus = scan['status'] as String?;
        a.scanMalicious = ((scan['malicious'] as num?) ?? 0).toInt() + ((scan['suspicious'] as num?) ?? 0).toInt();
        a.scanEngines = (scan['engines'] as num?)?.toInt();
        a.scanLink = scan['link'] as String?;
      }
    } catch (_) {}
  }

  /// Secours : demander directement à l'API de GitHub (limitée à 60 questions par heure).
  Future<void> _resolve(AppEntry a) async {
    try {
      final txt = await _getText(Uri.parse(
          'https://api.github.com/repos/${a.github}/releases/latest'));
      final j = jsonDecode(txt) as Map<String, dynamic>;
      if (!_applyRelease(a, j)) a.resolveError = "Aucun fichier d'installation trouvé.";
    } on HttpException catch (e) {
      a.resolveError = e.message.contains('403') || e.message.contains('429')
          ? 'GitHub est saturé pour ta connexion. Réessaie dans un moment.'
          : 'Pas de connexion.';
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
    s.installedCert = info?['cert'] as String?;
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


  // ---------- Installation ----------

  final Map<String, int> _downloadIds = {};
  final Map<String, Timer> _polls = {};

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
      await _loadMeta(a);
    }
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

    // Le téléchargement est confié à Android : il continue quand on quitte
    // WouStore, reprend après une coupure, puis l'installation se lance seule.
    try {
      final id = await _ch.invokeMethod<int>('download', {
        'url': a.downloadUrl,
        'package': a.id,
        'name': a.name,
      });
      _follow(a.id, id!);
    } on PlatformException catch (e) {
      s
        ..phase = Phase.error
        ..error = e.message ?? 'Le téléchargement a échoué.';
      notifyListeners();
    }
  }

  /// Suit la progression d'un téléchargement (pour la barre et le pourcentage).
  void _follow(String pkg, int id) {
    _downloadIds[pkg] = id;
    _polls[pkg]?.cancel();
    _polls[pkg] = Timer.periodic(const Duration(milliseconds: 700), (t) async {
      final s = stateOf(pkg);
      Map<String, dynamic> st;
      try {
        st = Map<String, dynamic>.from(
            await _ch.invokeMethod<Map>('downloadStatus', {'id': id}) ?? const {});
      } catch (_) {
        return;
      }
      final status = st['status'] as String? ?? 'gone';
      s.received = (st['received'] as num?)?.toInt() ?? s.received;
      final total = (st['total'] as num?)?.toInt() ?? 0;
      if (total > 0) s.total = total;
      if (s.total > 0) s.progress = (s.received / s.total).clamp(0, 1).toDouble();
      switch (status) {
        case 'done':
          t.cancel();
          _polls.remove(pkg);
          if (s.phase == Phase.downloading) s.phase = Phase.installing;
          // Certains téléphones (HiOS…) ne transmettent pas « téléchargement fini » :
          // WouStore lance donc l'installation lui-même.
          _ch.invokeMethod('installDownloaded', {'id': id});
          _watchdog(pkg);
          break;
        case 'failed':
          t.cancel();
          _polls.remove(pkg);
          s
            ..phase = Phase.error
            ..error = 'Le téléchargement a échoué. Vérifie ta connexion et réessaie.';
          break;
        case 'gone':
          t.cancel();
          _polls.remove(pkg);
          if (s.phase == Phase.downloading) s.phase = Phase.idle;
          break;
        default:
          s.phase = Phase.downloading;
      }
      notifyListeners();
    });
  }

  /// Si l'installation ne donne pas de nouvelles, on ne laisse pas tourner le cercle sans fin.
  void _watchdog(String pkg) {
    Timer(const Duration(minutes: 3), () {
      final s = stateOf(pkg);
      if (s.phase == Phase.installing) {
        s
          ..phase = Phase.error
          ..error = "L'installation n'a pas abouti. Vérifie que Shizuku est actif, puis réessaie.";
        notifyListeners();
      }
    });
  }

  /// Après un redémarrage de WouStore : reprendre l'affichage des téléchargements en cours.
  Future<void> _resumeDownloads() async {
    final list = await _ch.invokeMethod<List>('pendingDownloads') ?? const [];
    for (final item in list) {
      final m = Map<String, dynamic>.from(item as Map);
      final pkg = m['package'] as String;
      stateOf(pkg).phase = Phase.downloading;
      _follow(pkg, (m['id'] as num).toInt());
    }
    if (list.isNotEmpty) notifyListeners();
  }

  void cancel(AppEntry a) {
    final id = _downloadIds[a.id];
    if (id != null) _ch.invokeMethod('cancelDownload', {'id': id});
    _polls.remove(a.id)?.cancel();
    final s = stateOf(a.id);
    s.phase = s.installedVersion != null ? Phase.installed : Phase.idle;
    notifyListeners();
  }
}
