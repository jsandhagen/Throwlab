/// The library's angular chrome: a cut-corner silhouette, the search field
/// wearing it, and the grouping bar whose slants come from the sector.
library;

import 'package:flutter/material.dart';

import 'sector_art.dart';

/// Two opposite corners cut, the other two left square. Shared by the
/// search field and the grouping bar so the header reads as one shape
/// rather than a row of unrelated controls.
ShapeBorder angularShape(double cut, {BorderSide side = BorderSide.none}) =>
    BeveledRectangleBorder(
      side: side,
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(cut),
        bottomRight: Radius.circular(cut),
      ),
    );

/// The library's search box. A plain [TextField] inside the angular
/// silhouette — quiet until focused, when its outline lights up.
class AngularSearchField extends StatefulWidget {
  const AngularSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.hintText = 'Search throws',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final String hintText;

  @override
  State<AngularSearchField> createState() => _AngularSearchFieldState();
}

class _AngularSearchFieldState extends State<AngularSearchField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final focused = _focus.hasFocus;
    final empty = widget.controller.text.isEmpty;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: angularShape(
          14,
          side: BorderSide(
            color: focused
                ? scheme.primary.withOpacity(0.7)
                : scheme.outlineVariant.withOpacity(0.35),
            width: focused ? 1.4 : 1,
          ),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHighest.withOpacity(0.42),
            scheme.surfaceContainerHighest.withOpacity(0.14),
          ],
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15),
        cursorColor: scheme.primary,
        cursorWidth: 1.5,
        onChanged: (value) {
          widget.onChanged(value);
          setState(() {}); // the clear button appears with the first letter
        },
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hintText,
          hintStyle: TextStyle(
              fontSize: 15, color: scheme.onSurfaceVariant.withOpacity(0.7)),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: scheme.onSurfaceVariant.withOpacity(0.8)),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: empty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  iconSize: 18,
                  icon: const Icon(Icons.close_rounded),
                  color: scheme.onSurfaceVariant,
                  onPressed: () {
                    widget.onClear();
                    setState(() {});
                  },
                ),
          contentPadding: const EdgeInsets.fromLTRB(0, 13, 12, 13),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// One choice in an [AngularSegmentedBar].
class AngularSegment<T> {
  const AngularSegment({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;
  final String label;
}

/// Connected sections in one bar, painted rather than assembled: a slanted
/// block slides under the active one and leaning dividers separate the
/// rest. The slant is the sector's half-angle, so the header leans at the
/// same 17.46° the sector opens from the circle.
class AngularSegmentedBar<T> extends StatelessWidget {
  const AngularSegmentedBar({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<AngularSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index =
        segments.indexWhere((segment) => segment.value == value).toDouble();
    return SizedBox(
      height: 44,
      child: TweenAnimationBuilder<double>(
        // Only `end` matters after the first build: changing it slides the
        // block from wherever it is to the segment just tapped.
        tween: Tween<double>(begin: index, end: index),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        builder: (context, position, child) => CustomPaint(
          painter: _SegmentedBarPainter(
            position: position,
            count: segments.length,
            surface: scheme.surfaceContainerHighest,
            accent: scheme.primary,
            outline: scheme.outlineVariant,
          ),
          child: child,
        ),
        child: Row(
          children: [
            for (final segment in segments)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(segment.value),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(segment.icon,
                          size: 15,
                          color: segment.value == value
                              ? scheme.primary
                              : scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      // Shrinks rather than overflowing when the segment is
                      // squeezed by a large system text size.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            segment.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 13,
                              letterSpacing: 0.2,
                              color: segment.value == value
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: segment.value == value
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedBarPainter extends CustomPainter {
  const _SegmentedBarPainter({
    required this.position,
    required this.count,
    required this.surface,
    required this.accent,
    required this.outline,
  });

  /// Which segment the block sits on; fractional while it slides.
  final double position;
  final int count;
  final Color surface;
  final Color accent;
  final Color outline;

  static const double _cut = 12;

  /// The slanted edges lean at the sector's half-angle.
  double _lean(Size size) => size.height / 2 * sectorLean;

  /// The same two-corner cut as [angularShape], drawn by hand so the fill,
  /// the block and the dividers can all be clipped to it.
  Path _silhouette(Size size) => Path()
    ..moveTo(_cut, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height - _cut)
    ..lineTo(size.width - _cut, size.height)
    ..lineTo(0, size.height)
    ..lineTo(0, _cut)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bar = _silhouette(size);
    final lean = _lean(size);

    canvas.save();
    canvas.clipPath(bar);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surface.withOpacity(0.42), surface.withOpacity(0.14)],
        ).createShader(rect),
    );

    final segment = size.width / count;
    final left = position * segment;
    // A parallelogram, leaning right, one segment wide — except at the
    // ends, where the outer edge squares up so the block fills the bar's
    // corner instead of leaving a wedge of background in it. Both blend
    // over the last segment of travel, so the squaring off arrives with
    // the block rather than snapping when it lands.
    final atStart = (1 - position).clamp(0.0, 1.0);
    final atEnd = (position - (count - 2)).clamp(0.0, 1.0);
    final block = Path()
      ..moveTo(left + lean - 2 * lean * atStart, 0)
      ..lineTo(left + segment + lean, 0)
      ..lineTo(left + segment - lean + 2 * lean * atEnd, size.height)
      ..lineTo(left - lean, size.height)
      ..close();
    canvas.drawPath(
      block,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.34), accent.withOpacity(0.10)],
        ).createShader(block.getBounds()),
    );
    canvas.drawPath(
      block,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = accent.withOpacity(0.45),
    );
    // Bright underline along the block's slanted foot.
    canvas.drawLine(
      Offset(left - lean, size.height - 1),
      Offset(left + segment - lean + 2 * lean * atEnd, size.height - 1),
      Paint()
        ..strokeWidth = 2
        ..color = accent.withOpacity(0.85),
    );

    for (var i = 1; i < count; i++) {
      final x = i * segment;
      // Fade a divider down as the block slides up against it, but never
      // out — the bar should read as sections whatever is selected.
      final gap = [(x - left).abs(), (x - left - segment).abs()]
              .reduce((a, b) => a < b ? a : b) /
          segment;
      final opacity = 0.16 + gap.clamp(0.0, 1.0) * 0.4;
      final top = Offset(x + lean, 8);
      final bottom = Offset(x - lean, size.height - 8);
      canvas.drawLine(
        top,
        bottom,
        Paint()
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              outline.withOpacity(0),
              outline.withOpacity(opacity),
              outline.withOpacity(0),
            ],
          ).createShader(Rect.fromPoints(top, bottom)),
      );
    }
    canvas.restore();

    canvas.drawPath(
      bar,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline.withOpacity(0.35),
    );
  }

  @override
  bool shouldRepaint(_SegmentedBarPainter old) =>
      old.position != position ||
      old.count != count ||
      old.surface != surface ||
      old.accent != accent ||
      old.outline != outline;
}
