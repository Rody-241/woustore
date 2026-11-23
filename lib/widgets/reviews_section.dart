import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../services/account.dart';
import '../services/store.dart';
import '../theme.dart';

/// « Notes et avis » sur la fiche d'une appli.
class ReviewsSection extends StatefulWidget {
  const ReviewsSection({super.key, required this.app});

  final AppEntry app;

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  RatingSummary? _summary;
  List<Review> _reviews = const [];
  Review? _mine;
  bool _admin = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Account.i.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    Account.i.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    if (!Account.i.ready) {
      if (mounted) setState(() => _loading = Account.i.error == null);
      return;
    }
    try {
      final id = widget.app.id;
      final results = await Future.wait([
        Reviews.summary(id),
        Reviews.latest(id),
        Reviews.mine(id),
        Reviews.isAdmin(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as RatingSummary;
        _reviews = results[1] as List<Review>;
        _mine = results[2] as Review?;
        _admin = results[3] as bool;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Les avis ne se chargent pas. Vérifie ta connexion.';
        });
      }
    }
  }

  Future<void> _write() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: W.bg,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ReviewForm(app: widget.app, existing: _mine),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(Review r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: W.surface,
        title: Text('Supprimer cet avis ?', style: W.title(20)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Annuler', style: W.body(15, color: W.soft))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Supprimer', style: W.body(15, color: W.red, weight: FontWeight.w700))),
        ],
      ),
    );
    if (ok == true) {
      await Reviews.delete(widget.app.id, r.uid);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Account.i, Store.i]),
      builder: (context, _) {
        final s = _summary;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Notes et avis', style: W.title(18)),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(color: W.accent)),
              )
            else if (_error != null)
              Text(_error!, style: W.body(14, color: W.muted))
            else ...[
              if (s != null && s.count > 0) _SummaryCard(summary: s) else
                Text('Pas encore d’avis. Sois le premier à donner ton avis !',
                    style: W.body(14, color: W.muted)),
              const SizedBox(height: 16),
              _action(),
              const SizedBox(height: 8),
              for (final r in _reviews)
                _ReviewTile(
                  review: r,
                  mine: r.uid == Account.i.user?.uid,
                  canDelete: _admin || r.uid == Account.i.user?.uid,
                  onDelete: () => _delete(r),
                ),
            ],
          ],
        );
      },
    );
  }

  /// Le bouton du bas : se connecter, noter, ou modifier son avis.
  Widget _action() {
    if (!Account.i.ready) {
      return Text(Account.i.error ?? 'Les avis ne sont pas disponibles.',
          style: W.body(13, color: W.muted));
    }
    if (Account.i.user == null) {
      return OutlinedButton.icon(
        onPressed: Account.i.busy ? null : Account.i.signIn,
        icon: const Icon(Icons.login_rounded, size: 20),
        label: Text('Se connecter avec Google pour donner un avis',
            style: W.body(14, weight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: W.text,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: W.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
    final installed = Store.i.stateOf(widget.app.id).installedVersion != null;
    if (!installed && _mine == null) {
      return Text('Installe l’appli pour pouvoir la noter.', style: W.body(13, color: W.muted));
    }
    return FilledButton.icon(
      onPressed: _write,
      icon: Icon(_mine == null ? Icons.star_outline_rounded : Icons.edit_outlined, size: 20),
      label: Text(_mine == null ? 'Donner mon avis' : 'Modifier mon avis',
          style: W.body(15, color: W.onAccent, weight: FontWeight.w700)),
      style: FilledButton.styleFrom(
        backgroundColor: W.accent,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class Stars extends StatelessWidget {
  const Stars(this.value, {super.key, this.size = 16});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            value >= i
                ? Icons.star_rounded
                : value >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: size,
            color: W.accent,
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final RatingSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: W.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: W.border),
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(s.average.toStringAsFixed(1).replaceAll('.', ','), style: W.title(40)),
              Stars(s.average),
              const SizedBox(height: 4),
              Text(s.count == 1 ? '1 avis' : '${s.count} avis', style: W.body(12, color: W.muted)),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                for (var star = 5; star >= 1; star--)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(width: 14, child: Text('$star', style: W.body(12, color: W.muted))),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              minHeight: 8,
                              value: s.count == 0 ? 0 : (s.byStars[star] ?? 0) / s.count,
                              color: W.accent,
                              backgroundColor: W.border,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.mine,
    required this.canDelete,
    required this.onDelete,
  });

  final Review review;
  final bool mine;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final r = review;
    final d = r.updatedAt;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: W.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: W.surface2,
                child: Text(r.name.isEmpty ? '?' : r.name[0].toUpperCase(),
                    style: W.body(14, weight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(mine ? '${r.name} (toi)' : r.name,
                    style: W.body(14, weight: FontWeight.w600)),
              ),
              if (canDelete)
                IconButton(
                  tooltip: 'Supprimer',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, color: W.muted, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Stars(r.rating.toDouble(), size: 14),
              const SizedBox(width: 8),
              if (d != null)
                Text('${d.day}/${d.month}/${d.year}', style: W.body(12, color: W.muted)),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.text, style: W.body(14, color: W.soft).copyWith(height: 1.45)),
        ],
      ),
    );
  }
}

/// Le formulaire : choisir ses étoiles et écrire son commentaire.
class _ReviewForm extends StatefulWidget {
  const _ReviewForm({required this.app, this.existing});

  final AppEntry app;
  final Review? existing;

  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  late int _rating = widget.existing?.rating ?? 0;
  late final _text = TextEditingController(text: widget.existing?.text ?? '');
  bool _saving = false;
  String? _error;

  static const _labels = ['', 'Très mauvais', 'Mauvais', 'Moyen', 'Bien', 'Excellent'];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Reviews.save(widget.app.id, _rating, _text.text,
          Store.i.stateOf(widget.app.id).installedVersion);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'L’avis n’a pas pu être publié. Vérifie ta connexion et réessaie.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ton avis sur ${widget.app.name}', style: W.title(20)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  tooltip: '$i étoile${i > 1 ? 's' : ''}',
                  iconSize: 40,
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    _rating >= i ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: W.accent,
                  ),
                ),
            ],
          ),
          Center(
            child: Text(_rating == 0 ? 'Touche une étoile' : _labels[_rating],
                style: W.body(14, color: W.soft)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            maxLength: 500,
            maxLines: 4,
            minLines: 3,
            style: W.body(15),
            cursorColor: W.accent,
            decoration: InputDecoration(
              hintText: 'Qu’as-tu aimé ou pas aimé ? (facultatif)',
              hintStyle: W.body(15, color: W.muted),
              filled: true,
              fillColor: W.surface,
              counterStyle: W.body(12, color: W.muted),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: W.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: W.accent, width: 1.5),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: W.body(13, color: W.red)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _rating == 0 || _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: W.accent,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: W.onAccent))
                : Text('Publier', style: W.body(16, color: W.onAccent, weight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Text('Ton avis est public, avec le nom de ton compte Google.',
              textAlign: TextAlign.center, style: W.body(12, color: W.muted)),
        ],
      ),
    );
  }
}
