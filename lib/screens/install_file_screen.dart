import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/store.dart';
import '../theme.dart';

/// Un fichier ouvert avec WouStore (APK, XAPK, APKS, APKM, ZIP…) :
/// on montre ce qu'il contient, puis WouStore installe tout lui-même.
class InstallFileScreen extends StatefulWidget {
  const InstallFileScreen({super.key, required this.path, required this.name});

  final String path;
  final String name;

  @override
  State<InstallFileScreen> createState() => _InstallFileScreenState();
}

class _InstallFileScreenState extends State<InstallFileScreen> {
  static const _ch = MethodChannel('woustore/installer');

  Map<String, dynamic>? _info;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    final raw = await _ch.invokeMethod<Map>('analyzeFile', {'path': widget.path});
    if (!mounted) return;
    setState(() => _info = raw == null ? {'kind': 'unknown'} : Map<String, dynamic>.from(raw));
    final pkg = _info?['package'] as String?;
    if (pkg != null) await Store.i.watchPackage(pkg);
  }

  Future<void> _install() async {
    final pkg = (_info?['package'] as String?) ?? '';
    setState(() => _started = true);
    Store.i.markInstalling(pkg);
    await _ch.invokeMethod('installFile', {
      'path': widget.path,
      'package': pkg,
      'name': _info?['label'] ?? widget.name,
    });
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'apk':
        return 'Appli (APK)';
      case 'xapk':
        return 'Appli en plusieurs morceaux (XAPK)';
      case 'apks':
        return 'Appli en plusieurs morceaux (APKS)';
      case 'apkm':
        return 'Appli en plusieurs morceaux (APKM)';
      case 'zip':
        return 'Archive ZIP';
      default:
        return 'Fichier';
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: W.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Installer un fichier', style: W.title(18)),
      ),
      body: info == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: W.accent),
                  const SizedBox(height: 16),
                  Text('WouStore regarde ce que contient le fichier…',
                      style: W.body(14, color: W.soft)),
                ],
              ),
            )
          : info['kind'] == 'unknown'
              ? _error(info['error'] as String? ?? 'Ce fichier ne contient pas d’appli.')
              : _details(info),
    );
  }

  Widget _error(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: W.red, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: W.body(15, color: W.soft)),
          ],
        ),
      ),
    );
  }

  Widget _details(Map<String, dynamic> info) {
    final icon = info['icon'] as Uint8List?;
    final label = (info['label'] as String?) ?? widget.name;
    final pkg = (info['package'] as String?) ?? '';
    final obbCount = (info['obbCount'] as num?)?.toInt() ?? 0;
    final parts = (info['parts'] as num?)?.toInt() ?? 1;
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final s = Store.i.stateOf(pkg);
        final installing = _started && s.phase == Phase.installing;
        final installed = _started && s.phase == Phase.installed;
        final failed = _started && s.phase == Phase.error;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: icon == null
                      ? Container(
                          width: 88,
                          height: 88,
                          color: W.surface2,
                          child: const Icon(Icons.android_rounded, color: W.accent, size: 44))
                      : Image.memory(icon, width: 88, height: 88),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: W.title(26)),
                      const SizedBox(height: 4),
                      Text('Version ${info['versionName'] ?? '—'}',
                          style: W.body(14, color: W.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _row('Fichier', widget.name),
            _row('Format', _kindLabel(info['kind'] as String)),
            _row('Taille', formatSize((info['size'] as num?)?.toInt())),
            if (parts > 1) _row('Morceaux à installer', '$parts'),
            if (obbCount > 0)
              _row('Données du jeu (OBB)',
                  '$obbCount fichier${obbCount > 1 ? 's' : ''} · ${formatSize((info['obbSize'] as num?)?.toInt())}'),
            if (s.installedVersion != null && !_started)
              _row('Déjà installée', 'Version ${s.installedVersion}'),
            const SizedBox(height: 24),
            if (!_started || failed)
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _install,
                  icon: const Icon(Icons.install_mobile_rounded),
                  label: Text(
                    failed ? 'Réessayer' : (s.installedVersion != null ? 'Mettre à jour' : 'Installer'),
                    style: W.body(16, color: W.onAccent, weight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: W.accent,
                    foregroundColor: W.onAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            if (installing)
              Container(
                height: 52,
                decoration: BoxDecoration(
                  color: W.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: W.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: W.accent, strokeWidth: 3)),
                    const SizedBox(width: 12),
                    Text(obbCount > 0 ? 'Installation et copie des données…' : 'Installation…',
                        style: W.body(16, weight: FontWeight.w600)),
                  ],
                ),
              ),
            if (installed)
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: () => Store.i.openPackage(pkg),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text('Ouvrir', style: W.body(16, color: W.onAccent, weight: FontWeight.w700)),
                  style: FilledButton.styleFrom(
                    backgroundColor: W.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            if ((installed || failed) && s.error != null) ...[
              const SizedBox(height: 12),
              Text(s.error!, style: W.body(14, color: failed ? W.red : W.orange)),
            ],
            const SizedBox(height: 20),
            Text(
              'WouStore décompresse le fichier, choisit les morceaux faits pour ton téléphone'
              '${obbCount > 0 ? ' et range les données du jeu au bon endroit' : ''}. Tu n’as rien d’autre à faire.',
              style: W.body(13, color: W.muted).copyWith(height: 1.5),
            ),
          ],
        );
      },
    );
  }

  Widget _row(String a, String b) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: W.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(a, style: W.body(14, color: W.muted))),
          Expanded(child: Text(b, style: W.body(14))),
        ],
      ),
    );
  }
}
