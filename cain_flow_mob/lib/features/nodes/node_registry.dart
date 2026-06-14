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
      NodePortDefinition(name: 'image_1', type: 'image', label: 'Vision 1'),
      NodePortDefinition(name: 'image_2', type: 'image', label: 'Vision 2'),
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
        name: 'stream',
        label: 'Stream response',
        control: NodeParamControl.select,
        options: ['false', 'true'],
        defaultValue: 'false',
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
    params: [
      NodeParamDefinition(
        name: 'assetId',
        label: 'Image',
        control: NodeParamControl.imagePicker,
      ),
    ],
  ),
  NodeDefinition(
    type: 'ImageGenerate',
    title: 'Image Generate',
    description: 'Generate images from text and optional references.',
    inputPorts: [
      NodePortDefinition(name: 'prompt', type: 'text', label: 'Prompt'),
      NodePortDefinition(name: 'image_1', type: 'image', label: 'Ref 1'),
      NodePortDefinition(name: 'image_2', type: 'image', label: 'Ref 2'),
      NodePortDefinition(name: 'mask', type: 'image', label: 'Mask'),
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
    params: [
      NodeParamDefinition(
        name: 'downloadRemote',
        label: 'Download remote URLs',
        control: NodeParamControl.select,
        options: ['false', 'true'],
        defaultValue: 'false',
      ),
    ],
  ),
  NodeDefinition(
    type: 'TextMerge',
    title: 'Text Merge',
    description: 'Concatenate up to three text inputs.',
    inputPorts: [
      NodePortDefinition(name: 'text_1', type: 'text', label: 'Text 1'),
      NodePortDefinition(name: 'text_2', type: 'text', label: 'Text 2'),
      NodePortDefinition(name: 'text_3', type: 'text', label: 'Text 3'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'text', type: 'text', label: 'Merged'),
    ],
    params: [
      NodeParamDefinition(
        name: 'separator',
        label: 'Separator',
        control: NodeParamControl.text,
        defaultValue: '\n',
      ),
    ],
  ),
  NodeDefinition(
    type: 'TextSplit',
    title: 'Text Split',
    description: 'Split text into up to three parts by a separator.',
    inputPorts: [
      NodePortDefinition(name: 'text', type: 'text', label: 'Text'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'part_1', type: 'text', label: 'Part 1'),
      NodePortDefinition(name: 'part_2', type: 'text', label: 'Part 2'),
      NodePortDefinition(name: 'part_3', type: 'text', label: 'Part 3'),
    ],
    params: [
      NodeParamDefinition(
        name: 'separator',
        label: 'Separator',
        control: NodeParamControl.text,
        defaultValue: '\n',
      ),
    ],
  ),
  NodeDefinition(
    type: 'ImageResize',
    title: 'Image Resize',
    description: 'Scale an image to a target size.',
    inputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
    params: [
      NodeParamDefinition(
        name: 'width',
        label: 'Width',
        control: NodeParamControl.number,
        defaultValue: 512,
      ),
      NodeParamDefinition(
        name: 'height',
        label: 'Height',
        control: NodeParamControl.number,
        defaultValue: 512,
      ),
      NodeParamDefinition(
        name: 'fit',
        label: 'Fit',
        control: NodeParamControl.select,
        options: ['contain', 'cover', 'stretch'],
        defaultValue: 'contain',
      ),
    ],
  ),
  NodeDefinition(
    type: 'ImageMerge',
    title: 'Image Merge',
    description: 'Combine up to three images into one.',
    inputPorts: [
      NodePortDefinition(name: 'image_1', type: 'image', label: 'Image 1'),
      NodePortDefinition(name: 'image_2', type: 'image', label: 'Image 2'),
      NodePortDefinition(name: 'image_3', type: 'image', label: 'Image 3'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Merged'),
    ],
    params: [
      NodeParamDefinition(
        name: 'layout',
        label: 'Layout',
        control: NodeParamControl.select,
        options: ['horizontal', 'vertical', 'grid'],
        defaultValue: 'horizontal',
      ),
    ],
  ),
  NodeDefinition(
    type: 'ImageCompare',
    title: 'Image Compare',
    description: 'Place two images side by side.',
    inputPorts: [
      NodePortDefinition(name: 'imageA', type: 'image', label: 'Image A'),
      NodePortDefinition(name: 'imageB', type: 'image', label: 'Image B'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Comparison'),
    ],
  ),
  NodeDefinition(
    type: 'ImageCrop',
    title: 'Image Crop',
    description: 'Crop a rectangular region of an image.',
    inputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
    params: [
      NodeParamDefinition(name: 'x', label: 'X', control: NodeParamControl.number, defaultValue: 0),
      NodeParamDefinition(name: 'y', label: 'Y', control: NodeParamControl.number, defaultValue: 0),
      NodeParamDefinition(name: 'width', label: 'Width', control: NodeParamControl.number, defaultValue: 256),
      NodeParamDefinition(name: 'height', label: 'Height', control: NodeParamControl.number, defaultValue: 256),
    ],
  ),
  NodeDefinition(
    type: 'ImageAnnotate',
    title: 'Image Annotate',
    description: 'Draw shapes (JSON) onto an image.',
    inputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Image'),
    ],
    params: [
      NodeParamDefinition(
        name: 'shapes',
        label: 'Shapes',
        control: NodeParamControl.customParams,
        hint: '[{"type":"rect","x1":10,"y1":10,"x2":80,"y2":80}]',
      ),
    ],
  ),
  NodeDefinition(
    type: 'CameraControl',
    title: 'Camera Control',
    description: 'Builds a camera/shot prompt from settings and a reference.',
    inputPorts: [
      NodePortDefinition(name: 'image', type: 'image', label: 'Reference'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'text', type: 'text', label: 'Prompt'),
    ],
    params: [
      NodeParamDefinition(
        name: 'shot',
        label: 'Shot',
        control: NodeParamControl.select,
        options: ['wide', 'medium', 'close-up', 'aerial', 'low angle'],
        defaultValue: 'medium',
      ),
      NodeParamDefinition(
        name: 'movement',
        label: 'Movement',
        control: NodeParamControl.select,
        options: ['static', 'pan', 'zoom in', 'zoom out', 'dolly', 'orbit'],
        defaultValue: 'static',
      ),
    ],
  ),
  NodeDefinition(
    type: 'ControlCondition',
    title: 'Condition',
    description: 'Routes input to the true or false branch by a comparison.',
    inputPorts: [
      NodePortDefinition(name: 'value', type: 'text', label: 'Value'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'true', type: 'text', label: 'True'),
      NodePortDefinition(name: 'false', type: 'text', label: 'False'),
    ],
    params: [
      NodeParamDefinition(
        name: 'operator',
        label: 'Operator',
        control: NodeParamControl.select,
        options: ['==', '!=', 'contains', 'notEmpty'],
        defaultValue: '==',
      ),
      NodeParamDefinition(
        name: 'compareTo',
        label: 'Compare to',
        control: NodeParamControl.text,
        defaultValue: '',
      ),
    ],
  ),
  NodeDefinition(
    type: 'ControlLoop',
    title: 'Loop',
    description: 'Emits the loop branch a fixed number of times, then done.',
    inputPorts: [
      NodePortDefinition(name: 'value', type: 'text', label: 'Value'),
    ],
    outputPorts: [
      NodePortDefinition(name: 'loop', type: 'text', label: 'Loop'),
      NodePortDefinition(name: 'done', type: 'text', label: 'Done'),
    ],
    params: [
      NodeParamDefinition(
        name: 'count',
        label: 'Iterations',
        control: NodeParamControl.number,
        defaultValue: 3,
      ),
    ],
  ),
]);
