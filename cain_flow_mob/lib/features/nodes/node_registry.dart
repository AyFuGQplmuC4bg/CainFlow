import 'node_definition.dart';

class NodeRegistry {
  const NodeRegistry(this._definitions);

  final List<NodeDefinition> _definitions;

  List<NodeDefinition> get all => List.unmodifiable(_definitions);

  NodeDefinition? get(String type) {
    for (final definition in _definitions) {
      if (definition.type == type) return definition;
    }
    return null;
  }
}

const nodeRegistry = NodeRegistry([
  NodeDefinition(
    type: 'Text',
    title: 'Text Prompt',
    description: 'Static prompt text for downstream nodes.',
    outputPorts: [
      NodePortDefinition(name: 'text', type: 'text', label: 'Text'),
    ],
    params: [
      NodeParamDefinition(
        name: 'text',
        label: 'Prompt text',
        control: NodeParamControl.multiline,
        defaultValue: '',
      ),
    ],
  ),
  NodeDefinition(
    type: 'TextChat',
    title: 'Text Chat',
    description: 'Chat completion request.',
    inputPorts: [
      NodePortDefinition(name: 'prompt', type: 'text', label: 'Prompt'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'text', type: 'text', label: 'Text'),
    ],
    params: [
      NodeParamDefinition(
        name: 'apiConfigId',
        label: 'Model',
        control: NodeParamControl.modelPicker,
        taskType: 'chat',
      ),
      NodeParamDefinition(
        name: 'systemPrompt',
        label: 'System prompt',
        control: NodeParamControl.multiline,
        defaultValue: '',
      ),
      NodeParamDefinition(
        name: 'customParams',
        label: 'Custom params',
        control: NodeParamControl.customParams,
      ),
    ],
  ),
  NodeDefinition(
    type: 'ImageImport',
    title: 'Image Import',
    description: 'Local image asset input.',
    outputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
  ),
  NodeDefinition(
    type: 'ImageGenerate',
    title: 'Image Generate',
    description: 'Generate images from text and optional references.',
    inputPorts: [
      NodePortDefinition(name: 'prompt', type: 'text', label: 'Prompt'),
      NodePortDefinition(name: 'image', type: 'image', label: 'Reference'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
    params: [
      NodeParamDefinition(
        name: 'apiConfigId',
        label: 'Model',
        control: NodeParamControl.modelPicker,
        taskType: 'image',
      ),
      NodeParamDefinition(
        name: 'size',
        label: 'Size',
        control: NodeParamControl.select,
        options: ['', '512x512', '1024x1024', '1024x1536', '1536x1024'],
        defaultValue: '',
      ),
      NodeParamDefinition(
        name: 'quality',
        label: 'Quality',
        control: NodeParamControl.select,
        options: ['', 'low', 'medium', 'high'],
        defaultValue: '',
      ),
      NodeParamDefinition(
        name: 'customParams',
        label: 'Custom params',
        control: NodeParamControl.customParams,
      ),
    ],
  ),
  NodeDefinition(
    type: 'ImagePreview',
    title: 'Image Preview',
    description: 'Preview image output on the canvas.',
    inputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
  ),
  NodeDefinition(
    type: 'ImageSave',
    title: 'Image Save',
    description: 'Persist generated images to local storage.',
    inputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
  ),
]);
