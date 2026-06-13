import 'package:signals/signals.dart';

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
  });

  factory WorkbenchNode.fromJson(Map<String, dynamic> json) {
    return WorkbenchNode(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? json['type']?.toString() ?? '',
      x: _numberFrom(json['x']),
      y: _numberFrom(json['y']),
    );
  }

  final String id;
  final String type;
  final String title;
  final double x;
  final double y;

  WorkbenchNode moveBy(NodeOffset offset) {
    return WorkbenchNode(
      id: id,
      type: type,
      title: title,
      x: x + offset.dx,
      y: y + offset.dy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'x': x,
      'y': y,
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

class WorkbenchSignals {
  WorkbenchSignals();

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
