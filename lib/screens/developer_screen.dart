import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/account.dart';
import '../services/developer.dart';
import '../services/store.dart';
import '../theme.dart';

/// L'espace développeur : s'inscrire, puis publier ses applis.
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({super.key});

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  Developer? _dev;
  List<Submission> _subs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dev = await DevSpace.me();
      final subs = dev?.status == Review3.approved ? await DevSpace.mySubmissions() : const <Submission>[];
      if (!mounted) return;
      setState(() {
        _dev = dev;
        _subs = subs;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Impossible de charger ton espace. Vérifie ta connexion.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: W.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Espace développeur', style: W.title(20)),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (Account.i.user == null) {
      return _center(Icons.login_rounded, 'Connecte-toi avec Google (dans Mes applis) pour accéder à l’espace développeur.');
    }
    if (_loading) return const Center(child: CircularProgressIndicator(color: W.accent));
    if (_error != null) return _center(Icons.wifi_off_rounded, _error!);
    final dev = _dev;
    if (dev == null) return _RegisterForm(onDone: _load);
    switch (dev.status) {
      case Review3.pending:
        return _center(Icons.hourglass_top_rounded,
            'Merci ${dev.fullName.split(' ').first} ! Ton inscription est en cours de vérification.\nTu pourras publier tes applis dès qu’elle sera validée.');
      case Review3.rejected:
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _note(Icons.error_outline_rounded, W.red,
                'Ton inscription a été refusée.${(dev.reason ?? '').isEmpty ? '' : '\nRaison : ${dev.reason}'}\nTu peux corriger et renvoyer ta demande.'),
            const SizedBox(height: 20),
            _RegisterForm(onDone: _load, initial: dev, embedded: true),
          ],
        );
      case Review3.approved:
        return _approved(dev);
    }
  }

  Widget _approved(Developer dev) {
    return RefreshIndicator(
      color: W.accent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _note(Icons.verified_rounded, W.accent, 'Développeur vérifié : ${dev.fullName}'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () async {
              final ok = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const _SubmitScreen()),
              );
              if (ok == true) _load();
            },
            icon: const Icon(Icons.add_rounded),
            label: Text('Publier une appli', style: W.body(16, color: W.onAccent, weight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: W.accent,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(height: 28),
          Text('Mes applis publiées', style: W.title(18)),
          const SizedBox(height: 8),
          if (_subs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('Tu n’as encore rien publié.', style: W.body(14, color: W.muted)),
            ),
          for (final s in _subs) _SubmissionTile(s),
        ],
      ),
    );
  }

  Widget _center(IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: W.accent, size: 48),
              const SizedBox(height: 16),
              Text(text, textAlign: TextAlign.center, style: W.body(15, color: W.soft).copyWith(height: 1.5)),
            ],
          ),
        ),
      );
}

Widget _note(IconData icon, Color color, String text) => Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: W.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: W.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: W.body(14, color: W.soft).copyWith(height: 1.45))),
        ],
      ),
    );

class _SubmissionTile extends StatelessWidget {
  const _SubmissionTile(this.s);

  final Submission s;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (s.status) {
      Review3.pending => ('En attente de validation', W.orange),
      Review3.approved => ('Publiée dans WouStore', W.accent),
      Review3.rejected => ('Refusée', W.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: W.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.name, style: W.body(16, weight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(s.package, style: W.body(12, color: W.muted)),
          const SizedBox(height: 6),
          Text(label, style: W.body(13, color: color, weight: FontWeight.w600)),
          if (s.status == Review3.rejected && (s.reason ?? '').isNotEmpty)
            Text('Raison : ${s.reason}', style: W.body(13, color: W.soft)),
        ],
      ),
    );
  }
}

// ---------- Formulaire d'inscription ----------

class _RegisterForm extends StatefulWidget {
  const _RegisterForm({required this.onDone, this.initial, this.embedded = false});

  final VoidCallback onDone;
  final Developer? initial;
  final bool embedded;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  late final _name = TextEditingController(text: widget.initial?.fullName ?? Account.i.user?.displayName ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  Uint8List? _photo;
  bool _accept = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    // Photo réduite : lisible, mais légère (rangée dans la base de données).
    final x = await ImagePicker().pickImage(source: source, maxWidth: 1280, imageQuality: 60);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > 600 * 1024) {
      setState(() => _error = 'Photo trop lourde. Réessaie avec une photo plus simple.');
      return;
    }
    setState(() {
      _photo = bytes;
      _error = null;
    });
  }

  Future<void> _send() async {
    if (_name.text.trim().length < 4 || _phone.text.trim().length < 8 || _photo == null || !_accept) {
      setState(() => _error = 'Remplis tous les champs, ajoute la photo de ta pièce d’identité et accepte les règles.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DevSpace.register(fullName: _name.text, phone: _phone.text, idPhotoJpeg: _photo!);
      widget.onDone();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'L’envoi a échoué. Vérifie ta connexion et réessaie.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[
      if (!widget.embedded) ...[
        Text('Deviens développeur WouStore', style: W.title(22)),
        const SizedBox(height: 8),
        Text(
          'Publie tes applis pour tout le monde. On te demande juste ton nom, ton téléphone et une pièce d’identité : '
          'c’est ce qui protège les utilisateurs contre les applis malveillantes.',
          style: W.body(14, color: W.soft).copyWith(height: 1.5),
        ),
        const SizedBox(height: 12),
        _note(Icons.celebration_outlined, W.accent, 'Pendant la phase de lancement, l’inscription est gratuite.'),
        const SizedBox(height: 20),
      ],
      _field(_name, 'Nom complet (comme sur ta pièce d’identité)', TextInputType.name),
      const SizedBox(height: 12),
      _field(_phone, 'Téléphone (ex. 077 12 34 56)', TextInputType.phone),
      const SizedBox(height: 16),
      Text('Pièce d’identité', style: W.body(14, weight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Carte d’identité, passeport ou permis. Seul l’administrateur de WouStore peut la voir.',
          style: W.body(12, color: W.muted)),
      const SizedBox(height: 10),
      if (_photo != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.memory(_photo!, height: 180, fit: BoxFit.cover),
        ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Photographier'),
              style: _outlined(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Galerie'),
              style: _outlined(),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      CheckboxListTile(
        value: _accept,
        onChanged: (v) => setState(() => _accept = v ?? false),
        activeColor: W.accent,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          'Je m’engage à ne publier que mes propres applis, sans virus ni arnaque. '
          'Une appli dangereuse entraîne la fermeture de mon compte.',
          style: W.body(13, color: W.soft),
        ),
      ),
      if (_error != null) Text(_error!, style: W.body(13, color: W.red)),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _saving ? null : _send,
        style: FilledButton.styleFrom(
          backgroundColor: W.accent,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: _saving
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: W.onAccent))
            : Text('Envoyer ma demande', style: W.body(16, color: W.onAccent, weight: FontWeight.w700)),
      ),
    ];
    if (widget.embedded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content);
    }
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: content);
  }
}

ButtonStyle _outlined() => OutlinedButton.styleFrom(
      foregroundColor: W.text,
      minimumSize: const Size.fromHeight(48),
      side: const BorderSide(color: W.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );

Widget _field(TextEditingController c, String label, TextInputType type, {int lines = 1, int? max}) {
  return TextField(
    controller: c,
    keyboardType: type,
    maxLines: lines,
    maxLength: max,
    style: W.body(15),
    cursorColor: W.accent,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: W.body(14, color: W.muted),
      filled: true,
      fillColor: W.surface,
      counterStyle: W.body(11, color: W.muted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: W.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: W.accent, width: 1.5),
      ),
    ),
  );
}

// ---------- Publier une appli ----------

class _SubmitScreen extends StatefulWidget {
  const _SubmitScreen();

  @override
  State<_SubmitScreen> createState() => _SubmitScreenState();
}

class _SubmitScreenState extends State<_SubmitScreen> {
  final _name = TextEditingController();
  final _package = TextEditingController();
  final _tagline = TextEditingController();
  final _description = TextEditingController();
  final _github = TextEditingController();
  String? _category;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _package, _tagline, _description, _github]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Accepte « propriétaire/dépôt » ou un lien github.com complet.
  String? _repo(String input) {
    final t = input.trim().replaceAll(RegExp(r'\.git$'), '');
    final m = RegExp(r'(?:github\.com/)?([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/?$').firstMatch(t);
    return m == null ? null : '${m.group(1)}/${m.group(2)}';
  }

  Future<void> _send() async {
    final repo = _repo(_github.text);
    final pkg = _package.text.trim();
    if (_name.text.trim().length < 2 ||
        !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$').hasMatch(pkg) ||
        _tagline.text.trim().isEmpty ||
        _description.text.trim().length < 20 ||
        _category == null ||
        repo == null) {
      setState(() => _error =
          'Vérifie les champs : nom, nom de paquet (ex. com.monnom.monappli), phrase courte, description (20 caractères minimum), catégorie et dépôt GitHub.');
      return;
    }
    if (Store.i.apps.any((a) => a.id == pkg)) {
      setState(() => _error = 'Une appli avec ce nom de paquet existe déjà dans WouStore.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DevSpace.submit({
        'id': pkg,
        'name': _name.text.trim(),
        'developer': Account.i.name,
        'tagline': _tagline.text.trim(),
        'category': _category,
        'description': _description.text.trim(),
        'github': repo,
        'asset': r'\.(apk|xapk|apks|apkm)$',
        'icon': 'apps',
        'color': '#3DDC97',
        'featured': false,
        'openSource': false,
        'screenshots': <String>[],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'L’envoi a échoué. Vérifie ta connexion et réessaie.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = Store.i.categories;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: W.bg,
        surfaceTintColor: Colors.transparent,
        title: Text('Publier une appli', style: W.title(20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _field(_name, 'Nom de l’appli', TextInputType.text, max: 40),
          const SizedBox(height: 8),
          _field(_package, 'Nom de paquet Android (ex. com.monnom.monappli)', TextInputType.url),
          const SizedBox(height: 8),
          _field(_tagline, 'Phrase courte (ex. Apprends l’anglais en 5 minutes)', TextInputType.text, max: 60),
          const SizedBox(height: 8),
          _field(_description, 'Description : à quoi sert ton appli ?', TextInputType.multiline, lines: 5, max: 1000),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _category,
            dropdownColor: W.surface,
            isExpanded: true,
            style: W.body(15),
            decoration: InputDecoration(
              labelText: 'Catégorie',
              labelStyle: W.body(14, color: W.muted),
              filled: true,
              fillColor: W.surface,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: W.border),
              ),
            ),
            items: [
              for (final c in cats)
                DropdownMenuItem(value: c.$1, child: Text(c.$3 ? 'Jeu · ${c.$1}' : c.$1)),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 20),
          Text('Où se trouve ton APK ?', style: W.body(15, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          _note(
            Icons.info_outline_rounded,
            W.accent,
            '1. Crée un dépôt sur GitHub (gratuit).\n'
            '2. Dans « Releases », publie une version et joins ton fichier APK (ou XAPK).\n'
            '3. Tu peux aussi y joindre une vidéo .mp4 d’une minute au plus : elle servira d’aperçu.\n'
            'À chaque nouvelle version publiée, WouStore proposera la mise à jour tout seul.',
          ),
          const SizedBox(height: 12),
          _field(_github, 'Dépôt GitHub (ex. monnom/monappli)', TextInputType.url),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: W.body(13, color: W.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _send,
            style: FilledButton.styleFrom(
              backgroundColor: W.accent,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: W.onAccent))
                : Text('Envoyer pour validation', style: W.body(16, color: W.onAccent, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
