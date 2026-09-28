import 'package:flutter/material.dart';

import '../widgets/sector_art.dart';
import 'release_calculator_screen.dart';
import 'unit_converter_screen.dart';

/// The tools that work a number out rather than record one, behind the
/// calculator in the library's app bar.
///
/// A screen of its own rather than a popup menu, like the trophy's season
/// beside it: each tool is said in a line, which a menu has no room for,
/// and a second calculator is a card added here rather than a fourth icon
/// crowding the library's app bar.
class CalculatorsScreen extends StatelessWidget {
  const CalculatorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Calculators')),
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter:
                    SectorBackdropPainter(color: theme.colorScheme.primary),
              ),
            ),
          ),
          ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              _Tool(
                key: const ValueKey('tool-what-if'),
                icon: Icons.insights,
                title: 'What if',
                subtitle: 'Nudge a release — speed, angle, height — and see '
                    'what it is worth, or hold it against elite throwers.',
                open: () => const ReleaseCalculatorScreen(),
              ),
              _Tool(
                key: const ValueKey('tool-units'),
                icon: Icons.swap_horiz,
                title: 'Unit converter',
                subtitle: 'Marks between meters and feet, implements '
                    'between kilograms and pounds, and release speeds in '
                    'm/s, mph and km/h.',
                open: () => const UnitConverterScreen(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.open,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget Function() open;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: cardOverSector(scheme),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => open())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
