import 'package:flutter/material.dart';

import '../../nodes/node_definition.dart';
import '../workbench_signals.dart';

const workbenchNodeSize = Size(220, 132);

class NodeCard extends StatelessWidget {
  const NodeCard({
    super.key,
    required this.node,
    required this.definition,
    required this.selected,
    required this.onSelect,
    required this.onMove,
  });

  final WorkbenchNode node;
  final NodeDefinition? definition;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<NodeOffset> onMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onSelect,
      onPanStart: (_) => onSelect(),
      onPanUpdate: (details) {
        onMove(NodeOffset(details.delta.dx, details.delta.dy));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: workbenchNodeSize.width,
        height: workbenchNodeSize.height,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
            if (selected)
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.24),
                blurRadius: 22,
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(node.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              definition?.description ?? node.type,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PortCluster(
                  ports: definition?.inputPorts ?? const [],
                  fallbackLabel: 'in',
                  color: theme.colorScheme.secondary,
                ),
                _PortCluster(
                  ports: definition?.outputPorts ?? const [],
                  fallbackLabel: 'out',
                  color: theme.colorScheme.primary,
                  reverse: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PortCluster extends StatelessWidget {
  const _PortCluster({
    required this.ports,
    required this.fallbackLabel,
    required this.color,
    this.reverse = false,
  });

  final List<NodePortDefinition> ports;
  final String fallbackLabel;
  final Color color;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final label = ports.isEmpty ? fallbackLabel : ports.first.label;
    final dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    final text = Flexible(
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return SizedBox(
      width: 82,
      child: Row(
        mainAxisAlignment:
            reverse ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: reverse
            ? [text, const SizedBox(width: 6), dot]
            : [dot, const SizedBox(width: 6), text],
      ),
    );
  }
}
