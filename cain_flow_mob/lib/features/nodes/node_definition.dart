/// Control widget hint for rendering a node parameter in the editor form.
enum NodeParamControl {
  text,
  multiline,
  number,
  select,
  modelPicker,
  customParams,
  imagePicker,
}

class NodeParamDefinition {
  const NodeParamDefinition({
    required this.name,
    required this.label,
    this.control = NodeParamControl.text,
    this.options = const [],
    this.defaultValue,
    this.taskType,
    this.hint = '',
  });

  final String name;
  final String label;
  final NodeParamControl control;

  /// Selectable values for [NodeParamControl.select].
  final List<String> options;

  /// Initial value applied when a node of this type is created.
  final Object? defaultValue;

  /// For [NodeParamControl.modelPicker]: which model task type to filter by
  /// (e.g. `chat`, `image`). Null means no filtering.
  final String? taskType;

  final String hint;
}

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
    this.params = const [],
  });

  final String type;
  final String title;
  final String description;
  final List<NodePortDefinition> inputPorts;
  final List<NodePortDefinition> outputPorts;
  final List<NodeParamDefinition> params;

  /// Default `data` map for a freshly created node, derived from [params]
  /// that declare a [NodeParamDefinition.defaultValue].
  Map<String, dynamic> defaultData() {
    final data = <String, dynamic>{};
    for (final param in params) {
      if (param.defaultValue != null) data[param.name] = param.defaultValue;
    }
    return data;
  }
}
