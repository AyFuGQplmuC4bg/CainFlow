import 'dart:convert';

import 'package:flutter/material.dart';

import '../../nodes/node_definition.dart';
import '../../settings/provider_settings.dart';
import '../workbench_signals.dart';

/// Bottom sheet that renders an editable form for a node's parameters,
/// driven by its [NodeDefinition.params]. Edits are written back through
/// [WorkbenchSignals.updateNodeData]. Also hosts the delete-node action.
class NodeParamSheet extends StatefulWidget {
  const NodeParamSheet({
    super.key,
    required this.node,
    required this.definition,
    required this.models,
    required this.onChanged,
    required this.onDelete,
  });

  final WorkbenchNode node;
  final NodeDefinition? definition;
  final List<ModelConfig> models;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  @override
  State<NodeParamSheet> createState() => _NodeParamSheetState();
}

class _NodeParamSheetState extends State<NodeParamSheet> {
  late Map<String, dynamic> _data;

  @override
  void initState() {
    super.initState();
    _data = Map<String, dynamic>.from(widget.node.data);
  }

  void _set(String key, Object? value) {
    setState(() {
      if (value == null || (value is String && value.isEmpty)) {
        _data.remove(key);
      } else {
        _data[key] = value;
      }
    });
    widget.onChanged(Map<String, dynamic>.from(_data));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final params = widget.definition?.params ?? const [];
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.node.title,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Delete node',
                onPressed: widget.onDelete,
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              ),
            ],
          ),
          Text(
            widget.node.type,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (params.isEmpty)
            Text(
              'This node has no editable parameters.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final param in params) ...[
                      _buildControl(param),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControl(NodeParamDefinition param) {
    return switch (param.control) {
      NodeParamControl.modelPicker => _modelPicker(param),
      NodeParamControl.select => _select(param),
      NodeParamControl.customParams => _customParams(param),
      NodeParamControl.number => _textField(param, number: true),
      NodeParamControl.multiline => _textField(param, multiline: true),
      NodeParamControl.text => _textField(param),
    };
  }

  Widget _textField(
    NodeParamDefinition param, {
    bool multiline = false,
    bool number = false,
  }) {
    return TextFormField(
      key: ValueKey('param_${param.name}'),
      initialValue: _data[param.name]?.toString() ?? '',
      maxLines: multiline ? 4 : 1,
      keyboardType: number ? TextInputType.number : null,
      decoration: InputDecoration(
        labelText: param.label,
        hintText: param.hint.isEmpty ? null : param.hint,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => _set(param.name, value),
    );
  }

  Widget _select(NodeParamDefinition param) {
    final current = _data[param.name]?.toString() ?? '';
    final value = param.options.contains(current) ? current : '';
    return DropdownButtonFormField<String>(
      key: ValueKey('param_${param.name}'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: param.label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final option in param.options)
          DropdownMenuItem(
            value: option,
            child: Text(option.isEmpty ? '(default)' : option),
          ),
      ],
      onChanged: (v) => _set(param.name, v ?? ''),
    );
  }

  Widget _modelPicker(NodeParamDefinition param) {
    final candidates = [
      for (final model in widget.models)
        if (param.taskType == null || model.taskType.name == param.taskType)
          model,
    ];
    final currentId = _data[param.name]?.toString() ?? '';
    final value = candidates.any((m) => m.id == currentId) ? currentId : null;

    if (candidates.isEmpty) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: param.label,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          'No matching models configured',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return DropdownButtonFormField<String>(
      key: ValueKey('param_${param.name}'),
      initialValue: value,
      decoration: InputDecoration(
        labelText: param.label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final model in candidates)
          DropdownMenuItem(
            value: model.id,
            child: Text(model.name.isEmpty ? model.modelId : model.name),
          ),
      ],
      onChanged: (v) => _set(param.name, v),
    );
  }

  Widget _customParams(NodeParamDefinition param) {
    final raw = _data[param.name];
    final text = raw is Map ? const JsonEncoder.withIndent('  ').convert(raw) : '';
    return TextFormField(
      key: ValueKey('param_${param.name}'),
      initialValue: text,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: '${param.label} (JSON)',
        hintText: '{"temperature": 0.7}',
        border: const OutlineInputBorder(),
        errorText: _customParamsError,
      ),
      onChanged: _onCustomParamsChanged,
    );
  }

  String? _customParamsError;

  void _onCustomParamsChanged(String value) {
    if (value.trim().isEmpty) {
      setState(() => _customParamsError = null);
      _set('customParams', null);
      return;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        setState(() => _customParamsError = null);
        _set('customParams', Map<String, dynamic>.from(decoded));
      } else {
        setState(() => _customParamsError = 'Must be a JSON object');
      }
    } catch (_) {
      setState(() => _customParamsError = 'Invalid JSON');
    }
  }
}
