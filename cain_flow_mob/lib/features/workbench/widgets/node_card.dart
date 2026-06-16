import 'package:flutter/material.dart';

import '../../../app/theme/cain_tokens.dart';
import '../../execution/execution_signals.dart';
import '../../nodes/node_definition.dart';
import '../workbench_signals.dart';
import 'node_image_thumbnail.dart';

/// Base card size for a node with up to two ports and no thumbnail.
const workbenchNodeSize = Size(224, 152);

/// Maps a node type to its silkscreen band color + short code, grouping by
/// the kind of data the node deals in (text / image / control).
({Color color, String code}) _nodeBadge(String type) {
  if (type.startsWith('Control')) {
    return (color: CainTokens.signalControl, code: _code(type));
  }
  if (type.startsWith('Image') || type == 'CameraControl') {
    return (color: CainTokens.signalImage, code: _code(type));
  }
  return (color: CainTokens.signalText, code: _code(type));
}

/// A 2-3 char silkscreen code derived from the type's capital letters.
String _code(String type) {
  final caps = type.replaceAll(RegExp('[^A-Z]'), '');
  if (caps.length >= 2) return caps.substring(0, caps.length.clamp(0, 3));
  return type.substring(0, type.length.clamp(0, 3)).toUpperCase();
}

/// Fixed height of a single port row, so connection anchors can be computed
/// deterministically without measuring the rendered widget.
const double kPortRowHeight = 24;

/// Inner padding of the card (matches the `EdgeInsets.all` below).
const double _kCardPadding = 14;

/// Image preview size inside a node card. Keep this in sync with
/// [_kThumbnailExtra] so port anchors match the rendered card height.
const double _kNodeThumbnailSize = 76;

/// Extra height added to the thumbnail-bearing cards.
const double _kThumbnailExtra = _kNodeThumbnailSize + 8;

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
    this.runState,
    this.pollText,
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

  /// Current execution state for run-time styling (border/glow/status dot).
  final NodeRunState? runState;

  /// Transient progress text shown while running (e.g. async polling).
  final String? pollText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Card grows for nodes with more than two stacked ports, plus an optional
    // thumbnail. Height is computed by the shared helper so connection anchors
    // line up exactly with the rendered ports.
    final cardHeight = nodeCardHeight(
      definition,
      hasImage: imagePayload != null,
    );

    final runColor = _runStateColor(theme, runState);
    final borderColor = selected
        ? theme.colorScheme.primary
        : (runColor ?? theme.colorScheme.outlineVariant);
    final borderWidth = selected || runColor != null ? 2.0 : 1.0;
    final badge = _nodeBadge(node.type);

    return GestureDetector(
      onTap: () {
        onSelect();
        onOpen?.call();
      },
      onPanStart: (_) => onSelect(),
      onPanUpdate: (details) {
        onMove(NodeOffset(details.delta.dx, details.delta.dy));
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: workbenchNodeSize.width,
            height: cardHeight,
            decoration: BoxDecoration(
              color: CainTokens.panelHigh,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
                if (selected)
                  BoxShadow(
                    color: CainTokens.phosphor.withValues(alpha: 0.28),
                    blurRadius: 20,
                  )
                else if (runState == NodeRunState.running)
                  BoxShadow(
                    color: (runColor ?? CainTokens.phosphor).withValues(
                      alpha: 0.45,
                    ),
                    blurRadius: 22,
                  ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Opacity(
              opacity: runState == NodeRunState.skipped ? 0.5 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Silkscreen header band: type code chip + title.
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: badge.color.withValues(alpha: 0.12),
                      border: Border(
                        bottom: BorderSide(
                          color: badge.color.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: badge.color.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            badge.code,
                            style: CainTokens.mono(
                              9.5,
                              weight: FontWeight.w700,
                              color: badge.color,
                              spacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            node.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CainTokens.display(
                              12.5,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _kCardPadding,
                        8,
                        _kCardPadding,
                        _kCardPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pollText ?? definition?.description ?? node.type,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CainTokens.mono(
                              10.5,
                              color: pollText != null
                                  ? CainTokens.phosphor
                                  : CainTokens.inkFaint,
                            ),
                          ),
                          if (imagePayload != null) ...[
                            const SizedBox(height: 8),
                            NodeImageThumbnail(
                              payload: imagePayload!,
                              size: _kNodeThumbnailSize,
                            ),
                          ],
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _PortCluster(
                                ports: definition?.inputPorts ?? const [],
                                fallbackLabel: 'in',
                                color: CainTokens.signalText,
                                onPortTap: onPortTap == null
                                    ? null
                                    : (port) => onPortTap!(port, false),
                              ),
                              _PortCluster(
                                ports: definition?.outputPorts ?? const [],
                                fallbackLabel: 'out',
                                color: CainTokens.signalText,
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
                  ),
                ],
              ),
            ),
          ),
          if (runState != null)
            Positioned(
              top: -6,
              right: -6,
              child: _StatusDot(state: runState!, color: runColor),
            ),
        ],
      ),
    );
  }

  static Color? _runStateColor(ThemeData theme, NodeRunState? state) {
    return switch (state) {
      NodeRunState.running => CainTokens.phosphor,
      NodeRunState.completed => CainTokens.ok,
      NodeRunState.failed => CainTokens.danger,
      NodeRunState.skipped => CainTokens.idle,
      _ => null,
    };
  }
}

/// Small corner badge reflecting a node's execution state.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.state, this.color});

  final NodeRunState state;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (state == NodeRunState.running) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation(color ?? const Color(0xFF22D3EE)),
        ),
      );
    }
    final dotColor = color ?? Theme.of(context).colorScheme.outline;
    final icon = switch (state) {
      NodeRunState.completed => Icons.check,
      NodeRunState.failed => Icons.close,
      NodeRunState.skipped => Icons.remove,
      _ => null,
    };
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
      child: icon == null ? null : Icon(icon, size: 11, color: Colors.white),
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
          mainAxisAlignment: reverse
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [Text(fallbackLabel)],
        ),
      );
    }

    return SizedBox(
      width: 90,
      child: Column(
        crossAxisAlignment: reverse
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
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
    // Type-colored solder pad: a ring with a darker core, glowing when armed.
    final portColor = port.type == 'image'
        ? CainTokens.signalImage
        : CainTokens.signalText;
    final dot = Container(
      width: armed ? 14 : 11,
      height: armed ? 14 : 11,
      decoration: BoxDecoration(
        color: CainTokens.void0,
        shape: BoxShape.circle,
        border: Border.all(color: portColor, width: armed ? 2.5 : 2),
        boxShadow: armed
            ? [
                BoxShadow(
                  color: portColor.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
    );
    final text = Flexible(
      child: Text(
        port.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: reverse ? TextAlign.end : TextAlign.start,
        style: CainTokens.mono(9.5, color: CainTokens.inkDim, spacing: 0.3),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: kPortRowHeight,
        child: Row(
          mainAxisAlignment: reverse
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: reverse
              ? [text, const SizedBox(width: 6), dot]
              : [dot, const SizedBox(width: 6), text],
        ),
      ),
    );
  }
}
