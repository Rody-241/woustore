import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import 'home_screen.dart';

/// Toutes les catégories, comme dans les grands magasins : Applis puis Jeux.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, required this.onOpenApp});

  final void Function(AppEntry) onOpenApp;

  @override
  Widget build(BuildContext context) {
    final store = Store.i;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: W.bg,
          surfaceTintColor: Colors.transparent,
          title: Text('Catégories', style: W.title(20)),
          bottom: TabBar(
            indicatorColor: W.accent,
            labelColor: W.accent,
            unselectedLabelColor: W.muted,
            dividerColor: W.line,
            labelStyle: W.body(15, weight: FontWeight.w700),
            tabs: const [Tab(text: 'Applis'), Tab(text: 'Jeux')],
          ),
        ),
        body: TabBarView(
          children: [
            _list(context, store.appCategories),
            _list(context, store.gameCategories),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<(String, String, bool)> cats) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: cats.length,
      separatorBuilder: (_, __) => const Divider(color: W.line, height: 1),
      itemBuilder: (_, i) {
        final c = cats[i];
        final n = Store.i.appsIn(c.$1).length;
        return InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => _CategoryApps(name: c.$1, icon: c.$2, onOpenApp: onOpenApp),
          )),
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: W.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: W.border),
                  ),
                  child: Icon(iconFor(c.$2), size: 20, color: n > 0 ? W.accent : W.muted),
                ),
                const SizedBox(width: 14),
                Expanded(child: Text(c.$1, style: W.body(15, weight: FontWeight.w600))),
                Text(n == 0 ? 'Bientôt' : (n == 1 ? '1 appli' : '$n applis'),
                    style: W.body(13, color: W.muted)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: W.muted),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CategoryApps extends StatelessWidget {
  const _CategoryApps({required this.name, required this.icon, required this.onOpenApp});

  final String name;
  final String icon;
  final void Function(AppEntry) onOpenApp;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: W.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(name, style: W.title(20)),
      ),
      body: ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) {
          final apps = Store.i.appsIn(name);
          if (apps.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconFor(icon), size: 48, color: W.muted),
                    const SizedBox(height: 12),
                    Text('Pas encore d’appli ici.\nLes premières arrivent bientôt !',
                        textAlign: TextAlign.center, style: W.body(15, color: W.muted)),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              for (var i = 0; i < apps.length; i++)
                AppRow(app: apps[i], last: i == apps.length - 1, onTap: () => onOpenApp(apps[i])),
            ],
          );
        },
      ),
    );
  }
}
