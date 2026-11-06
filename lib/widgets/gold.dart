/// The gold a personal best is marked in: the medal, and the frame around
/// the throw that won it.
///
/// One ramp serves both, and it is a narrow one — a light sheen either side
/// of the same mid gold, never dropping to brown. A wide ramp makes a
/// convincing coin on its own and a blotchy frame around a photo, and what
/// matters more is that the two read as the same piece of metal.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The flat gold, for text and small marks where a gradient would only
/// muddy a few pixels. The medal's mid tone, so they match.
const personalBestGold = Color(0xFFF7B733);

/// Sheen, mid, sheen — enough to look like metal, even enough to run all
/// the way round a frame without a dark side.
const _metal = <Color>[
  Color(0xFFE9A62B),
  Color(0xFFFFD978),
  Color(0xFFF7B733),
  Color(0xFFFFE9A8),
  Color(0xFFECAA2E),
];
const _metalStops = <double>[0, 0.26, 0.52, 0.78, 1];

/// The ramp across [bounds], lit from the top left.
Shader goldShader(Rect bounds) => _ramp(_metal, bounds);

/// The other two of a podium, struck the same way.
///
/// Same five stops, same narrow spread, same light from the same corner —
/// so three lines drawn across a sector read as three medals rather than as
/// three arbitrary colors. Silver is the cool one and bronze the warm one;
/// neither is allowed to go dark, for the reason the gold isn't.
const _silverMetal = <Color>[
  Color(0xFFA9B4BE),
  Color(0xFFE4EAEF),
  Color(0xFFC6CED6),
  Color(0xFFF2F6F9),
  Color(0xFFADB8C2),
];
const _bronzeMetal = <Color>[
  Color(0xFFB0724A),
  Color(0xFFE2A379),
  Color(0xFFCB8A5B),
  Color(0xFFF0BE96),
  Color(0xFFB4764D),
];

/// The flat mid tone of each, for text beside the line it belongs to —
/// the same reason [personalBestGold] exists.
const secondPlaceSilver = Color(0xFFC6CED6);
const thirdPlaceBronze = Color(0xFFCB8A5B);

Shader silverShader(Rect bounds) => _ramp(_silverMetal, bounds);
Shader bronzeShader(Rect bounds) => _ramp(_bronzeMetal, bounds);

/// The three metals a podium is struck in, as one thing.
///
/// The ramps were here already — the board has drawn its three lines with
/// them since it was written. This names them together so everywhere else
/// that puts a place on screen can reach the same metal, rather than each
/// picking a yellow, a gray and a brown of its own.
enum Medal {
  gold(personalBestGold, _metal),
  silver(secondPlaceSilver, _silverMetal),
  bronze(thirdPlaceBronze, _bronzeMetal);

  const Medal(this.flat, this.ramp);

  /// The mid tone, for text and small marks. A five-stop gradient across
  /// two digits of a place number is a muddy two digits; the flat tone is
  /// the same metal and stays legible, which is the rule the board already
  /// follows for the type beside its lines.
  final Color flat;

  /// The five stops, for something big enough to show them.
  final List<Color> ramp;

  Shader shader(Rect bounds) => _ramp(ramp, bounds);
}

/// The five stops every metal is spread across, shared so the three read as
/// the same strike. Exposed because the spectator's page has to lay the
/// same ramp down in CSS.
const List<double> metalStops = _metalStops;

/// The metal a place is struck in — null for a place off the podium, which
/// is most of a field and wears the plain type the rest of the row does.
Medal? medalFor(int place) => switch (place) {
      1 => Medal.gold,
      2 => Medal.silver,
      3 => Medal.bronze,
      _ => null,
    };

Shader _ramp(List<Color> metal, Rect bounds) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: metal,
      stops: _metalStops,
    ).createShader(bounds);

/// Strokes a rounded rectangle in gold, inside the bounds it is given.
///
/// A foreground painter rather than a border on the card's shape: the card
/// is already clipped to its radius, so the stroke has to sit inside that
/// clip, and painting it here keeps a best exactly the same size as every
/// other card instead of two pixels fatter.
class GoldEdgePainter extends CustomPainter {
  const GoldEdgePainter({
    this.radius = 16,
    this.width = 2,
    this.drawn = 1,
    this.glint,
    this.opacity = 1,
  });

  final double radius;
  final double width;

  /// How much of the frame is drawn, traced both ways from the top-right
  /// corner — where the medal hangs — to meet at the bottom left. 1 is the
  /// whole frame, which is every frame but the one being struck.
  final double drawn;

  /// Where a bright band of light is running across the metal, 0 at the
  /// top-left corner and 1 at the bottom right; null for none.
  final double? glint;

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (drawn <= 0 || opacity <= 0) return;
    // Half the stroke falls either side of the path, so inset by that much
    // to keep all of it inside the clip.
    final rect = Offset.zero & size;
    final inset = rect.deflate(width / 2);
    final rrect =
        RRect.fromRectAndRadius(inset, Radius.circular(radius - width / 2));
    final path = drawn >= 1 ? (Path()..addRRect(rrect)) : _traced(rrect);
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..shader = goldShader(rect);
    if (opacity < 1) {
      canvas.saveLayer(rect, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    }
    canvas.drawPath(path, gold);
    if (glint != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..shader = glintShader(rect, glint!),
      );
    }
    if (opacity < 1) canvas.restore();
  }

  /// The part of the frame drawn so far: two runs out of the top-right
  /// corner, one each way, which meet at the far corner as [drawn] reaches
  /// 1.
  Path _traced(RRect rrect) {
    final metric = (Path()..addRRect(rrect)).computeMetrics().first;
    final length = metric.length;
    // Where along the outline the top-right corner is. Found rather than
    // assumed, because where a rounded rectangle's path starts is the
    // engine's business.
    final corner = Offset(rrect.right, rrect.top);
    var start = 0.0;
    var nearest = double.infinity;
    for (var at = 0.0; at < length; at += 2) {
      final gap = (metric.getTangentForOffset(at)!.position - corner).distance;
      if (gap < nearest) {
        nearest = gap;
        start = at;
      }
    }
    final half = length * drawn / 2;
    final out = Path();
    void run(double from, double to) {
      // A run that wraps past the end of the outline is two extracts.
      if (from < 0) {
        out.addPath(metric.extractPath(length + from, length), Offset.zero);
        from = 0;
      }
      if (to > length) {
        out.addPath(metric.extractPath(0, to - length), Offset.zero);
        to = length;
      }
      out.addPath(metric.extractPath(from, to), Offset.zero);
    }

    run(start - half, start + half);
    return out;
  }

  @override
  bool shouldRepaint(GoldEdgePainter old) =>
      old.radius != radius ||
      old.width != width ||
      old.drawn != drawn ||
      old.glint != glint ||
      old.opacity != opacity;
}

/// A narrow band of light across [bounds], lit from the same corner the
/// ramp is, centered [at] of the way along the diagonal. Laid over metal
/// that has just been struck, it runs across it once — which is what makes
/// a best that has just been set read as new rather than as one more medal.
Shader glintShader(Rect bounds, double at) {
  const width = 0.14;
  double stop(double x) => x.clamp(0.0, 1.0).toDouble();
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: const [
      Color(0x00FFFFFF),
      Color(0xE6FFFBEA),
      Color(0x00FFFFFF),
    ],
    stops: [stop(at - width), stop(at), stop(at + width)],
  ).createShader(bounds);
}

/// A first-place medal: a struck disc with a star cut clean out of it,
/// hanging from two straps of ribbon.
///
/// Drawn like the event glyphs and the sector are, so it scales to whatever
/// corner it is pinned in, needs no icon font, and takes the same gold as
/// the frame around the card it sits on. The star is a real hole rather
/// than a lighter shape, which is what keeps it reading as a medal at 13
/// pixels instead of as a yellow blob with a smudge in it.
///
/// The disc is the subject. The ribbon was as wide as it and half again as
/// tall once, and at the size a personal best is actually marked at —
/// beside a mark, or a placing — that read as a gold V with something under
/// it. It is shorter now, and it hangs clear of the disc rather than
/// running under it: ribbon and disc are the same metal, so with nothing
/// between them the straps melted into the top of the coin.
///
/// The ribbon is not two mirrored straps. It is one band, tapering as it
/// comes down, with a slot cut across it at 45° — so the right-hand piece
/// runs out to a point while the left carries on to a square end. That
/// asymmetry is the whole read: a ribbon has a front and a back and is
/// folded through itself, and two straps leaning symmetrically into each
/// other are a V, which is a letter.
class PlaceMedal extends StatelessWidget {
  const PlaceMedal({
    super.key,
    required this.medal,
    this.size = 20,
    this.label,
  });

  /// Which of the three it is struck in.
  final Medal medal;

  /// Width — which is the disc's diameter. The ribbon puts a little more
  /// height on top, so a badge is sized by how big its disc should be and
  /// the straps follow.
  final double size;

  /// What it is marking, read out loud. The same disc means a placing in a
  /// competition and a personal best in the library, and a screen reader
  /// has no context to tell them apart — so whoever pins it says.
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label ?? '${medal.name} medal',
      child: SizedBox(
        width: size,
        height: size * _MedalPainter.aspect,
        child: CustomPaint(painter: _MedalPainter(medal)),
      ),
    );
  }
}

/// The gold a personal best wears. The same disc as a first place, named
/// apart because it means something else: a best is against the athlete's
/// own record book, a placing is against the field in front of them.
///
/// [celebrate] is for the one that has just been won: it drops in on its
/// ribbon, swings, and catches the light once — see [PersonalBestStrike].
class PersonalBestMedal extends StatelessWidget {
  const PersonalBestMedal({
    super.key,
    this.size = 20,
    this.celebrate = false,
    this.onCelebrated,
  });

  final double size;
  final bool celebrate;

  /// Called once it has been struck, so whoever said it was new can stop
  /// saying so.
  final VoidCallback? onCelebrated;

  @override
  Widget build(BuildContext context) {
    final medal =
        PlaceMedal(medal: Medal.gold, size: size, label: 'Personal best');
    if (!celebrate) return medal;
    return PersonalBestStrike(
      onStruck: onCelebrated,
      builder: (context, strike) => strike.medal(medal, size),
    );
  }
}

/// The moment a best is won, as one animation both halves of the gold hang
/// off: the frame traced out of the medal's corner, the medal dropping in
/// on its ribbon and swinging still, and a band of light run across the
/// metal once it has.
///
/// Played once, when it is built — a best is only new the first time
/// anybody sees it. Reduced motion skips straight to the end, which is
/// exactly what a best looks like after the moment is over.
class PersonalBestStrike extends StatefulWidget {
  const PersonalBestStrike({super.key, required this.builder, this.onStruck});

  final Widget Function(BuildContext context, StrikeFrame strike) builder;
  final VoidCallback? onStruck;

  static const duration = Duration(milliseconds: 1900);

  @override
  State<PersonalBestStrike> createState() => _PersonalBestStrikeState();
}

class _PersonalBestStrikeState extends State<PersonalBestStrike>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: PersonalBestStrike.duration);

  @override
  void initState() {
    super.initState();
    // Told only once it is over. Whoever said the best was new goes on
    // saying so until then, so a rebuild halfway through — the entry that
    // set it saving, a poll landing — keeps the strike rather than swapping
    // it for a medal at rest.
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onStruck?.call();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _controller.value = 1;
        widget.onStruck?.call();
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) =>
            widget.builder(context, StrikeFrame(_controller.value)),
      );
}

/// Where a [PersonalBestStrike] has got to, and what each part of the gold
/// is doing at that point.
class StrikeFrame {
  const StrikeFrame(this.t);

  /// 0 to 1 over [PersonalBestStrike.duration].
  final double t;

  static double _span(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0).toDouble();

  /// How much of the frame is traced.
  double get drawn =>
      Curves.easeInOutCubic.transform(_span(t, 0, 0.42));

  /// The medal: how far it has dropped, how hard it is still swinging, and
  /// whether it is there yet.
  ///
  /// The drop overshoots and settles back, written out rather than taken
  /// from [Curves.easeOutBack] — a Bézier the spectator's page would only
  /// be approximating — so the page can say exactly the same curve.
  double get drop {
    final p = _span(t, 0.22, 0.58) - 1;
    return 1 + 2.70158 * p * p * p + 1.70158 * p * p;
  }
  double get medalOpacity => _span(t, 0.22, 0.3);
  double get swing {
    final p = _span(t, 0.4, 0.95);
    if (p == 0 || p == 1) return 0;
    return 0.32 * math.pow(1 - p, 2) * math.sin(p * math.pi * 3.5);
  }

  /// The band of light across the metal, once the medal has come to rest.
  double? get glint {
    final p = _span(t, 0.58, 0.98);
    return p == 0 || p == 1 ? null : -0.2 + 1.4 * Curves.easeInOut.transform(p);
  }

  /// [child], a medal [size] wide, dropping in and swinging from the top
  /// of its ribbon — where a medal is held from.
  Widget medal(Widget child, double size) => Opacity(
        opacity: medalOpacity,
        child: Transform.translate(
          offset: Offset(0, -size * 1.4 * (1 - drop)),
          child: Transform.rotate(
            angle: swing,
            alignment: Alignment.topCenter,
            child: glint == null
                ? child
                : Semantics(
                    label: 'Personal best',
                    child: SizedBox(
                      width: size,
                      height: size * medalAspect,
                      child: CustomPaint(
                          painter: _MedalPainter(Medal.gold, glint: glint)),
                    ),
                  ),
          ),
        ),
      );
}

/// The medal as a PNG, struck by the same painter the app pins on a card.
///
/// For the spectator's page, which cannot run a `CustomPainter` — and where
/// porting this geometry to SVG would give something nearly right, which on
/// a badge measured off a reference is worse than nothing. The phone draws
/// it and serves the pixels.
Future<Uint8List> medalPng(Medal medal, {int size = 48}) async {
  final recorder = ui.PictureRecorder();
  final height = (size * _MedalPainter.aspect).round();
  _MedalPainter(medal).paint(
      Canvas(recorder), Size(size.toDouble(), height.toDouble()));
  final image = await recorder.endRecording().toImage(size, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Paints a medal [width] wide with its top-left corner at [topLeft] — for
/// a painter that has one to hang on something it draws, like the board's
/// divot under a best, and so cannot put a widget there. Its height is
/// [medalAspect] of its width, the way [PlaceMedal] is sized.
void paintMedal(Canvas canvas, Offset topLeft, double width, Medal medal,
    {double? glint}) {
  canvas.save();
  canvas.translate(topLeft.dx, topLeft.dy);
  _MedalPainter(medal, glint: glint)
      .paint(canvas, Size(width, width * _MedalPainter.aspect));
  canvas.restore();
}

/// A medal's height over its width.
const double medalAspect = _MedalPainter.aspect;

class _MedalPainter extends CustomPainter {
  const _MedalPainter(this.metal, {this.glint});

  final Medal metal;

  /// Where a band of light is running across it — see [glintShader].
  final double? glint;

  /// The ribbon, as fractions of the disc's diameter: how tall it stands,
  /// how much air is under it, how wide it is across the top, and how far
  /// each edge draws in per unit of height as it comes down.
  static const _ribbon = 0.585;
  static const _gap = 0.079;
  static const _left = 0.030;
  static const _right = 0.954;
  static const _taper = 0.37;

  /// The slot through it: where its left edge crosses the top, how wide it
  /// is measured across, and how far it leans per unit of height. It leans
  /// harder than the band's edges draw in, which is what runs the
  /// right-hand piece out to a point while the left one carries on.
  static const _slot = 0.396;
  static const _slotWidth = 0.169;
  static const _slotLean = 0.55;

  /// Height as a multiple of width: the disc, plus the ribbon and the gap
  /// above it.
  static const aspect = 1 + _ribbon + _gap;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w / 2;
    final center = Offset(w / 2, h - radius);
    final bounds = Offset.zero & size;

    // One layer for the medal, so the star is punched out of the disc.
    canvas.saveLayer(bounds, Paint());

    // One band rather than two straps: it tapers as it comes down, and a
    // leaning slot splits it into a long piece cut off square and a short
    // one running out to a point. See the class comment for why it is
    // lopsided; the numbers are measured, not invented.
    final ribbon = Paint()..shader = metal.shader(bounds);
    final foot = w * _ribbon;
    final band = Path()
      ..addPolygon([
        Offset(w * _left, 0),
        Offset(w * _right, 0),
        Offset(w * (_right - _taper * _ribbon), foot),
        Offset(w * (_left + _taper * _ribbon), foot),
      ], true);

    /// Everything to the right of the slot's edge through [x] — a
    /// half-plane, as a box big enough to reach past the badge.
    Path beyond(double x) => Path()
      ..addPolygon([
        Offset(w * (x - _slotLean), -w),
        Offset(w * (x + 2 * _slotLean), 2 * w),
        Offset(w * (x + 2 * _slotLean + 4), 2 * w),
        Offset(w * (x - _slotLean + 4), -w),
      ], true);

    canvas
      ..drawPath(
        Path.combine(PathOperation.difference, band, beyond(_slot)),
        ribbon,
      )
      ..drawPath(
        Path.combine(
            PathOperation.intersect, band, beyond(_slot + _slotWidth)),
        ribbon,
      )
      // The disc takes the ramp across its own square rather than across the
      // whole badge: a coin is lit corner to corner, and over the taller
      // bounds it only ever caught the pale end of the sheen.
      ..drawCircle(
        center,
        radius,
        Paint()
          ..shader =
              metal.shader(Rect.fromCircle(center: center, radius: radius)),
      )
      ..drawPath(
        _star(center, radius * 0.58),
        Paint()..blendMode = BlendMode.clear,
      );
    // On the metal only: source-atop keeps the light off the star's hole
    // and off the air round the ribbon.
    if (glint != null) {
      canvas.drawRect(
        bounds,
        Paint()
          ..blendMode = BlendMode.srcATop
          ..shader = glintShader(bounds, glint!),
      );
    }
    canvas.restore();
  }

  /// A five-pointed star, one point straight up. Chunky rather than
  /// spindly: the points have to survive being a couple of pixels long.
  Path _star(Offset center, double outer) {
    final inner = outer * 0.5;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_MedalPainter old) =>
      old.metal != metal || old.glint != glint;
}
