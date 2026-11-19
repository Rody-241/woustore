import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/install_button.dart';
import 'app_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Store.i.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Store.i.refreshShizuku();
      Store.i.refreshInstalled();
    }
  }

  void _openApp(AppEntry a) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AppScreen(app: a)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Store.i,
          builder: (context, _) {
            final store = Store.i;
            return Column(
              children: [
                _Header(),
                Expanded(
                  child: store.loading
                      ? const Center(
                          child: CircularProgressIndicator(color: W.accent))
                      : RefreshIndicator(
                          color: W.accent,
                          backgroundColor: W.surface,
                          onRefresh: store.load,
                          child: _tab == 0 ? _home(store) : _mine(store),
                        ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _BottomBar(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }

  Widget _home(Store store) {
    final featured = store.apps.where((a) => a.featured).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (store.loadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(store.loadError!, style: W.body(14, color: W.red)),
          ),
        if (featured.isNotEmpty) ...[
          _FeaturedCard(app: featured.first, onTap: () => _openApp(featured.first)),
          const SizedBox(height: 28),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text('Toutes les applis', style: W.title(20))),
            Text('${store.apps.length} applis', style: W.body(13, color: W.muted)),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < store.apps.length; i++)
          _AppRow(
            app: store.apps[i],
            last: i == store.apps.length - 1,
            onTap: () => _openApp(store.apps[i]),
          ),
      ],
    );
  }

  Widget _mine(Store store) {
    final mine = store.installedApps;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Mes applis', style: W.title(20)),
        const SizedBox(height: 8),
        if (mine.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text(
              "Tu n'as encore installé aucune appli de WouStore.",
              textAlign: TextAlign.center,
              style: W.body(15, color: W.muted),
            ),
          ),
        for (var i = 0; i < mine.length; i++)
          _AppRow(
            app: mine[i],
            last: i == mine.length - 1,
            onTap: () => _openApp(mine[i]),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          const WouLogo(),
          const SizedBox(width: 10),
          Expanded(child: Text('WouStore', style: W.title(24))),
          const _ShizukuPill(),
        ],
      ),
    );
  }
}

/// Le voyant Shizuku : visible seulement si Shizuku est sur le téléphone.
class _ShizukuPill extends StatelessWidget {
  const _ShizukuPill();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) => _pill(),
    );
  }

  Widget _pill() {
    final status = Store.i.shizuku;
    late final Color dot;
    late final String label;
    switch (status) {
      case 'ready':
        dot = W.accent;
        label = 'Shizuku actif';
        break;
      case 'off':
        dot = W.red;
        label = 'Shizuku arrêté';
        break;
      case 'ask':
        dot = W.orange;
        label = 'Autoriser Shizuku';
        break;
      case 'denied':
        dot = W.orange;
        label = 'Shizuku refusé';
        break;
      case 'old':
        dot = W.orange;
        label = 'Shizuku à mettre à jour';
        break;
      default:
        return const SizedBox.shrink();
    }
    return Material(
      color: W.surface,
      shape: const StadiumBorder(side: BorderSide(color: W.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: status == 'ready' ? null : Store.i.shizukuAction,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(label, style: W.body(13, color: W.soft, weight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.app, required this.onTap});

  final AppEntry app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: W.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: W.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Color.lerp(W.surface, app.color, 0.18)!, width: 28),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('À LA UNE',
                      style: W.body(12, color: W.accent, weight: FontWeight.w600)
                          .copyWith(letterSpacing: 0.8)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      AppIcon(app, size: 64),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(app.name, style: W.title(22)),
                            const SizedBox(height: 2),
                            Text(app.tagline, style: W.body(14, color: W.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          app.size == null
                              ? app.category
                              : '${app.category} · ${formatSize(app.size)}',
                          style: W.body(13, color: W.muted),
                        ),
                      ),
                      InstallButton(app),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.last, required this.onTap});

  final AppEntry app;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: W.line)),
        ),
        child: Row(
          children: [
            AppIcon(app),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.name, style: W.body(16, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(app.categoryLine, style: W.body(13, color: W.muted)),
                ],
              ),
            ),
            InstallButton(app),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, String label) {
      final on = i == index;
      return Expanded(
        child: InkWell(
          onTap: () => onTap(i),
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: on ? W.accent : W.muted),
                const SizedBox(height: 4),
                Text(label,
                    style: W.body(12,
                        color: on ? W.accent : W.muted,
                        weight: on ? FontWeight.w600 : FontWeight.w500)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1015),
        border: Border(top: BorderSide(color: W.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: Row(
            children: [
              item(0, Icons.home_outlined, 'Accueil'),
              item(1, Icons.grid_view_rounded, 'Mes applis'),
            ],
          ),
        ),
      ),
    );
  }
}
