import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'drawing_canvas.dart';

/// The drawing tools, run along an edge of the frame and anchored in its
/// bottom-right corner.
///
/// Which edge is [axis], and it follows the shape of the picture rather than
/// the shape of the screen. A clip is filmed on its side, so held that way
/// the frame fills the screen and the tools have to sit on it somewhere:
/// they go up the right edge, out past the release and the flight, which is
/// the least of the picture to stand in front of. Held upright the same
/// clip is letterboxed into a band of black above and below, so the tools
/// lie along the bottom instead and cover none of the frame at all.
///
/// Either way they run out of room before they run out of controls — a
/// phone gives about 300 logical pixels of height on its side and 360 of
/// width upright, and the tools want 341. So the rail grows a second run
/// rather than shrinking its buttons: a 34 px target is one a thumb misses
/// at a track. The seam is where the tools are already grouped — what a
/// tool is picked with in the first run, what is done to the drawing in the
/// second — and the chevron is still last, so it is still in the corner.
///
/// The shapes that build on a drag (line, arrow, curved arrow, circle,
/// angle) share one menu button that wears whichever is selected, and the
/// pen weight and color are menus too, so the rail stays nine controls long
/// rather than the 18 it offers. Undo, redo and clear are not among them —
/// they are what a drawing hand reaches for most, and a tool that has to be
/// hunted for in a menu is one nobody uses. Clear is safe to leave in the
/// open because undo brings the whole frame back.
///
/// A dedicated chevron on the end — always there, open or closed, and never
/// also a tool — collapses the rail down to just that button, so there is
/// one fixed target for getting the tools out of the way and back.
class DrawingRail extends StatefulWidget {
  const DrawingRail({
    super.key,
    required this.controller,
    this.initiallyOpen = true,
    this.axis = Axis.vertical,
  });

  final DrawingController controller;

  /// Whether the tools are showing to begin with. The comparison screen
  /// starts collapsed: its video area is already split between two clips,
  /// and drawing is the occasional job there rather than the main one.
  final bool initiallyOpen;

  /// Which way the tools run: a column up an edge of the frame, or a bar
  /// along one.
  final Axis axis;

  @override
  State<DrawingRail> createState() => _DrawingRailState();
}

class _DrawingRailState extends State<DrawingRail> {
  late bool _open = widget.initiallyOpen;

  DrawingController get controller => widget.controller;

  bool get _upright => widget.axis == Axis.vertical;

  /// The two modes worth a button of their own: scrubbing without drawing,
  /// and the freehand pen.
  static const _directTools = [
    (DrawTool.none, Icons.pan_tool_alt, 'Scrub only'),
    (DrawTool.pen, Icons.draw, 'Freehand pen'),
  ];

  /// The shapes a drag builds, sharing one menu button that shows whichever
  /// is selected — five more icons is more than an edge of a phone has room
  /// for.
  static const _shapeTools = [
    (DrawTool.line, Icons.timeline, 'Straight line'),
    (DrawTool.arrow, Icons.arrow_right_alt, 'Arrow (drag tail to head)'),
    (
      DrawTool.curvedArrow,
      Icons.turn_slight_right,
      'Curved arrow (trace a path, head where you lift)'
    ),
    (
      DrawTool.circle,
      Icons.circle_outlined,
      'Circle (press the middle, drag out to the rim)'
    ),
    (DrawTool.angle, Icons.square_foot, 'Angle (tap 3 points, vertex second)'),
  ];

  static const _thicknessLabels = ['Thin', 'Medium', 'Thick'];

  /// The shape the menu button offers on a single tap — whichever shape is
  /// active, or the plain arrow before one has been chosen.
  (DrawTool, IconData, String) get _shape => _shapeTools.firstWhere(
        (entry) => entry.$1 == controller.tool,
        orElse: () => _shapeTools[1],
      );

  /// Rail buttons are drawn 40x36 and sized to match: Material's default
  /// 48px tap padding around each one is invisible room the rail cannot
  /// spare on a phone, where all nine controls have to fit along an edge.
  ButtonStyle _styleFor(bool selected, ColorScheme scheme) =>
      IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: selected ? scheme.primaryContainer : null,
      );

  static const _slotWidth = 40.0;
  static const _slotHeight = 36.0;
  static const _sidePadding = 4.0;
  static const _slot =
      BoxConstraints.tightFor(width: _slotWidth, height: _slotHeight);

  Widget _toolButton(
      DrawTool tool, IconData icon, String tip, ColorScheme scheme) {
    return IconButton(
      tooltip: tip,
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: _slot,
      isSelected: controller.tool == tool,
      style: _styleFor(controller.tool == tool, scheme),
      icon: Icon(icon),
      onPressed: () => controller.tool = tool,
    );
  }

  /// An action on the drawing itself, grayed out when there is nothing for
  /// it to act on — an undo arrow that does nothing is worse than one that
  /// says so.
  Widget _actionButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    required ColorScheme scheme,
  }) =>
      IconButton(
        key: key,
        tooltip: tooltip,
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: _slot,
        style: _styleFor(false, scheme),
        icon: Icon(icon),
        onPressed: onPressed,
      );

  /// A rail-sized menu button: tapping the icon picks [onTap] straight
  /// away, the small chevron opens the rest.
  Widget _menuButton<T>({
    required Key key,
    required String tooltip,
    required Widget icon,
    required bool selected,
    required List<PopupMenuEntry<T>> items,
    required ValueChanged<T> onSelected,
    VoidCallback? onTap,
    ColorScheme? scheme,
  }) {
    final button = PopupMenuButton<T>(
      key: key,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      // Nothing under the bar to hang a menu in — the transport is there —
      // so the menus come up over the frame instead.
      position: PopupMenuPosition.over,
      itemBuilder: (context) => items,
      onSelected: onSelected,
      child: Container(
        width: 40,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected && scheme != null
              ? scheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const Icon(Icons.arrow_drop_down, size: 14),
          ],
        ),
      ),
    );
    return button;
  }

  /// A bar drawn at [width], the way that pen paints.
  Widget _weightPreview(double width, Color color) => Container(
        width: 18,
        height: math.max(2, width),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(width),
        ),
      );

  /// The breath between groups of buttons, along the rail's own axis.
  static const _gapExtent = 2.0;
  Widget get _gap => SizedBox(
        width: _upright ? 0 : _gapExtent,
        height: _upright ? _gapExtent : 0,
      );

  /// The rule that cuts the collapse chevron off from the tools, drawn
  /// across the rail. It is given a size of its own on the other axis
  /// because a second run lays it out beside children that are no longer
  /// the ones setting the measurement it would inherit.
  static const _ruleExtent = 5.0;
  Widget _rule(ColorScheme scheme) {
    final color = scheme.onSurface.withOpacity(0.2);
    return _upright
        ? SizedBox(
            width: _slotWidth,
            child: Divider(
                height: _ruleExtent,
                thickness: 1,
                indent: 8,
                endIndent: 8,
                color: color),
          )
        : SizedBox(
            height: _slotHeight,
            child: VerticalDivider(
                width: _ruleExtent,
                thickness: 1,
                indent: 6,
                endIndent: 6,
                color: color),
          );
  }

  /// What the rail measures as a single run — five controls for the pen,
  /// four for the drawing, two gaps, the rule, and the padding around the
  /// lot. It comes out within a few pixels of 340 either way up.
  double get _oneRunExtent =>
      (_upright ? _slotHeight : _slotWidth) * 9 +
      _gapExtent * 2 +
      _ruleExtent +
      _sidePadding * 2;

  /// Which way the chevron points: away from the tools when they are
  /// showing, back toward them when they are not. The rail is anchored at
  /// the chevron's end, in the bottom-right corner, so 'away' is down a
  /// column and to the right along a bar.
  IconData get _chevron => _upright
      ? (_open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up)
      : (_open ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_left);

  /// What is armed and what it draws with — the half of the bar a tool is
  /// picked out of.
  List<Widget> _penControls(ColorScheme scheme) {
    final (shapeTool, shapeIcon, shapeTip) = _shape;
    return [
      _toolButton(
          _directTools[0].$1, _directTools[0].$2, _directTools[0].$3, scheme),
      _toolButton(
          _directTools[1].$1, _directTools[1].$2, _directTools[1].$3, scheme),
      // Lines, arrows, circles and angles share a button: all
      // built on one drag or a few taps, and five more icons is
      // what ran the rail off a landscape screen.
      _menuButton<DrawTool>(
        key: const ValueKey('rail-shapes'),
        tooltip: shapeTip,
        icon: Icon(shapeIcon, size: 20),
        selected: controller.tool == shapeTool,
        scheme: scheme,
        items: [
          for (final (tool, icon, tip) in _shapeTools)
            PopupMenuItem(
              value: tool,
              child: Row(
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(width: 12),
                  Flexible(child: Text(tip.split(' (').first)),
                ],
              ),
            ),
        ],
        onSelected: (tool) => controller.tool = tool,
      ),
      _gap,
      _menuButton<double>(
        key: const ValueKey('rail-width'),
        tooltip: 'Line width',
        icon: _weightPreview(controller.strokeWidth, controller.color),
        selected: false,
        items: [
          for (final (index, width) in kStrokeWidths.indexed)
            PopupMenuItem(
              value: width,
              child: Row(
                children: [
                  SizedBox(
                      width: 24,
                      child: _weightPreview(width, controller.color)),
                  const SizedBox(width: 12),
                  Text('${_thicknessLabels[index]} line'),
                ],
              ),
            ),
        ],
        onSelected: (width) => controller.strokeWidth = width,
      ),
      _menuButton<Color>(
        key: const ValueKey('rail-color'),
        tooltip: 'Color',
        icon: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: controller.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
        ),
        selected: false,
        items: [
          for (final (index, color) in kAnnotationColors.indexed)
            PopupMenuItem(
              value: color,
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: controller.color == color
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(_colorNames[index]),
                ],
              ),
            ),
        ],
        onSelected: (color) => controller.color = color,
      ),
    ];
  }

  /// What is done to the drawing rather than with it. These three are in
  /// the open on purpose: a wrong stroke is undone where it happened rather
  /// than through a menu, and clear is only as final as one tap of undo.
  List<Widget> _actionControls(ColorScheme scheme) => [
        _actionButton(
          key: const ValueKey('rail-undo'),
          tooltip: 'Undo',
          icon: Icons.undo,
          onPressed: controller.canUndo ? controller.undo : null,
          scheme: scheme,
        ),
        _actionButton(
          key: const ValueKey('rail-redo'),
          tooltip: 'Redo',
          icon: Icons.redo,
          onPressed: controller.canRedo ? controller.redo : null,
          scheme: scheme,
        ),
        _actionButton(
          key: const ValueKey('rail-clear'),
          tooltip: 'Clear drawings',
          icon: Icons.layers_clear,
          onPressed: controller.annotations.isEmpty ? null : controller.clear,
          scheme: scheme,
        ),
      ];

  /// Collapsing the bar is its own button, always in the same spot on the
  /// end of it, open or closed — never buried in a menu and never doubling
  /// as a tool, so there is one fixed target for getting the tools out of
  /// the way and back.
  Widget _collapseButton(ColorScheme scheme) => IconButton(
        key: const ValueKey('rail-collapse'),
        tooltip: _open ? 'Hide drawing tools' : 'Show drawing tools',
        iconSize: 20,
        padding: EdgeInsets.zero,
        style: _styleFor(false, scheme),
        constraints: _slot,
        icon: Icon(_chevron),
        onPressed: () => setState(() => _open = !_open),
      );

  /// One run of controls, along the rail's own axis.
  Widget _run(List<Widget> children) => Flex(
        direction: widget.axis,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );

  /// The two runs side by side, across the rail: a column each way up a
  /// vertical rail, a row each way along a horizontal one. Both are aligned
  /// to the far end, so the second run finishes in the same corner the
  /// first one does.
  Widget _runs(List<Widget> first, List<Widget> second) => Flex(
        direction: _upright ? Axis.horizontal : Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [_run(first), _run(second)],
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          // Out of room along the edge and the rail grows a second run
          // rather than shrinking its buttons: a 34 px target is one a
          // thumb misses at a track, and there is room going spare across
          // the rail in both orientations. The seam is where the tools are
          // already grouped — what a tool is picked with in the first run,
          // what is done to the drawing in the second, the chevron still
          // last and so still in the corner.
          final room = _upright ? constraints.maxHeight : constraints.maxWidth;
          final oneRun = room >= _oneRunExtent;
          final pen = _penControls(scheme);
          final actions = [..._actionControls(scheme), _rule(scheme)];
          return Material(
            color: scheme.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: _upright
                  ? const EdgeInsets.symmetric(vertical: _sidePadding)
                  : const EdgeInsets.symmetric(horizontal: _sidePadding),
              child: !_open
                  ? _run([_collapseButton(scheme)])
                  : oneRun
                      ? _run(
                          [...pen, _gap, ...actions, _collapseButton(scheme)])
                      : _runs(pen, [...actions, _collapseButton(scheme)]),
            ),
          );
        },
      ),
    );
  }
}

/// Names for the annotation colors, in [kAnnotationColors] order, for the
/// rail's color menu.
const _colorNames = ['Orange', 'Green', 'Cyan', 'Pink', 'White'];
