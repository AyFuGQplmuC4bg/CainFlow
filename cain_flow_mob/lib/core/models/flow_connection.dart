class FlowEndpoint {
  const FlowEndpoint({
    required this.nodeId,
    required this.port,
    this.type = '',
    this.extra = const {},
  });

  factory FlowEndpoint.fromJson(Map<String, dynamic> json) {
    final extra = Map<String, dynamic>.from(json)
      ..remove('nodeId')
      ..remove('port')
      ..remove('type');
    return FlowEndpoint(
      nodeId: json['nodeId']?.toString() ?? '',
      port: json['port']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      extra: extra,
    );
  }

  final String nodeId;
  final String port;
  final String type;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() {
    return {
      ...extra,
      'nodeId': nodeId,
      'port': port,
      if (type.isNotEmpty) 'type': type,
    };
  }
}

class FlowConnection {
  const FlowConnection({
    required this.id,
    required this.from,
    required this.to,
    this.type = '',
    this.extra = const {},
  });

  factory FlowConnection.fromJson(Map<String, dynamic> json) {
    final extra = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('from')
      ..remove('to')
      ..remove('type');
    return FlowConnection(
      id: json['id']?.toString() ?? '',
      from: _endpointFrom(json['from']),
      to: _endpointFrom(json['to']),
      type: json['type']?.toString() ?? '',
      extra: extra,
    );
  }

  final String id;
  final FlowEndpoint from;
  final FlowEndpoint to;
  final String type;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() {
    return {
      ...extra,
      'id': id,
      'from': from.toJson(),
      'to': to.toJson(),
      if (type.isNotEmpty) 'type': type,
    };
  }

  static FlowEndpoint _endpointFrom(Object? value) {
    if (value is Map) {
      return FlowEndpoint.fromJson(Map<String, dynamic>.from(value));
    }
    return const FlowEndpoint(nodeId: '', port: '');
  }
}
