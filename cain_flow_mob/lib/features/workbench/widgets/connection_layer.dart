import 'package:flutter/material.dart';

import '../../nodes/node_registry.dart';
import '../workbench_signals.dart';
import 'node_card.dart';

class ConnectionLayer extends StatelessWidget {
  const ConnectionLayer({
    super.key,
    required this.nodes,
    required this.connections,
    this.imageOutputs = const {},
    this.zoom = 1,
  });

  final List<WorkbenchNode> nodes;
  final List<WorkbenchConnection> connections;

  /// Node ids that currently show a thumbnail (taller cards), so anchors match.
  final Set<String> imageOutputs;

  /// Canvas zoom; card dimensions are scaled by this when anchoring.
  final double zoom;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ConnectionPainter(
        nodes: nodes,
        connections: connections,
        imageOutputs: imageOutputs,
        zoom: zoom,
        textColor: Theme.of(context).colorScheme.secondary,
        imageColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  const _ConnectionPainter({
    required this.nodes,
    required this.connections,
    required this.imageOutputs,
    required this.zoom,
    required this.textColor,
    required this.imageColor,
  });

  final List<WorkbenchNode> nodes;
  final List<WorkbenchConnection> connections;
  final Set<String> imageOutputs;
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
        from.x + workbenchNodeSize.width * zoom,
        from.y +
            portAnchorY(
                  fromDef,
                  isOutput: true,
                  portIndex: fromIndex,
                  hasImage: imageOutputs.contains(from.id),
                ) *
                zoom,
      );
      final end = Offset(
        to.x,
        to.y +
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
      final paint = Paint()
        ..color = connection.type == 'image' ? imageColor : textColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, paint);
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
        oldDelegate.textColor != textColor ||
        oldDelegate.imageColor != imageColor;
  }
}
