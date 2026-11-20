import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/theme.dart';
import '../platform/desktop_window.dart';
import '../platform/window_frame.dart';
import 'startup_appearance.dart';

/// Opening animation shown while the core starts.
///
/// The layers come from design/build_splash_layers.py and share the icon's
/// 1024-unit artwork space; every offset below is in those units.
class StartupSplash extends StatefulWidget {
  const StartupSplash({
    required this.appearance,
    required this.ready,
    required this.onExited,
    this.intro = true,
    this.error,
    this.onRetry,
    super.key,
  });

  final StartupAppearance appearance;

  /// Once true the splash finishes its intro, fades out and calls [onExited].
  final bool ready;
  final VoidCallback onExited;

  /// False when reconnecting: the artwork appears already assembled.
  final bool intro;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

const _introEnd = 1400.0;
const _minVisible = 1500.0;
const _exitLength = 450.0;

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late final _clock = ValueNotifier(_SplashFrame(_offset, 0));
  late final _still = WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;
  double? _exitAt;

  double get _offset => widget.intro && !_still ? 0 : _introEnd;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void didUpdateWidget(StartupSplash old) {
    super.didUpdateWidget(old);
    if (!widget.ready) _exitAt = null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final t = _still ? _introEnd : _offset + elapsed.inMicroseconds / 1000;
    if (widget.ready && _exitAt == null && (_still || t >= _minVisible)) {
      _exitAt = elapsed.inMicroseconds / 1000;
    }
    var exit = 0.0;
    if (_exitAt case final at?) {
      final length = _still ? 1.0 : _exitLength;
      exit = ((elapsed.inMicroseconds / 1000 - at) / length).clamp(0.0, 1.0);
    }
    _clock.value = _SplashFrame(t, exit);
    if (exit >= 1) {
      _ticker.stop();
      widget.onExited();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = widget.appearance;
    return ValueListenableBuilder(
      valueListenable: _clock,
      builder: (context, frame, child) => Opacity(
        opacity: 1 - Curves.easeInCubic.transform(frame.exit),
        child: child,
      ),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appearance.themeData(Brightness.light),
        darkTheme: appearance.themeData(Brightness.dark),
        themeMode: appearance.mode,
        builder: (context, child) =>
            DesktopWindow.installed ? ZeroWindowFrame(child: child!) : child!,
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: _clock,
            builder: (context, frame, _) => _SplashScene(
              frame: frame,
              ready: widget.ready,
              error: widget.error,
              onRetry: widget.onRetry,
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashFrame {
  const _SplashFrame(this.t, this.exit);

  /// Milliseconds on the splash timeline.
  final double t;

  /// Fade-out progress, 0 to 1.
  final double exit;
}

double _span(double t, double from, double to, [Curve curve = Curves.linear]) =>
    curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

/// One bar of the idle loop is two beats; the halo pulses on every beat and
/// sends out a ripple on the downbeat.
const _beatsFrom = 1000.0;
const _beat = 750.0;
const _bar = _beat * 2;
const _haloCenter = Offset(512, 141);
const _haloRadii = Size(212, 68);
const _brandRed = Color(0xFFFF5555);

class _SplashScene extends StatelessWidget {
  const _SplashScene({
    required this.frame,
    required this.ready,
    this.error,
    this.onRetry,
  });

  final _SplashFrame frame;
  final bool ready;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = frame.t;
    final zero = context.zero;
    final text = Theme.of(context).textTheme;
    final title = _span(t, 650, 1150, Curves.easeOutCubic);
    final status = ready ? 0.0 : _span(t, 1300, 1700);
    return LayoutBuilder(
      builder: (context, box) {
        final size = (box.biggest.shortestSide * 0.42).clamp(150.0, 300.0);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: size,
                child: _Artwork(frame: frame, scale: size / 1024),
              ),
              const SizedBox(height: 20),
              Opacity(
                opacity: title,
                child: Transform.translate(
                  offset: Offset(0, (1 - title) * 8),
                  child: Column(
                    children: [
                      Text(
                        '零拍',
                        style: TextStyle(
                          color: zero.text,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ZERO BEAT',
                        style: TextStyle(
                          color: zero.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 136,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: error != null
                      ? Column(
                          children: [
                            Text(
                              '无法连接播放服务',
                              style: text.bodyMedium?.copyWith(
                                color: zero.danger,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                error!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: text.bodySmall,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: onRetry,
                              child: const Text('重试'),
                            ),
                          ],
                        )
                      : Opacity(
                          opacity: status,
                          child: Text('正在连接播放服务', style: text.bodySmall),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.frame, required this.scale});

  final _SplashFrame frame;

  /// Pixels per artwork unit.
  final double scale;

  Widget _layer(
    String name, {
    double opacity = 1,
    Offset offset = Offset.zero,
    Offset origin = Offset.zero,
    double scaleX = 1,
    double scaleY = 1,
    double rotation = 0,
  }) {
    final matrix = Matrix4.identity()
      ..translateByDouble(offset.dx * scale, offset.dy * scale, 0, 1)
      ..rotateZ(rotation)
      ..scaleByDouble(scaleX, scaleY, 1, 1);
    return Positioned.fill(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform(
          transform: matrix,
          origin: origin * scale,
          child: RepaintBoundary(
            child: SvgPicture.asset(
              'assets/splash/$name.svg',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = frame.t;
    final exit = Curves.easeInCubic.transform(frame.exit);

    final rise = _span(t, 0, 700, Curves.easeOutCubic);
    final body = Offset(0, (1 - rise) * 28);

    final drop = _span(t, 250, 900, Curves.easeOutBack);
    final beats = math.max(0.0, t - _beatsFrom);
    final pulse = t < _beatsFrom ? 0.0 : math.exp(-(beats % _beat) / _beat * 7);
    final halo = 1 + 0.045 * pulse;

    final sway = t < _beatsFrom ? 0.0 : math.sin(beats / _bar * 2 * math.pi);
    final leftPop = _span(t, 550, 950, Curves.easeOutBack);
    final rightPop = _span(t, 700, 1100, Curves.easeOutBack);

    var blink = 1.0;
    if (t >= 1150) {
      final local = (t - 1150) % 4500;
      if (local < 200) blink = 1 - 0.9 * math.sin(math.pi * local / 200);
    }

    final ripple = t < _beatsFrom ? 1.0 : (beats % _bar) / 1200;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.72, 0.97],
      ).createShader(rect),
      child: Transform.scale(
        scale: 1 + 0.06 * exit,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (ripple < 1)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RipplePainter(progress: ripple, scale: scale),
                ),
              ),
            _layer('body', opacity: _span(t, 0, 600), offset: body),
            _layer(
              'eyes',
              opacity: _span(t, 0, 600),
              offset: body,
              origin: const Offset(502, 640),
              scaleY: blink,
            ),
            _layer(
              'halo',
              opacity: _span(t, 250, 500) * (1 - exit),
              offset: Offset(0, (1 - drop) * -90 - 60 * exit),
              origin: _haloCenter,
              scaleX: halo,
              scaleY: halo,
            ),
            _layer(
              'note_left',
              opacity: _span(t, 550, 750),
              offset: Offset(0, sway * 10),
              origin: const Offset(159, 166),
              scaleX: 0.3 + 0.7 * leftPop,
              scaleY: 0.3 + 0.7 * leftPop,
              rotation: sway * 0.06,
            ),
            _layer(
              'note_right',
              opacity: _span(t, 700, 900),
              offset: Offset(0, -sway * 10),
              origin: const Offset(876, 168),
              scaleX: 0.3 + 0.7 * rightPop,
              scaleY: 0.3 + 0.7 * rightPop,
              rotation: -sway * 0.06,
            ),
          ],
        ),
      ),
    );
  }
}

/// A sound-wave ring that leaves the halo on each downbeat.
class _RipplePainter extends CustomPainter {
  const _RipplePainter({required this.progress, required this.scale});

  final double progress;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final grow = 1 + 0.55 * Curves.easeOutCubic.transform(progress);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * scale * (1 - progress * 0.6)
      ..color = _brandRed.withValues(alpha: 0.6 * (1 - progress));
    canvas.drawOval(
      Rect.fromCenter(
        center: _haloCenter * scale,
        width: _haloRadii.width * 2 * grow * scale,
        height: _haloRadii.height * 2 * grow * scale,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.progress != progress || old.scale != scale;
}
