import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';

/// Durée maximale d'un aperçu.
const maxPreview = Duration(minutes: 1);

/// Aperçu vidéo d'une appli. Rien n'est téléchargé tant qu'on ne touche pas ▶,
/// pour ne pas consommer les données des gens sans leur accord.
class VideoPreview extends StatefulWidget {
  const VideoPreview({super.key, required this.url, this.size});

  final String url;
  final int? size;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  VideoPlayerController? _c;
  bool _loading = false;
  bool _failed = false;
  bool _muted = true;

  @override
  void dispose() {
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      await c.setVolume(_muted ? 0 : 1);
      c.addListener(_onTick);
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _loading = false;
      });
    } catch (_) {
      c.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  /// L'aperçu s'arrête à 1 minute.
  void _onTick() {
    final c = _c;
    if (c == null) return;
    if (c.value.position >= maxPreview && c.value.isPlaying) {
      c.pause();
      c.seekTo(Duration.zero);
    }
    if (mounted) setState(() {});
  }

  void _toggle() {
    final c = _c;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _c?.setVolume(_muted ? 0 : 1);
  }

  void _fullscreen() {
    final c = _c;
    if (c == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FullscreenVideo(controller: c),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return _poster();

    final ratio = c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: W.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        // Verticale ou horizontale : la vidéo garde ses proportions.
        final h = (box.maxWidth / ratio).clamp(160.0, 480.0);
        return SizedBox(
        height: h,
        child: Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(
              onTap: _toggle,
              child: Center(
                child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(c)),
              ),
            ),
            if (!c.value.isPlaying)
              IgnorePointer(child: _roundButton(Icons.play_arrow_rounded, 64)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _controls(c),
            ),
          ],
        ),
        );
      }),
    );
  }

  Widget _controls(VideoPlayerController c) {
    final total = c.value.duration > maxPreview ? maxPreview : c.value.duration;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 18, 4, 4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xAA000000)],
        ),
      ),
      child: Row(
        children: [
          Text('${_fmt(c.value.position)} / ${_fmt(total)}',
              style: W.body(12, color: W.soft, weight: FontWeight.w500)),
          const Spacer(),
          IconButton(
            tooltip: _muted ? 'Activer le son' : 'Couper le son',
            onPressed: _toggleMute,
            icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: W.text, size: 22),
          ),
          IconButton(
            tooltip: 'Plein écran',
            onPressed: _fullscreen,
            icon: const Icon(Icons.fullscreen_rounded, color: W.text, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _poster() {
    return Material(
      color: W.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: W.border),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        onTap: _start,
        child: SizedBox(
          height: 200,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_loading)
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(color: W.accent, strokeWidth: 3),
                )
              else
                _roundButton(_failed ? Icons.refresh_rounded : Icons.play_arrow_rounded, 64),
              const SizedBox(height: 14),
              Text(
                _failed ? 'La vidéo ne se charge pas. Touche pour réessayer.' : "Voir l'appli en action",
                style: W.body(15, weight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                widget.size == null
                    ? 'Moins d’une minute'
                    : 'Moins d’une minute · ${formatSize(widget.size)}',
                style: W.body(13, color: W.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundButton(IconData icon, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: W.accent, shape: BoxShape.circle),
      child: Icon(icon, color: W.onAccent, size: size * 0.55),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _FullscreenVideo extends StatefulWidget {
  const _FullscreenVideo({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Une vidéo horizontale se regarde en tournant le téléphone.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    widget.controller.addListener(_tick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ratio = c.value.aspectRatio == 0 ? 9 / 16 : c.value.aspectRatio;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => c.value.isPlaying ? c.pause() : c.play(),
              child: Center(child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(c))),
            ),
            if (!c.value.isPlaying)
              const IgnorePointer(
                child: Center(
                  child: Icon(Icons.play_circle_fill_rounded, color: W.accent, size: 72),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
