import 'package:signals/signals.dart';

import '../nodes/node_registry.dart';
import 'connection_rules.dart';

enum WorkbenchRunState {
  idle,
  running,
  stopped,
}

class NodeOffset {
  const NodeOffset(this.dx, this.dy);

  factory NodeOffset.fromJson(Map<String, dynamic> json) {
    return NodeOffset(
      _numberFrom(json['dx']),
      _numberFrom(json['dy']),
    );
  }

  final double dx;
  final double dy;

  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy};
}

class WorkbenchNode {
  const WorkbenchNode({
    required this.id,
    required this.type,
    required this.title,
    required this.x,
    required this.y,
    this.data = const {},
  });

  factory WorkbenchNode.fromJson(Map<String, dynamic> json) {
    return WorkbenchNode(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? json['type']?.toString() ?? '',
      x: _numberFrom(json['x']),
      y: _numberFrom(json['y']),
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : const {},
    );
  }

  final String id;
  final String type;
  final String title;
  final double x;
  final double y;
  final Map<String, dynamic> data;

  WorkbenchNode moveBy(NodeOffset offset) {
    return WorkbenchNode(
      id: id,
      type: type,
      title: title,
      x: x + offset.dx,
      y: y + offset.dy,
      data: data,
    );
  }

  WorkbenchNode withData(Map<String, dynamic> newData) {
    return WorkbenchNode(
      id: id,
      type: type,
      title: title,
      x: x,
      y: y,
      data: newData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'x': x,
      'y': y,
      if (data.isNotEmpty) 'data': data,
    };
  }
}

class WorkbenchConnection {
  const WorkbenchConnection({
    required this.id,
    required this.fromNodeId,
    required this.fromPort,
    required this.toNodeId,
    required this.toPort,
    required this.type,
  });

  factory WorkbenchConnection.fromJson(Map<String, dynamic> json) {
    return WorkbenchConnection(
      id: json['id']?.toString() ?? '',
      fromNodeId: json['fromNodeId']?.toString() ?? '',
      fromPort: json['fromPort']?.toString() ?? '',
      toNodeId: json['toNodeId']?.toString() ?? '',
      toPort: json['toPort']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
    );
  }

  final String id;
  final String fromNodeId;
  final String fromPort;
  final String toNodeId;
  final String toPort;
  final String type;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fromNodeId': fromNodeId,
      'fromPort': fromPort,
      'toNodeId': toNodeId,
      'toPort': toPort,
      'type': type,
    };
  }
}

/// A connection origin held while the user is picking the destination port.
class PendingConnection {
  const PendingConnection({
    required this.fromNodeId,
    required this.fromPort,
    required this.type,
  });

  final String fromNodeId;
  final String fromPort;
  final String type;
}

class WorkbenchSignals {
  WorkbenchSignals();

  /// Invoked just before a structural graph mutation (add/remove node or
  /// connection, data edit) so an undo history can capture the prior state.
  /// Node drags and pan/zoom are intentionally excluded.
  void Function()? onBeforeMutation;

  void _recordMutation() => onBeforeMutation?.call();
  final activeWorkflowName = signal('Untitled Workflow');
  final nodes = signal<List<WorkbenchNode>>(const [
    WorkbenchNode(
      id: 'node_text_prompt',
      type: 'Text',
      title: 'Text Prompt',
      x: 80,
      y: 120,
    ),
    WorkbenchNode(
      id: 'node_image_generate',
      type: 'ImageGenerate',
      title: 'Image Generate',
      x: 360,
      y: 96,
    ),
    WorkbenchNode(
      id: 'node_image_save',
      type: 'ImageSave',
      title: 'Image Save',
      x: 640,
      y: 140,
    ),
  ]);
  final connections = signal<List<WorkbenchConnection>>(const [
    WorkbenchConnection(
      id: 'conn_text_to_image',
      fromNodeId: 'node_text_prompt',
      fromPort: 'text',
      toNodeId: 'node_image_generate',
      toPort: 'prompt',
      type: 'text',
    ),
    WorkbenchConnection(
      id: 'conn_image_to_save',
      fromNodeId: 'node_image_generate',
      fromPort: 'image',
      toNodeId: 'node_image_save',
      toPort: 'image',
      type: 'image',
    ),
  ]);
  final selectedNodeId = signal<String?>(null);
  final pendingConnection = signal<PendingConnection?>(null);
  final lastConnectionRejection = signal<ConnectionRejection>(
    ConnectionRejection.none,
  );
  final runState = signal(WorkbenchRunState.idle);
  final panOffset = signal(const NodeOffset(0, 0));
  final zoom = signal(1.0);

  late final nodeCount = computed(() => nodes.value.length);
  late final connectionCount = computed(() => connections.value.length);
  late final hasSelection = computed(() => selectedNodeId.value != null);
  late final selectedNode = computed(() {
    final id = selectedNodeId.value;
    if (id == null) return null;
    for (final node in nodes.value) {
      if (node.id == id) return node;
    }
    return null;
  });
  late final graphSummary = computed(
    () => '${nodeCount.value} nodes / ${connectionCount.value} links',
  );

  void selectNode(String nodeId) {
    selectedNodeId.value = nodeId;
  }

  void clearSelection() {
    selectedNodeId.value = null;
  }

  void moveNode(String nodeId, NodeOffset offset) {
    nodes.value = [
      for (final node in nodes.value)
        if (node.id == nodeId) node.moveBy(offset) else node,
    ];
  }

  /// Replaces the parameter map of [nodeId] with [data].
  void updateNodeData(String nodeId, Map<String, dynamic> data) {
    _recordMutation();
    nodes.value = [
      for (final node in nodes.value)
        if (node.id == nodeId) node.withData(Map<String, dynamic>.from(data)) else node,
    ];
  }

  /// Adds a node of [type] at [position] (defaults to a spread-out spot),
  /// seeded with the definition's default data. Returns the new node id.
  String addNode(String type, {NodeOffset? position}) {
    _recordMutation();
    final definition = nodeRegistry.get(type);
    final id = 'node_${type}_${DateTime.now().microsecondsSinceEpoch}';
    final spot = position ?? _nextNodeSpot();
    final node = WorkbenchNode(
      id: id,
      type: type,
      title: definition?.title ?? type,
      x: spot.dx,
      y: spot.dy,
      data: definition?.defaultData() ?? const {},
    );
    nodes.value = [...nodes.value, node];
    return id;
  }

  /// Removes [nodeId] and every connection touching it.
  void removeNode(String nodeId) {
    _recordMutation();
    nodes.value = [
      for (final node in nodes.value)
        if (node.id != nodeId) node,
    ];
    connections.value = [
      for (final connection in connections.value)
        if (connection.fromNodeId != nodeId && connection.toNodeId != nodeId)
          connection,
    ];
    if (selectedNodeId.value == nodeId) selectedNodeId.value = null;
  }

  NodeOffset _nextNodeSpot() {
    // Cascade new nodes so they don't stack exactly on top of each other.
    final count = nodes.value.length;
    return NodeOffset(120 + (count % 5) * 40, 120 + (count % 5) * 40);
  }

  // --- Point-select connections --------------------------------------------

  /// Begins a connection from an output port. A second tap on a compatible
  /// input port completes it via [completeConnection].
  void beginConnection(String nodeId, String port, String type) {
    pendingConnection.value =
        PendingConnection(fromNodeId: nodeId, fromPort: port, type: type);
    lastConnectionRejection.value = ConnectionRejection.none;
  }

  void cancelPendingConnection() {
    pendingConnection.value = null;
  }

  /// Attempts to complete the pending connection at an input port. Returns the
  /// rejection reason (or [ConnectionRejection.none] on success) and clears the
  /// pending state. A successful edge replaces any existing edge on the same
  /// input port (single-input rule).
  ConnectionRejection completeConnection(
    String toNodeId,
    String toPort,
    String toType,
  ) {
    final pending = pendingConnection.value;
    if (pending == null) return ConnectionRejection.none;

    final attempt = ConnectionAttempt(
      fromNodeId: pending.fromNodeId,
      fromPort: pending.fromPort,
      fromType: pending.type,
      toNodeId: toNodeId,
      toPort: toPort,
      toType: toType,
    );
    final rejection =
        validateConnection(attempt, nodes.value, connections.value);
    lastConnectionRejection.value = rejection;
    if (rejection != ConnectionRejection.none) {
      pendingConnection.value = null;
      return rejection;
    }

    final type = pending.type.isNotEmpty ? pending.type : toType;
    final id =
        'conn_${pending.fromNodeId}_${pending.fromPort}_to_${toNodeId}_$toPort';
    _recordMutation();
    connections.value = [
      // Drop any existing edge feeding the same input port.
      for (final c in connections.value)
        if (!(c.toNodeId == toNodeId && c.toPort == toPort)) c,
      WorkbenchConnection(
        id: id,
        fromNodeId: pending.fromNodeId,
        fromPort: pending.fromPort,
        toNodeId: toNodeId,
        toPort: toPort,
        type: type,
      ),
    ];
    pendingConnection.value = null;
    return ConnectionRejection.none;
  }

  void removeConnection(String connectionId) {
    _recordMutation();
    connections.value = [
      for (final c in connections.value)
        if (c.id != connectionId) c,
    ];
  }

  void moveCanvas(NodeOffset offset) {
    final current = panOffset.value;
    panOffset.value = NodeOffset(current.dx + offset.dx, current.dy + offset.dy);
  }

  void setZoom(double value) {
    zoom.value = value.clamp(0.5, 1.8);
  }

  Map<String, dynamic> toSessionJson() {
    return {
      'activeWorkflowName': activeWorkflowName.value,
      'nodes': nodes.value.map((node) => node.toJson()).toList(),
      'connections': connections.value
          .map((connection) => connection.toJson())
          .toList(),
      'selectedNodeId': selectedNodeId.value,
      'panOffset': panOffset.value.toJson(),
      'zoom': zoom.value,
    };
  }

  void restoreSession(Map<String, dynamic> json) {
    final decodedNodes = _listOfMaps(json['nodes'])
        .map(WorkbenchNode.fromJson)
        .where((node) => node.id.isNotEmpty)
        .toList();
    final decodedConnections = _listOfMaps(json['connections'])
        .map(WorkbenchConnection.fromJson)
        .where((connection) => connection.id.isNotEmpty)
        .toList();

    activeWorkflowName.value =
        json['activeWorkflowName']?.toString() ?? activeWorkflowName.value;
    if (decodedNodes.isNotEmpty) nodes.value = decodedNodes;
    connections.value = decodedConnections;
    selectedNodeId.value = json['selectedNodeId']?.toString();
    final pan = json['panOffset'];
    if (pan is Map) {
      panOffset.value = NodeOffset.fromJson(Map<String, dynamic>.from(pan));
    }
    zoom.value = _numberFrom(json['zoom'], fallback: zoom.value).clamp(0.5, 1.8);
  }

  void toggleRunState() {
    runState.value = switch (runState.value) {
      WorkbenchRunState.running => WorkbenchRunState.stopped,
      _ => WorkbenchRunState.running,
    };
  }
}

final workbenchSignals = WorkbenchSignals();

double _numberFrom(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
