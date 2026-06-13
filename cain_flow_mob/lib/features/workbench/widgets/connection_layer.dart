import 'package:flutter/material.dart';

import '../workbench_signals.dart';
import 'node_card.dart';

class ConnectionLayer extends StatelessWidget {
  const ConnectionLayer({
    super.key,
    required this.nodes,
    required this.connections,
  });

  final List<WorkbenchNode> nodes;
  final List<WorkbenchConnection> connections;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ConnectionPainter(
        nodes: nodes,
        connections: connections,
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
    required this.textColor,
    required this.imageColor,
  });

  final List<WorkbenchNode> nodes;
  final List<WorkbenchConnection> connections;
  final Color textColor;
  final Color imageColor;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeById = {for (final node in nodes) node.id: node};

    for (final connection in connections) {
      final from = nodeById[connection.fromNodeId];
      final to = nodeById[connection.toNodeId];
      if (from == null || to == null) continue;

      final start = Offset(
        from.x + workbenchNodeSize.width,
        from.y + workbenchNodeSize.height - 28,
      );
      final end = Offset(
        to.x,
        to.y + workbenchNodeSize.height - 28,
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

  @override
  bool shouldRepaint(covariant _ConnectionPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.connections != connections ||
        oldDelegate.textColor != textColor ||
        oldDelegate.imageColor != imageColor;
  }
}
