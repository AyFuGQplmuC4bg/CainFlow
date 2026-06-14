import 'package:flutter/material.dart';

import '../../nodes/node_definition.dart';
import '../workbench_signals.dart';
import 'node_image_thumbnail.dart';

/// Base card size for a node with up to two ports and no thumbnail.
const workbenchNodeSize = Size(220, 150);

/// Fixed height of a single port row, so connection anchors can be computed
/// deterministically without measuring the rendered widget.
const double kPortRowHeight = 24;

/// Inner padding of the card (matches the `EdgeInsets.all` below).
const double _kCardPadding = 14;

/// Extra height added to the thumbnail-bearing cards.
const double _kThumbnailExtra = 56;

/// Total rendered height of a node card, shared by [NodeCard] and the
/// connection painter so anchors line up exactly.
double nodeCardHeight(NodeDefinition? definition, {bool hasImage = false}) {
  final portRows = _portRowCount(definition);
  final extraPortRows = (portRows - 2).clamp(0, 6);
  return workbenchNodeSize.height +
      extraPortRows * 26.0 +
      (hasImage ? _kThumbnailExtra : 0);
}

int _portRowCount(NodeDefinition? definition) {
  final inputs = definition?.inputPorts.length ?? 0;
  final outputs = definition?.outputPorts.length ?? 0;
  return inputs > outputs ? inputs : outputs;
}

/// Y offset (from the card top) of the center of port [portIndex] on the
/// input or output side. Ports render as a bottom-aligned column, so the
/// last port sits one row-height above the card's bottom padding.
double portAnchorY(
  NodeDefinition? definition, {
  required bool isOutput,
  required int portIndex,
  required bool hasImage,
}) {
  final count = isOutput
      ? (definition?.outputPorts.length ?? 1)
      : (definition?.inputPorts.length ?? 1);
  final n = count < 1 ? 1 : count;
  final height = nodeCardHeight(definition, hasImage: hasImage);
  final bottom = height - _kCardPadding;
  // Row i (0-based from the top of the cluster) center:
  return bottom - (n - portIndex) * kPortRowHeight + kPortRowHeight / 2;
}

class NodeCard extends StatelessWidget {
  const NodeCard({
    super.key,
    required this.node,
    required this.definition,
    required this.selected,
    required this.onSelect,
    required this.onMove,
    this.onOpen,
    this.onPortTap,
    this.pendingFromPort,
    this.imagePayload,
  });

  final WorkbenchNode node;
  final NodeDefinition? definition;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<NodeOffset> onMove;

  /// Tapping the node body selects it and opens its editor (param sheet).
  final VoidCallback? onOpen;

  /// Called when a port dot is tapped. [isOutput] distinguishes the origin
  /// (output) from the destination (input) of a point-select connection.
  final void Function(NodePortDefinition port, bool isOutput)? onPortTap;

  /// Output port name currently armed as a pending connection origin on this
  /// node, highlighted to show the user where the link starts.
  final String? pendingFromPort;

  /// Image output payload (`{kind: url|asset}`) to preview inside the card.
  final Map<String, dynamic>? imagePayload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Card grows for nodes with more than two stacked ports, plus an optional
    // thumbnail. Height is computed by the shared helper so connection anchors
    // line up exactly with the rendered ports.
    final cardHeight =
        nodeCardHeight(definition, hasImage: imagePayload != null);

    return GestureDetector(
      onTap: () {
        onSelect();
        onOpen?.call();
      },
      onPanStart: (_) => onSelect(),
      onPanUpdate: (details) {
        onMove(NodeOffset(details.delta.dx, details.delta.dy));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: workbenchNodeSize.width,
        height: cardHeight,
        padding: const EdgeInsets.all(_kCardPadding),
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
            if (imagePayload != null) ...[
              const SizedBox(height: 8),
              NodeImageThumbnail(payload: imagePayload!, size: 48),
            ],
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PortCluster(
                  ports: definition?.inputPorts ?? const [],
                  fallbackLabel: 'in',
                  color: theme.colorScheme.secondary,
                  onPortTap: onPortTap == null
                      ? null
                      : (port) => onPortTap!(port, false),
                ),
                _PortCluster(
                  ports: definition?.outputPorts ?? const [],
                  fallbackLabel: 'out',
                  color: theme.colorScheme.primary,
                  reverse: true,
                  pendingPort: pendingFromPort,
                  onPortTap: onPortTap == null
                      ? null
                      : (port) => onPortTap!(port, true),
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
    this.onPortTap,
    this.pendingPort,
  });

  final List<NodePortDefinition> ports;
  final String fallbackLabel;
  final Color color;
  final bool reverse;
  final ValueChanged<NodePortDefinition>? onPortTap;
  final String? pendingPort;

  @override
  Widget build(BuildContext context) {
    if (ports.isEmpty) {
      return SizedBox(
        width: 82,
        child: Row(
          mainAxisAlignment:
              reverse ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [Text(fallbackLabel)],
        ),
      );
    }

    return SizedBox(
      width: 90,
      child: Column(
        crossAxisAlignment:
            reverse ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final port in ports)
            _PortRow(
              port: port,
              color: color,
              reverse: reverse,
              armed: pendingPort == port.name,
              onTap: onPortTap == null ? null : () => onPortTap!(port),
            ),
        ],
      ),
    );
  }
}

class _PortRow extends StatelessWidget {
  const _PortRow({
    required this.port,
    required this.color,
    required this.reverse,
    required this.armed,
    this.onTap,
  });

  final NodePortDefinition port;
  final Color color;
  final bool reverse;
  final bool armed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: armed ? 13 : 9,
      height: armed ? 13 : 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: armed ? Border.all(color: Colors.white, width: 2) : null,
      ),
    );
    final text = Flexible(
      child: Text(
        port.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: reverse ? TextAlign.end : TextAlign.start,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: kPortRowHeight,
        child: Row(
          mainAxisAlignment:
              reverse ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: reverse
              ? [text, const SizedBox(width: 6), dot]
              : [dot, const SizedBox(width: 6), text],
        ),
      ),
    );
  }
}
