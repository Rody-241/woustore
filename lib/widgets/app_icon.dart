import 'package:flutter/material.dart';

import '../models/app_entry.dart';
import '../services/store.dart';
import '../theme.dart';

IconData iconFor(String name) {
  const icons = <String, IconData>{
    'shield': Icons.shield_outlined,
    'terminal': Icons.terminal_rounded,
    'target': Icons.adjust_rounded,
    'play': Icons.smart_display_outlined,
    'game': Icons.sports_esports_outlined,
    'book': Icons.menu_book_outlined,
    'music': Icons.music_note_outlined,
    'build': Icons.handyman_outlined,
    'wifi': Icons.wifi_rounded,
    'chat': Icons.forum_outlined,
    'people': Icons.groups_outlined,
    'star': Icons.theater_comedy_outlined,
    'camera': Icons.photo_camera_outlined,
    'library': Icons.local_library_outlined,
    'check': Icons.task_alt_rounded,
    'money': Icons.payments_outlined,
    'bag': Icons.shopping_bag_outlined,
    'news': Icons.newspaper_outlined,
    'health': Icons.favorite_border_rounded,
    'sports': Icons.sports_soccer_outlined,
    'travel': Icons.flight_outlined,
    'map': Icons.map_outlined,
    'food': Icons.restaurant_outlined,
    'spa': Icons.spa_outlined,
    'palette': Icons.palette_outlined,
    'weather': Icons.wb_sunny_outlined,
    'work': Icons.business_center_outlined,
    'brush': Icons.brush_outlined,
    'comic': Icons.auto_stories_outlined,
    'home': Icons.home_outlined,
    'family': Icons.family_restroom_outlined,
    'medical': Icons.medical_services_outlined,
    'car': Icons.directions_car_outlined,
    'beauty': Icons.face_retouching_natural_outlined,
    'heart': Icons.favorite_outline_rounded,
    'event': Icons.event_outlined,
    'code': Icons.code_rounded,
    'action': Icons.flash_on_outlined,
    'explore': Icons.explore_outlined,
    'arcade': Icons.videogame_asset_outlined,
    'board': Icons.grid_on_outlined,
    'cards': Icons.style_outlined,
    'casino': Icons.casino_outlined,
    'smile': Icons.sentiment_satisfied_alt_outlined,
    'puzzle': Icons.extension_outlined,
    'race': Icons.sports_motorsports_outlined,
    'sim': Icons.precision_manufacturing_outlined,
    'strategy': Icons.military_tech_outlined,
    'quiz': Icons.quiz_outlined,
    'words': Icons.abc_rounded,
  };
  return icons[name] ?? Icons.apps_rounded;
}

/// Le logo d'une appli, tel que son créateur l'a fait :
/// 1. appli installée → l'icône que le téléphone affiche ;
/// 2. sinon → le logo extrait de son APK (icons/<id>.png) ;
/// 3. pas de réseau → une icône simple en attendant.
class AppIcon extends StatelessWidget {
  const AppIcon(this.app, {super.key, this.size = 52});

  final AppEntry app;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Store.i,
      builder: (context, _) {
        final bytes = Store.i.iconBytes[app.id];
        final radius = BorderRadius.circular(size * 0.24);
        Widget image;
        if (bytes != null) {
          image = Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true);
        } else {
          image = Image.network(
            app.iconUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _fallback(),
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : _placeholder(),
          );
        }
        return ClipRRect(borderRadius: radius, child: SizedBox(width: size, height: size, child: image));
      },
    );
  }

  Widget _placeholder() => Container(color: W.surface2);

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color.lerp(W.bg, app.color, 0.13),
        border: Border.all(color: Color.lerp(W.bg, app.color, 0.35)!),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Icon(iconFor(app.icon), color: app.color, size: size * 0.5),
    );
  }
}

/// Le logo WouStore : un « W » sur un carré vert.
class WouLogo extends StatelessWidget {
  const WouLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: W.accent,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: CustomPaint(painter: _WPainter()),
    );
  }
}

class _WPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = W.onAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(s.width * 0.22, s.height * 0.32)
      ..lineTo(s.width * 0.36, s.height * 0.70)
      ..lineTo(s.width * 0.50, s.height * 0.44)
      ..lineTo(s.width * 0.64, s.height * 0.70)
      ..lineTo(s.width * 0.78, s.height * 0.32);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
