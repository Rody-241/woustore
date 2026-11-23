import 'package:flutter/material.dart';

import '../services/developer.dart';
import '../theme.dart';

/// Ton espace administrateur : valider les développeurs et les applis.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: W.bg,
          surfaceTintColor: Colors.transparent,
          title: Text('Administration', style: W.title(20)),
          bottom: TabBar(
            indicatorColor: W.accent,
            labelColor: W.accent,
            unselectedLabelColor: W.muted,
            dividerColor: W.line,
            labelStyle: W.body(15, weight: FontWeight.w700),
            tabs: const [Tab(text: 'Développeurs'), Tab(text: 'Applis')],
          ),
        ),
        body: const TabBarView(children: [_Developers(), _Apps()]),
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: W.surface,
      title: Text('Raison du refus', style: W.title(20)),
      content: TextField(
        controller: c,
        maxLines: 3,
        style: W.body(15),
        decoration: InputDecoration(
          hintText: 'Ex. la photo de la pièce est illisible',
          hintStyle: W.body(14, color: W.muted),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Annuler', style: W.body(15, color: W.soft))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, c.text.trim()),
          child: Text('Refuser', style: W.body(15, color: W.red, weight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

Widget _actions({required VoidCallback onApprove, required VoidCallback onReject}) => Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onReject,
            style: OutlinedButton.styleFrom(
              foregroundColor: W.red,
              side: const BorderSide(color: W.border),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Refuser', style: W.body(14, color: W.red, weight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: onApprove,
            style: FilledButton.styleFrom(
              backgroundColor: W.accent,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Valider', style: W.body(14, color: W.onAccent, weight: FontWeight.w700)),
          ),
        ),
      ],
    );

Widget _empty(String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center, style: W.body(15, color: W.muted)),
      ),
    );

class _Developers extends StatefulWidget {
  const _Developers();

  @override
  State<_Developers> createState() => _DevelopersState();
}

class _DevelopersState extends State<_Developers> {
  late Future<List<Developer>> _list = DevSpace.developers(Review3.pending);

  void _reload() => setState(() => _list = DevSpace.developers(Review3.pending));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Developer>>(
      future: _list,
      builder: (context, snap) {
        if (snap.hasError) return _empty('Chargement impossible : ${snap.error}');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: W.accent));
        final devs = snap.data!;
        if (devs.isEmpty) return _empty('Aucune inscription en attente.');
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final d in devs)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: W.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: W.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(d.fullName, style: W.body(17, weight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${d.phone} · ${d.email}', style: W.body(13, color: W.muted)),
                    const SizedBox(height: 12),
                    FutureBuilder(
                      future: DevSpace.idPhoto(d.uid),
                      builder: (context, img) => img.data == null
                          ? Container(
                              height: 160,
                              alignment: Alignment.center,
                              color: W.surface2,
                              child: Text(img.connectionState == ConnectionState.done ? 'Pas de photo' : 'Chargement de la pièce…',
                                  style: W.body(13, color: W.muted)),
                            )
                          : GestureDetector(
                              onTap: () => showDialog(
                                context: context,
                                builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(img.data!))),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(img.data!, height: 200, fit: BoxFit.cover),
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text('Touche la photo pour l’agrandir. Vérifie que le nom correspond.',
                        style: W.body(12, color: W.muted)),
                    const SizedBox(height: 12),
                    _actions(
                      onApprove: () async {
                        await DevSpace.decideDeveloper(d.uid, true);
                        _reload();
                      },
                      onReject: () async {
                        final reason = await _askReason(context);
                        if (reason == null) return;
                        await DevSpace.decideDeveloper(d.uid, false, reason: reason);
                        _reload();
                      },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Apps extends StatefulWidget {
  const _Apps();

  @override
  State<_Apps> createState() => _AppsState();
}

class _AppsState extends State<_Apps> {
  late Future<List<Submission>> _list = DevSpace.submissions(Review3.pending);

  void _reload() => setState(() => _list = DevSpace.submissions(Review3.pending));

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Submission>>(
      future: _list,
      builder: (context, snap) {
        if (snap.hasError) return _empty('Chargement impossible : ${snap.error}');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: W.accent));
        final subs = snap.data!;
        if (subs.isEmpty) return _empty('Aucune appli en attente.');
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final s in subs)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: W.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: W.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(s.name, style: W.body(17, weight: FontWeight.w700)),
                    Text(s.package, style: W.body(12, color: W.muted)),
                    const SizedBox(height: 8),
                    Text('${s.data['category']} · par ${s.data['developer']}', style: W.body(13, color: W.soft)),
                    const SizedBox(height: 4),
                    Text(s.data['tagline'] as String? ?? '', style: W.body(14, weight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(s.data['description'] as String? ?? '', style: W.body(13, color: W.soft).copyWith(height: 1.45)),
                    const SizedBox(height: 8),
                    SelectableText('github.com/${s.github}/releases', style: W.body(13, color: W.accent)),
                    const SizedBox(height: 4),
                    Text(
                      'Avant de valider : ouvre ce lien et vérifie qu’une version avec un fichier APK est publiée. '
                      'Installe-la et essaie-la si tu as un doute.',
                      style: W.body(12, color: W.muted),
                    ),
                    const SizedBox(height: 12),
                    _actions(
                      onApprove: () async {
                        await DevSpace.decideSubmission(s, true);
                        _reload();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Validée ! Elle apparaîtra dans WouStore dans l’heure, avec son logo.'),
                          ));
                        }
                      },
                      onReject: () async {
                        final reason = await _askReason(context);
                        if (reason == null) return;
                        await DevSpace.decideSubmission(s, false, reason: reason);
                        _reload();
                      },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
