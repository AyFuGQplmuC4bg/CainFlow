import 'flow_connection.dart';
import 'flow_node.dart';

class WorkflowCanvas {
  const WorkflowCanvas({
    required this.x,
    required this.y,
    required this.zoom,
    this.extra = const {},
  });

  factory WorkflowCanvas.fromJson(Map<String, dynamic> json) {
    final extra = Map<String, dynamic>.from(json)
      ..remove('x')
      ..remove('y')
      ..remove('zoom');
    return WorkflowCanvas(
      x: _numberFrom(json['x']),
      y: _numberFrom(json['y']),
      zoom: _numberFrom(json['zoom'], fallback: 1),
      extra: extra,
    );
  }

  factory WorkflowCanvas.empty() {
    return const WorkflowCanvas(x: 0, y: 0, zoom: 1);
  }

  final double x;
  final double y;
  final double zoom;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() {
    return {
      ...extra,
      'x': x,
      'y': y,
      'zoom': zoom,
    };
  }

  static double _numberFrom(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class WorkflowDocument {
  const WorkflowDocument({
    required this.canvas,
    required this.nodes,
    required this.connections,
    required this.version,
    this.name = '',
    this.extra = const {},
  });

  factory WorkflowDocument.empty() {
    return WorkflowDocument(
      canvas: WorkflowCanvas.empty(),
      nodes: const [],
      connections: const [],
      version: defaultVersion,
    );
  }

  factory WorkflowDocument.fromJson(Map<String, dynamic> json) {
    final extra = Map<String, dynamic>.from(json)
      ..remove('canvas')
      ..remove('nodes')
      ..remove('connections')
      ..remove('version')
      ..remove('name');
    return WorkflowDocument(
      canvas: _canvasFrom(json['canvas']),
      nodes: _nodesFrom(json['nodes']),
      connections: _connectionsFrom(json['connections']),
      version: json['version']?.toString() ?? defaultVersion,
      name: json['name']?.toString() ?? '',
      extra: extra,
    );
  }

  /// Current schema version. Older documents (1.3 and earlier) load without
  /// node `data` maps; [FlowNode.fromJson] already defaults those to empty.
  static const defaultVersion = '1.4';

  final WorkflowCanvas canvas;
  final List<FlowNode> nodes;
  final List<FlowConnection> connections;
  final String version;
  final String name;
  final Map<String, dynamic> extra;

  WorkflowDocument copyWith({
    WorkflowCanvas? canvas,
    List<FlowNode>? nodes,
    List<FlowConnection>? connections,
    String? version,
    String? name,
  }) {
    return WorkflowDocument(
      canvas: canvas ?? this.canvas,
      nodes: nodes ?? this.nodes,
      connections: connections ?? this.connections,
      version: version ?? this.version,
      name: name ?? this.name,
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...extra,
      if (name.isNotEmpty) 'name': name,
      'canvas': canvas.toJson(),
      'nodes': nodes.map((node) => node.toJson()).toList(),
      'connections': connections.map((connection) => connection.toJson()).toList(),
      'version': version,
    };
  }

  static WorkflowCanvas _canvasFrom(Object? value) {
    if (value is Map) {
      return WorkflowCanvas.fromJson(Map<String, dynamic>.from(value));
    }
    return WorkflowCanvas.empty();
  }

  static List<FlowNode> _nodesFrom(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((node) => FlowNode.fromJson(Map<String, dynamic>.from(node)))
        .toList();
  }

  static List<FlowConnection> _connectionsFrom(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (connection) => FlowConnection.fromJson(
            Map<String, dynamic>.from(connection),
          ),
        )
        .toList();
  }
}
