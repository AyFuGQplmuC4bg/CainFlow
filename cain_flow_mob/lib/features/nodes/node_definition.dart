class NodePortDefinition {
  const NodePortDefinition({
    required this.name,
    required this.type,
    required this.label,
  });

  final String name;
  final String type;
  final String label;
}

class NodeDefinition {
  const NodeDefinition({
    required this.type,
    required this.title,
    required this.description,
    this.inputPorts = const [],
    this.outputPorts = const [],
  });

  final String type;
  final String title;
  final String description;
  final List<NodePortDefinition> inputPorts;
  final List<NodePortDefinition> outputPorts;
}
