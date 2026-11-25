import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../permissions.dart';
import '../services/account.dart';
import '../services/developer.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/install_button.dart';
import '../widgets/reviews_section.dart';
import '../widgets/video_preview.dart';

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
              if (Store.i.otherSource(app)) ...[
                const SizedBox(height: 12),
                Text(
                  'Cette version a été installée depuis une autre source (Play Store, F-Droid…). '
                  'WouStore ne peut pas la mettre à jour : continue avec ta source habituelle.',
                  style: W.body(13, color: W.orange).copyWith(height: 1.45),
                ),
              ],
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
              if (app.videoUrl != null) ...[
                const SizedBox(height: 26),
                Text('Aperçu', style: W.title(18)),
                const SizedBox(height: 12),
                VideoPreview(url: app.videoUrl!, size: app.videoSize),
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
              if (app.releaseNotes != null && cleanNotes(app.releaseNotes!).isNotEmpty) ...[
                const SizedBox(height: 28),
                _Section(
                  title: 'Nouveautés',
                  trailing: app.updatedAt == null ? null : frenchDate(app.updatedAt!),
                  child: _Expandable(text: cleanNotes(app.releaseNotes!)),
                ),
              ],
              const SizedBox(height: 28),
              ReviewsSection(app: app),
              const SizedBox(height: 28),
              _Section(title: 'Informations', child: _Infos(app: app)),
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: () => _report(context, app),
                  icon: const Icon(Icons.flag_outlined, size: 18, color: W.muted),
                  label: Text('Signaler cette appli', style: W.body(14, color: W.muted, weight: FontWeight.w600)),
                ),
              ),
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
          cell(app.androidLabel, 'Compatible'),
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


// ---------- « À quoi s'attendre » ----------

String frenchDate(DateTime d) {
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  final l = d.toLocal();
  return '${l.day} ${months[l.month - 1]} ${l.year}';
}

/// Notes de version écrites en Markdown → texte simple.
String cleanNotes(String md) {
  var t = md.replaceAll('\r', '');
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  t = t.replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
  t = t.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
  t = t.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '• ');
  t = t.replaceAll(RegExp(r'[*_`]{1,3}'), '');
  t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t.trim();
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(title, style: W.title(18))),
            if (trailing != null) Text(trailing!, style: W.body(13, color: W.muted)),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _Expandable extends StatefulWidget {
  const _Expandable({required this.text});

  final String text;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long = widget.text.length > 280 || '\n'.allMatches(widget.text).length > 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _open || !long ? null : 5,
          overflow: _open || !long ? TextOverflow.visible : TextOverflow.ellipsis,
          style: W.body(14, color: W.soft).copyWith(height: 1.5),
        ),
        if (long)
          TextButton(
            onPressed: () => setState(() => _open = !_open),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
            child: Text(_open ? 'Voir moins' : 'Voir plus',
                style: W.body(14, color: W.accent, weight: FontWeight.w600)),
          ),
      ],
    );
  }
}

class _Permissions extends StatefulWidget {
  const _Permissions({required this.app});

  final AppEntry app;

  @override
  State<_Permissions> createState() => _PermissionsState();
}

class _PermissionsState extends State<_Permissions> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final d = describePermissions(widget.app.permissions ?? const []);
    if (d.shown.isEmpty) {
      return Text("Cette appli ne demande aucune autorisation particulière.",
          style: W.body(14, color: W.soft));
    }
    final showAll = _all || d.shown.length <= 8;
    final visible = showAll ? d.shown : d.shown.take(5).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      decoration: BoxDecoration(
        color: W.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: W.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Cette appli pourra :', style: W.body(13, color: W.muted)),
          ),
          for (final p in visible)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(p.icon, size: 20, color: p.sensitive ? W.orange : W.muted),
                  const SizedBox(width: 12),
                  Expanded(child: Text(p.label, style: W.body(14))),
                ],
              ),
            ),
          if (d.shown.length > 8)
            TextButton(
              onPressed: () => setState(() => _all = !_all),
              style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft, padding: EdgeInsets.zero, minimumSize: const Size(0, 44)),
              child: Text(_all ? 'Voir moins' : 'Voir les ${d.shown.length} autorisations',
                  style: W.body(14, color: W.accent, weight: FontWeight.w600)),
            ),
          if (d.technical > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                d.technical == 1
                    ? '+ 1 autorisation technique sans accès à tes données'
                    : '+ ${d.technical} autorisations techniques sans accès à tes données',
                style: W.body(12, color: W.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Infos extends StatelessWidget {
  const _Infos({required this.app});

  final AppEntry app;

  Widget _permissionsRow(BuildContext context, List<String> perms) {
    final d = describePermissions(perms);
    final n = d.shown.length;
    return InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: W.bg,
        isScrollControlled: true,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Autorisations de ${app.name}', style: W.title(20)),
                const SizedBox(height: 14),
                _Permissions(app: app),
              ],
            ),
          ),
        ),
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: W.line))),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text('Autorisations', style: W.body(14, color: W.muted))),
            Expanded(
              child: Text(
                n == 0 ? 'Aucune particulière' : n == 1 ? '1 autorisation' : '$n autorisations',
                style: W.body(14),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: W.muted),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Créateur', app.developer.isEmpty ? '—' : app.developer),
      ('Version', app.latestVersion ?? '—'),
      if (app.updatedAt != null) ('Mise à jour', frenchDate(app.updatedAt!)),
      ('Taille', formatSize(app.size)),
      ('Android requis', app.androidLabel),
      ('Catégorie', app.category),
      ('Code source', app.openSource ? 'Open source (github.com/${app.github})' : 'Fermé'),
      if (app.ageRating != null)
        ('Âge', switch (app.ageRating) { 'all' => 'Tout public', '18' => '18 ans et plus', final a => '$a ans et plus' }),
      if (app.ageRating != null)
        (
          'Données',
          app.dataCollected.isEmpty
              ? 'Aucune donnée collectée'
              : 'Collecte : ${app.dataCollected.join(', ')}${app.dataShared ? ' (partagées avec des tiers)' : ''}'
        ),
      if (app.scanStatus == 'done')
        (
          'Anti-virus',
          (app.scanMalicious ?? 0) == 0
              ? '✅ Aucune menace détectée (${app.scanEngines} anti-virus, VirusTotal)'
              : (app.scanMalicious ?? 0) <= 2
                  ? '🟡 ${app.scanMalicious} anti-virus sur ${app.scanEngines} a un doute (souvent une fausse alerte)'
                  : '⚠️ ${app.scanMalicious} anti-virus sur ${app.scanEngines} signalent un danger'
        )
      else if (app.scanStatus == 'pending')
        ('Anti-virus', 'Analyse en cours par VirusTotal'),
    ];
    final perms = app.permissions;
    return Column(
      children: [
        if (perms != null) _permissionsRow(context, perms),
        for (final r in rows)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: W.line))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 130, child: Text(r.$1, style: W.body(14, color: W.muted))),
                Expanded(child: Text(r.$2, style: W.body(14))),
              ],
            ),
          ),
      ],
    );
  }
}


/// Signaler une appli dangereuse ou trompeuse (comme sur Google Play).
Future<void> _report(BuildContext context, AppEntry app) async {
  final messenger = ScaffoldMessenger.of(context);
  if (Account.i.user == null) {
    final ok = await Account.i.signIn();
    if (!ok) return;
  }
  if (!context.mounted) return;
  const reasons = [
    'Virus, vol de données ou arnaque',
    'Contenu choquant ou interdit',
    'Copie ou imitation d’une autre appli',
    'Ne fonctionne pas',
    'Autre',
  ];
  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: W.bg,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Pourquoi signales-tu ${app.name} ?', style: W.title(20)),
          ),
          for (final r in reasons)
            ListTile(
              title: Text(r, style: W.body(15)),
              trailing: const Icon(Icons.chevron_right_rounded, color: W.muted),
              onTap: () => Navigator.pop(ctx, r),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (reason == null) return;
  try {
    await DevSpace.report(app.id, Account.i.user!.uid, reason);
    messenger.showSnackBar(const SnackBar(content: Text('Merci, ton signalement a été envoyé.')));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Le signalement n’a pas pu être envoyé.')));
  }
}
