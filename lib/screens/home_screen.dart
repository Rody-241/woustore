import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../services/account.dart';
import '../services/store.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/install_button.dart';
import 'app_screen.dart';
import 'admin_screen.dart';
import 'categories_screen.dart';
import 'developer_screen.dart';
import 'install_file_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;

  /// Catégorie choisie sur l'accueil (null = tout).
  String? _category;
  final _query = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Store.i.incoming.addListener(_onIncoming);
    Store.i.init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Store.i.incoming.removeListener(_onIncoming);
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Store.i.refreshShizuku();
      Store.i.refreshInstalled();
      Store.i.checkIncoming();
    }
  }

  /// Un fichier a été ouvert avec WouStore : on affiche l'écran d'installation.
  void _onIncoming() {
    final f = Store.i.incoming.value;
    if (f == null || !mounted) return;
    Store.i.incoming.value = null;
    if (f['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f['error'] as String)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InstallFileScreen(path: f['path'] as String, name: f['name'] as String),
    ));
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
                          child: _tab == 0
                              ? _home(store)
                              : _tab == 1
                                  ? _search(store)
                                  : _mine(store),
                        ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: Store.i,
        builder: (context, _) => _BottomBar(
        index: _tab,
        badge: Store.i.updates.length + (Store.i.selfUpdate ? 1 : 0),
        onTap: (i) {
          setState(() => _tab = i);
          if (i == 1) {
            _searchFocus.requestFocus();
          } else {
            _searchFocus.unfocus();
          }
        },
      ),
      ),
    );
  }

  Widget _home(Store store) {
    final cats = store.usedCategories;
    // « Jeux » regroupe toutes les catégories de jeux.
    final cat = _category == 'Jeux' || cats.any((c) => c.$1 == _category) ? _category : null;
    final featured = cat == null
        ? store.visibleApps.where((a) => a.featured).toList()
        : <AppEntry>[];
    final list = cat == null
        ? store.visibleApps
        : cat == 'Jeux'
            ? store.games
            : store.appsIn(cat);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (store.loadError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(store.loadError!, style: W.body(14, color: W.red)),
          ),
        if (store.selfUpdate) ...[
          _SelfUpdateBanner(app: store.selfApp!),
          const SizedBox(height: 20),
        ],
        _CategoryBar(
          categories: cats,
          selected: cat,
          onSelect: (c) => setState(() => _category = c),
          onAll: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CategoriesScreen(onOpenApp: _openApp)),
          ),
        ),
        const SizedBox(height: 20),
        if (featured.isNotEmpty) ...[
          _FeaturedCard(app: featured.first, onTap: () => _openApp(featured.first)),
          const SizedBox(height: 28),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(cat ?? 'Toutes les applis', style: W.title(20))),
            if (list.isNotEmpty)
              Text(list.length == 1 ? '1 appli' : '${list.length} applis',
                  style: W.body(13, color: W.muted)),
          ],
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              cat == 'Jeux'
                  ? 'Pas encore de jeux. Ils arrivent bientôt !'
                  : 'Pas encore d’appli dans cette catégorie.',
              textAlign: TextAlign.center,
              style: W.body(15, color: W.muted),
            ),
          ),
        for (var i = 0; i < list.length; i++)
          AppRow(
            app: list[i],
            last: i == list.length - 1,
            onTap: () => _openApp(list[i]),
          ),
      ],
    );
  }

  Widget _search(Store store) {
    final q = _normalize(_query.text.trim());
    final results = q.isEmpty
        ? store.visibleApps
        : store.visibleApps.where((a) {
            final text = _normalize(
                '${a.name} ${a.tagline} ${a.category} ${a.developer} ${a.description}');
            return q.split(' ').every(text.contains);
          }).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        TextField(
          controller: _query,
          focusNode: _searchFocus,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          style: W.body(16),
          cursorColor: W.accent,
          decoration: InputDecoration(
            hintText: 'Rechercher une appli ou un jeu',
            hintStyle: W.body(16, color: W.muted),
            prefixIcon: const Icon(Icons.search_rounded, color: W.muted),
            suffixIcon: _query.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    icon: const Icon(Icons.close_rounded, color: W.muted),
                    onPressed: () => setState(_query.clear),
                  ),
            filled: true,
            fillColor: W.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: W.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: W.accent, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (q.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              results.isEmpty
                  ? 'Aucune appli ne correspond à « ${_query.text.trim()} ».'
                  : results.length == 1
                      ? '1 résultat'
                      : '${results.length} résultats',
              style: W.body(13, color: W.muted),
            ),
          ),
        for (var i = 0; i < results.length; i++)
          AppRow(
            app: results[i],
            last: i == results.length - 1,
            onTap: () => _openApp(results[i]),
          ),
      ],
    );
  }

  /// Minuscules et sans accents : « réseau » trouve « Reseau ».
  static String _normalize(String s) {
    const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
    final lower = s.toLowerCase();
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  Widget _mine(Store store) {
    final mine = store.installedApps;
    final ups = store.updates;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (store.selfUpdate) ...[
          _SelfUpdateBanner(app: store.selfApp!),
          const SizedBox(height: 20),
        ],
        if (ups.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  ups.length == 1 ? '1 mise à jour' : '${ups.length} mises à jour',
                  style: W.title(20),
                ),
              ),
              if (ups.length > 1)
                TextButton(
                  onPressed: store.updateAll,
                  child: Text('Tout mettre à jour',
                      style: W.body(14, color: W.accent, weight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < ups.length; i++)
            AppRow(app: ups[i], last: i == ups.length - 1, onTap: () => _openApp(ups[i])),
          const SizedBox(height: 24),
        ],
        const _AccountCard(),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.code_rounded,
          title: 'Espace développeur',
          subtitle: 'Publie tes propres applis sur WouStore',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DeveloperScreen()),
          ),
        ),
        const _AdminTile(),
        const SizedBox(height: 24),
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
          AppRow(
            app: mine[i],
            last: i == mine.length - 1,
            onTap: () => _openApp(mine[i]),
          ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            'WouStore version ${store.selfVersion ?? '—'}',
            style: W.body(12, color: W.muted),
          ),
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

class AppRow extends StatelessWidget {
  const AppRow({required this.app, required this.last, required this.onTap});

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
  const _BottomBar({required this.index, required this.onTap, this.badge = 0});

  final int index;
  final int badge;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, String label, {int count = 0}) {
      final on = i == index;
      return Expanded(
        child: InkWell(
          onTap: () => onTap(i),
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  backgroundColor: W.accent,
                  textColor: W.onAccent,
                  child: Icon(icon, size: 22, color: on ? W.accent : W.muted),
                ),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              item(0, Icons.home_outlined, 'Accueil'),
              item(1, Icons.search_rounded, 'Rechercher'),
              item(2, Icons.grid_view_rounded, 'Mes applis', count: badge),
            ],
          ),
        ),
      ),
    );
  }
}


/// « Nouvelle version de WouStore » : se met à jour tout seul.
class _SelfUpdateBanner extends StatelessWidget {
  const _SelfUpdateBanner({required this.app});

  final AppEntry app;

  @override
  Widget build(BuildContext context) {
    final s = Store.i.stateOf(app.id);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2A1F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2B5A44)),
      ),
      child: Row(
        children: [
          const WouLogo(size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nouvelle version de WouStore', style: W.body(15, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  s.phase == Phase.error && s.error != null
                      ? s.error!
                      : s.busy
                          ? 'WouStore va redémarrer tout seul.'
                          : 'Mets à jour en un toucher.',
                  style: W.body(13, color: s.phase == Phase.error ? W.orange : W.soft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InstallButton(app),
        ],
      ),
    );
  }
}


/// La rangée qui défile : « Tout », « Jeux », les catégories qui ont des applis,
/// puis « Catégories » pour les voir toutes.
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selected,
    required this.onSelect,
    required this.onAll,
  });

  final List<(String, String, bool)> categories;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          CategoryChip('Tout', Icons.apps_rounded, selected == null, () => onSelect(null)),
          const SizedBox(width: 8),
          CategoryChip('Jeux', Icons.sports_esports_outlined, selected == 'Jeux', () => onSelect('Jeux')),
          for (final c in categories) ...[
            const SizedBox(width: 8),
            CategoryChip(c.$1, iconFor(c.$2), selected == c.$1, () => onSelect(c.$1)),
          ],
          const SizedBox(width: 8),
          CategoryChip('Catégories', Icons.grid_view_rounded, false, onAll, outlined: true),
        ],
      ),
    );
  }
}

class CategoryChip extends StatelessWidget {
  const CategoryChip(this.label, this.icon, this.on, this.onTap, {super.key, this.outlined = false});

  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? W.accent : (outlined ? W.bg : W.surface),
      shape: StadiumBorder(side: BorderSide(color: on ? W.accent : W.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: on ? W.onAccent : (outlined ? W.accent : W.muted)),
              const SizedBox(width: 8),
              Text(label,
                  style: W.body(14,
                      color: on ? W.onAccent : (outlined ? W.accent : W.soft),
                      weight: on || outlined ? FontWeight.w700 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}


/// Le compte Google de l'utilisateur, en haut de « Mes applis ».
class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Account.i,
      builder: (context, _) {
        final a = Account.i;
        final u = a.user;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: W.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: W.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: W.surface2,
                backgroundImage: u?.photoURL == null ? null : NetworkImage(u!.photoURL!),
                child: u?.photoURL == null
                    ? const Icon(Icons.person_outline_rounded, color: W.muted)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u == null ? 'Pas connecté' : a.name,
                        style: W.body(15, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      u == null
                          ? (a.error ?? 'Connecte-toi pour noter les applis.')
                          : (u.email ?? ''),
                      style: W.body(12, color: a.error != null && u == null ? W.red : W.muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (u == null)
                TextButton(
                  onPressed: a.ready && !a.busy ? a.signIn : null,
                  child: Text('Se connecter',
                      style: W.body(14, color: W.accent, weight: FontWeight.w700)),
                )
              else
                TextButton(
                  onPressed: a.signOut,
                  child: Text('Déconnexion', style: W.body(13, color: W.soft)),
                ),
            ],
          ),
        );
      },
    );
  }
}


class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: W.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: W.border),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: W.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: W.body(15, weight: FontWeight.w700)),
                      Text(subtitle, style: W.body(12, color: W.muted)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: W.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Visible seulement pour l'administrateur.
class _AdminTile extends StatelessWidget {
  const _AdminTile();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Account.i,
      builder: (context, _) => Account.i.user == null
          ? const SizedBox.shrink()
          : FutureBuilder<bool>(
              future: Reviews.isAdmin(),
              builder: (context, snap) => snap.data == true
                  ? _MenuTile(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'Administration',
                      subtitle: 'Valider les développeurs et les applis',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AdminScreen()),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
    );
  }
}
