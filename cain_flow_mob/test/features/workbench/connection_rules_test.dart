import 'package:cain_flow_mob/features/workbench/connection_rules.dart';
import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nodes = const [
    WorkbenchNode(id: 'a', type: 'Text', title: 'A', x: 0, y: 0),
    WorkbenchNode(id: 'b', type: 'TextChat', title: 'B', x: 0, y: 0),
    WorkbenchNode(id: 'c', type: 'ImageGenerate', title: 'C', x: 0, y: 0),
  ];

  ConnectionAttempt attempt(String from, String to, {String type = 'text'}) {
    return ConnectionAttempt(
      fromNodeId: from,
      fromPort: 'out',
      fromType: type,
      toNodeId: to,
      toPort: 'in',
      toType: type,
    );
  }

  test('accepts a valid forward edge', () {
    expect(
      validateConnection(attempt('a', 'b'), nodes, const []),
      ConnectionRejection.none,
    );
  });

  test('rejects self connection', () {
    expect(
      validateConnection(attempt('a', 'a'), nodes, const []),
      ConnectionRejection.selfConnection,
    );
  });

  test('rejects type mismatch', () {
    final a = ConnectionAttempt(
      fromNodeId: 'a',
      fromPort: 'out',
      fromType: 'text',
      toNodeId: 'c',
      toPort: 'image',
      toType: 'image',
    );
    expect(
      validateConnection(a, nodes, const []),
      ConnectionRejection.typeMismatch,
    );
  });

  test('rejects an edge that would create a cycle', () {
    // Existing a->b, b->c. Adding c->a closes the loop.
    final existing = [
      const WorkbenchConnection(
        id: 'e1',
        fromNodeId: 'a',
        fromPort: 'out',
        toNodeId: 'b',
        toPort: 'in',
        type: 'text',
      ),
      const WorkbenchConnection(
        id: 'e2',
        fromNodeId: 'b',
        fromPort: 'out',
        toNodeId: 'c',
        toPort: 'in',
        type: 'text',
      ),
    ];
    expect(
      validateConnection(attempt('c', 'a'), nodes, existing),
      ConnectionRejection.cycle,
    );
  });
}
