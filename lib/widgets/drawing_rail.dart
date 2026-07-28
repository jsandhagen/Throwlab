import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'drawing_canvas.dart';

/// Vertical, collapsible tool rail anchored to the bottom-right corner of
/// the video, kept short enough for a landscape phone: the tools that build
/// on a drag (line, arrow, curved arrow) share one menu button, and the pen
/// weight and colour are menus too, so the column stays ~7 buttons instead
/// of the 17 controls it offers. A dedicated chevron button at the bottom —
/// always there, open or closed, and never also a tool — collapses the rail
/// down to just that button, keeping the right-center and upper-right of
/// the frame — where the throw happens — unobstructed.
class DrawingRail extends StatefulWidget {
  const DrawingRail({
    super.key,
    required this.controller,
    this.initiallyOpen = true,
  });

  final DrawingController controller;

  /// Whether the tools are showing to begin with. The comparison screen
  /// starts collapsed: its video area is already split between two clips,
  /// and drawing is the occasional job there rather than the main one.
  final bool initiallyOpen;

  @override
  State<DrawingRail> createState() => _DrawingRailState();
}

class _DrawingRailState extends State<DrawingRail> {
  late bool _open = widget.initiallyOpen;

  DrawingController get controller => widget.controller;

  /// The two modes worth a button of their own: scrubbing without drawing,
  /// and the freehand pen.
  static const _directTools = [
    (DrawTool.none, Icons.pan_tool_alt, 'Scrub only'),
    (DrawTool.pen, Icons.draw, 'Freehand pen'),
  ];

  /// The measured shapes, sharing one menu button that shows whichever is
  /// selected — four more icons on the rail is what ran it off a landscape
  /// screen.
  static const _shapeTools = [
    (DrawTool.line, Icons.timeline, 'Straight line'),
    (DrawTool.arrow, Icons.arrow_right_alt, 'Arrow (drag tail to head)'),
    (
      DrawTool.curvedArrow,
      Icons.turn_slight_right,
      'Curved arrow (trace a path, head where you lift)'
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
  /// 48px tap padding around each one is invisible height the rail cannot
  /// spare on a landscape phone, where the whole column has to fit above
  /// the transport.
  ButtonStyle _styleFor(bool selected, ColorScheme scheme) =>
      IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: selected ? scheme.primaryContainer : null,
      );

  Widget _toolButton(DrawTool tool, IconData icon, String tip,
      ColorScheme scheme) {
    return IconButton(
      tooltip: tip,
      iconSize: 20,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 36),
      isSelected: controller.tool == tool,
      style: _styleFor(controller.tool == tool, scheme),
      icon: Icon(icon),
      onPressed: () => controller.tool = tool,
    );
  }

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
      position: PopupMenuPosition.under,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final (shapeTool, shapeIcon, shapeTip) = _shape;
        return Material(
          color: scheme.surface.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_open) ...[
                  _toolButton(_directTools[0].$1, _directTools[0].$2,
                      _directTools[0].$3, scheme),
                  _toolButton(_directTools[1].$1, _directTools[1].$2,
                      _directTools[1].$3, scheme),
                  // Lines and arrows share a button: same gesture, and
                  // three more icons is what ran the rail off a
                  // landscape screen.
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
                  const SizedBox(height: 2),
                  _menuButton<double>(
                    key: const ValueKey('rail-width'),
                    tooltip: 'Line width',
                    icon: _weightPreview(
                        controller.strokeWidth, controller.color),
                    selected: false,
                    items: [
                      for (final (index, width) in kStrokeWidths.indexed)
                        PopupMenuItem(
                          value: width,
                          child: Row(
                            children: [
                              SizedBox(
                                  width: 24,
                                  child: _weightPreview(
                                      width, controller.color)),
                              const SizedBox(width: 12),
                              Text('${_thicknessLabels[index]} line'),
                            ],
                          ),
                        ),
                    ],
                    onSelected: (width) => controller.strokeWidth = width,
                  ),
                  _menuButton<Color>(
                    key: const ValueKey('rail-colour'),
                    tooltip: 'Colour',
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
                      for (final (index, color)
                          in kAnnotationColors.indexed)
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
                  const SizedBox(height: 2),
                  IconButton(
                    tooltip: 'Undo',
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    style: _styleFor(false, scheme),
                    constraints: const BoxConstraints.tightFor(
                        width: 40, height: 36),
                    icon: const Icon(Icons.undo),
                    onPressed: controller.undo,
                  ),
                  _menuButton<String>(
                    key: const ValueKey('rail-more'),
                    tooltip: 'More',
                    icon: const Icon(Icons.more_horiz, size: 20),
                    selected: false,
                    items: const [
                      PopupMenuItem(
                        value: 'clear',
                        child: Row(children: [
                          Icon(Icons.layers_clear, size: 20),
                          SizedBox(width: 12),
                          Text('Clear drawings'),
                        ]),
                      ),
                    ],
                    onSelected: (choice) {
                      if (choice == 'clear') controller.clear();
                    },
                  ),
                  Divider(
                    height: 5,
                    thickness: 1,
                    indent: 8,
                    endIndent: 8,
                    color: scheme.onSurface.withOpacity(0.2),
                  ),
                ],
                // Collapsing the rail is its own button, always in the same
                // spot at the bottom, open or closed — never buried in a
                // menu and never doubling as a tool, so there is one fixed
                // target for getting the tools out of the way and back.
                IconButton(
                  key: const ValueKey('rail-collapse'),
                  tooltip: _open ? 'Hide drawing tools' : 'Show drawing tools',
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  style: _styleFor(false, scheme),
                  constraints:
                      const BoxConstraints.tightFor(width: 40, height: 36),
                  icon: Icon(_open
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up),
                  onPressed: () => setState(() => _open = !_open),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Names for the annotation colours, in [kAnnotationColors] order, for the
/// rail's colour menu.
const _colorNames = ['Orange', 'Green', 'Cyan', 'Pink', 'White'];
