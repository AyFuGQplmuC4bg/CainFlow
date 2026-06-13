class FlowNode {
  const FlowNode({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    this.customTitle,
    this.enabled = true,
    this.data = const {},
    this.extra = const {},
  });

  factory FlowNode.fromJson(Map<String, dynamic> json) {
    final extra = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('type')
      ..remove('x')
      ..remove('y')
      ..remove('customTitle')
      ..remove('enabled')
      ..remove('data');
    return FlowNode(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      x: _numberFrom(json['x']),
      y: _numberFrom(json['y']),
      customTitle: json['customTitle']?.toString(),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      data: _mapFrom(json['data']),
      extra: extra,
    );
  }

  final String id;
  final String type;
  final double x;
  final double y;
  final String? customTitle;
  final bool enabled;
  final Map<String, dynamic> data;
  final Map<String, dynamic> extra;

  String get title => customTitle?.isNotEmpty == true ? customTitle! : type;

  Map<String, dynamic> toJson() {
    return {
      ...extra,
      'id': id,
      'type': type,
      'x': x,
      'y': y,
      if (customTitle != null) 'customTitle': customTitle,
      if (!enabled) 'enabled': enabled,
      'data': data,
    };
  }

  static double _numberFrom(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static Map<String, dynamic> _mapFrom(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }
}
