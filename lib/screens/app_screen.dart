import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/install_button.dart';

/// Fiche d'une appli, avec la progression de l'installation.
class AppScreen extends StatelessWidget {
  const AppScreen({super.key, required this.app});

  final AppEntry app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: W.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          final s = Store.i.stateOf(app.id);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Row(
                children: [
                  AppIcon(app, size: 88),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app.name, style: W.title(28)),
                        const SizedBox(height: 4),
                        Text(app.developer,
                            style: W.body(14, color: W.accent, weight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(app.categoryLine, style: W.body(13, color: W.muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _Stats(app: app),
              const SizedBox(height: 22),
              if (s.busy) _Progress(app: app, s: s) else InstallButton(app, big: true),
              if (s.phase == Phase.error && s.error != null) ...[
                const SizedBox(height: 12),
                Text(s.error!, style: W.body(14, color: W.red)),
              ],
              if (s.busy) ...[
                const SizedBox(height: 22),
                _Steps(s: s),
                const SizedBox(height: 22),
                const _LeaveNote(),
              ],
              if (app.screenshots.isNotEmpty) ...[
                const SizedBox(height: 26),
                Text("Captures d'écran", style: W.title(18)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: app.screenshots.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(app.screenshots[i], fit: BoxFit.cover),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 26),
              Text('À propos', style: W.title(18)),
              const SizedBox(height: 8),
              Text(app.description,
                  style: W.body(15, color: W.soft).copyWith(height: 1.55)),
            ],
          );
        },
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.app});

  final AppEntry app;

  @override
  Widget build(BuildContext context) {
    Widget cell(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: W.body(15, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(label, style: W.body(12, color: W.muted)),
            ],
          ),
        );
    Widget sep() => Container(width: 1, height: 34, color: W.line);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: W.line)),
      ),
      child: Row(
        children: [
          cell(formatSize(app.size), 'Taille'),
          sep(),
          cell(app.latestVersion ?? '—', 'Version'),
          sep(),
          cell(app.android.isEmpty ? '—' : 'Android ${app.android}', 'Compatible'),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.app, required this.s});

  final AppEntry app;
  final AppState s;

  @override
  Widget build(BuildContext context) {
    final downloading = s.phase == Phase.downloading;
    final pct = (s.progress * 100).clamp(0, 100).round();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: W.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: W.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(downloading ? 'Téléchargement…' : 'Installation…',
                    style: W.body(15, weight: FontWeight.w600)),
              ),
              if (downloading && s.total > 0)
                Text('$pct %', style: W.title(20).copyWith(color: W.accent)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: downloading && s.total > 0 ? s.progress : null,
              color: W.accent,
              backgroundColor: W.border,
            ),
          ),
          if (downloading)
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.total > 0
                        ? '${formatSize(s.received)} sur ${formatSize(s.total)}'
                        : formatSize(s.received),
                    style: W.body(13, color: W.muted),
                  ),
                ),
                TextButton(
                  onPressed: () => Store.i.cancel(app),
                  style: TextButton.styleFrom(foregroundColor: W.soft),
                  child: Text('Annuler',
                      style: W.body(13, color: W.soft, weight: FontWeight.w600)),
                ),
              ],
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.s});

  final AppState s;

  @override
  Widget build(BuildContext context) {
    final installing = s.phase == Phase.installing;
    return Column(
      children: [
        _Step(
          title: 'Téléchargement',
          subtitle: installing ? 'Terminé' : 'En cours',
          state: installing ? _S.done : _S.active,
          icon: Icons.arrow_downward_rounded,
          line: true,
        ),
        _Step(
          title: 'Installation',
          subtitle: installing ? 'En cours' : 'Quelques secondes',
          state: installing ? _S.active : _S.todo,
          icon: Icons.install_mobile_rounded,
          line: true,
        ),
        const _Step(
          title: 'Prêt à ouvrir',
          state: _S.todo,
          icon: Icons.check_rounded,
          line: false,
        ),
      ],
    );
  }
}

enum _S { todo, active, done }

class _Step extends StatelessWidget {
  const _Step({
    required this.title,
    this.subtitle,
    required this.state,
    required this.icon,
    required this.line,
  });

  final String title;
  final String? subtitle;
  final _S state;
  final IconData icon;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final filled = state != _S.todo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? W.accent : null,
                border: filled ? null : Border.all(color: const Color(0xFF3A4352), width: 2),
              ),
              child: filled
                  ? Icon(state == _S.done ? Icons.check_rounded : icon,
                      size: 16, color: W.onAccent)
                  : null,
            ),
            if (line) Container(width: 2, height: 34, color: W.border),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: W.body(15,
                        color: filled ? W.text : W.soft, weight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: W.body(13, color: W.muted)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaveNote extends StatelessWidget {
  const _LeaveNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: W.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: W.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_none_rounded, color: W.muted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Tu peux quitter WouStore : le téléchargement continue, et une notification te prévient quand c'est prêt.",
              style: W.body(13, color: W.soft).copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
