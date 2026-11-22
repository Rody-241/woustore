import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../services/store.dart';
import '../theme.dart';

/// Bouton Installer / Ouvrir. [big] = le grand bouton de la fiche.
class InstallButton extends StatelessWidget {
  const InstallButton(this.app, {super.key, this.big = false});

  final AppEntry app;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final s = Store.i.stateOf(app.id);
        switch (s.phase) {
          case Phase.downloading:
          case Phase.installing:
            return _busy(s);
          case Phase.installed:
            final update = Store.i.hasUpdate(app);
            final main = update
                ? _button('Mettre à jour', primary: true, onTap: () => Store.i.install(app))
                : _button('Ouvrir', primary: false, onTap: () => Store.i.open(app));
            if (!big || app.id == Store.i.selfId) return main;
            return Row(
              children: [
                Expanded(child: _uninstall(context)),
                const SizedBox(width: 12),
                Expanded(child: main),
              ],
            );
          case Phase.idle:
          case Phase.error:
            return _button(s.phase == Phase.error ? 'Réessayer' : 'Installer',
                primary: true, onTap: () => Store.i.install(app));
        }
      },
    );
  }

  Widget _uninstall(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: W.surface,
              title: Text('Désinstaller ${app.name} ?', style: W.title(20)),
              content: Text(
                "L'appli et ses données seront supprimées de ton téléphone.",
                style: W.body(15, color: W.soft),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('Annuler', style: W.body(15, color: W.soft, weight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text('Désinstaller', style: W.body(15, color: W.red, weight: FontWeight.w700)),
                ),
              ],
            ),
          );
          if (ok == true) await Store.i.uninstall(app);
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: W.text,
          side: const BorderSide(color: W.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text('Désinstaller', style: W.body(16, weight: FontWeight.w600)),
      ),
    );
  }

  Widget _busy(AppState s) {
    final value = s.phase == Phase.downloading && s.total > 0 ? s.progress : null;
    final ring = SizedBox(
      width: big ? 22 : 26,
      height: big ? 22 : 26,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: 3,
        color: W.accent,
        backgroundColor: W.border,
      ),
    );
    if (!big) {
      return SizedBox(width: 96, height: 44, child: Center(child: ring));
    }
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: W.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: W.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ring,
          const SizedBox(width: 12),
          Text(
            s.phase == Phase.downloading ? 'Téléchargement…' : 'Installation…',
            style: W.body(16, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _button(String label,
      {required bool primary, required VoidCallback onTap}) {
    if (big) {
      return SizedBox(
        height: 52,
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(primary ? Icons.download_rounded : Icons.open_in_new_rounded,
              size: 20),
          label: Text(label, style: W.body(16, color: primary ? W.onAccent : W.text, weight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            backgroundColor: primary ? W.accent : W.surface2,
            foregroundColor: primary ? W.onAccent : W.text,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: primary ? BorderSide.none : const BorderSide(color: W.border),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: primary ? const Color(0xFF0F2A1F) : W.surface2,
          foregroundColor: primary ? W.accent : W.text,
          side: BorderSide(color: primary ? const Color(0xFF2B5A44) : const Color(0xFF2E3644)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Text(label, style: W.body(14, color: primary ? W.accent : W.text, weight: FontWeight.w700)),
      ),
    );
  }
}
