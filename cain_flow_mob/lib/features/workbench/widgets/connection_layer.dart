import 'package:flutter/material.dart';

import '../../../app/theme/cain_tokens.dart';
import '../../nodes/node_registry.dart';
import '../workbench_signals.dart';
import 'node_card.dart';

class ConnectionLayer extends StatelessWidget {
  const ConnectionLayer({
    super.key,
    required this.nodes,
    required this.connections,
    this.imageOutputs = const {},
    this.panOffset = const NodeOffset(0, 0),
    this.zoom = 1,
  });

  final List<WorkbenchNode> nodes;
  final List<WorkbenchConnection> connections;

  /// Node ids that currently show a thumbnail (taller cards), so anchors match.
  final Set<String> imageOutputs;

  /// Canvas pan in viewport pixels.
  final NodeOffset panOffset;

  /// Canvas zoom; card dimensions are scaled by this when anchoring.
  final double zoom;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ConnectionPainter(
        nodes: nodes,
        connections: connections,
        imageOutputs: imageOutputs,
        panOffset: panOffset,
        zoom: zoom,
        textColor: CainTokens.signalText,
        imageColor: CainTokens.signalImage,
      ),
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  const _ConnectionPainter({
    required this.nodes,
    required this.connections,
    required this.imageOutputs,
    required this.panOffset,
    required this.zoom,
    required this.textColor,
    required this.imageColor,
  });

  final List<WorkbenchNode> nodes;
  final List<WorkbenchConnection> connections;
  final Set<String> imageOutputs;
  final NodeOffset panOffset;
  final double zoom;
  final Color textColor;
  final Color imageColor;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeById = {for (final node in nodes) node.id: node};

    for (final connection in connections) {
      final from = nodeById[connection.fromNodeId];
      final to = nodeById[connection.toNodeId];
      if (from == null || to == null) continue;

      final fromDef = nodeRegistry.get(from.type);
      final toDef = nodeRegistry.get(to.type);

      final fromIndex = _portIndex(fromDef?.outputPorts, connection.fromPort);
      final toIndex = _portIndex(toDef?.inputPorts, connection.toPort);

      final start = Offset(
        panOffset.dx + from.x * zoom + workbenchNodeSize.width * zoom,
        panOffset.dy + from.y * zoom +
            portAnchorY(
                  fromDef,
                  isOutput: true,
                  portIndex: fromIndex,
                  hasImage: imageOutputs.contains(from.id),
                ) *
                zoom,
      );
      final end = Offset(
        panOffset.dx + to.x * zoom,
        panOffset.dy + to.y * zoom +
            portAnchorY(
                  toDef,
                  isOutput: false,
                  portIndex: toIndex,
                  hasImage: imageOutputs.contains(to.id),
                ) *
                zoom,
      );
      final controlDistance = ((end.dx - start.dx).abs() * 0.45).clamp(64, 180);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + controlDistance,
          start.dy,
          end.dx - controlDistance,
          end.dy,
          end.dx,
          end.dy,
        );
      final signalColor = connection.type == 'image' ? imageColor : textColor;

      // Glow underlay, then crisp trace, then bright solder pads at each end —
      // a signal wire on a schematic.
      canvas.drawPath(
        path,
        Paint()
          ..color = signalColor.withValues(alpha: 0.22)
          ..strokeWidth = 6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = signalColor
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      for (final p in [start, end]) {
        canvas.drawCircle(p, 3, Paint()..color = signalColor);
      }
    }
  }

  int _portIndex(List<dynamic>? ports, String name) {
    if (ports == null) return 0;
    for (var i = 0; i < ports.length; i++) {
      if (ports[i].name == name) return i;
    }
    return 0;
  }

  @override
  bool shouldRepaint(covariant _ConnectionPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.connections != connections ||
        oldDelegate.imageOutputs != imageOutputs ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.zoom != zoom ||
        oldDelegate.textColor != textColor ||
        oldDelegate.imageColor != imageColor;
  }
}
