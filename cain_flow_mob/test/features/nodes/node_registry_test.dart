import 'package:cain_flow_mob/features/nodes/node_definition.dart';
import 'package:cain_flow_mob/features/nodes/node_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry exposes the first CainFlow node definitions', () {
    expect(nodeRegistry.get('Text')?.title, 'Text Prompt');
    expect(nodeRegistry.get('ImageGenerate')?.outputPorts.single.name, 'image');
    expect(nodeRegistry.get('ImageSave')?.inputPorts.single.name, 'image');
    expect(nodeRegistry.all.map((definition) => definition.type), contains('TextChat'));
  });

  test('Text node declares a multiline text param with empty default', () {
    final text = nodeRegistry.get('Text')!;
    final param = text.params.single;
    expect(param.name, 'text');
    expect(param.control, NodeParamControl.multiline);
    expect(param.defaultValue, '');
  });

  test('TextChat declares a chat model picker and custom params', () {
    final chat = nodeRegistry.get('TextChat')!;
    final picker = chat.params.firstWhere((p) => p.name == 'apiConfigId');
    expect(picker.control, NodeParamControl.modelPicker);
    expect(picker.taskType, 'chat');
    expect(
      chat.params.map((p) => p.control),
      contains(NodeParamControl.customParams),
    );
  });

  test('ImageGenerate declares web-aligned ports and params', () {
    final gen = nodeRegistry.get('ImageGenerate')!;
    final picker = gen.params.firstWhere((p) => p.name == 'apiConfigId');
    expect(picker.taskType, 'image');
    expect(gen.inputPorts.map((p) => p.name), contains('camera_prompt'));
    expect(gen.inputPorts.map((p) => p.name), contains('params'));
    final resolution = gen.params.firstWhere((p) => p.name == 'resolution');
    expect(resolution.control, NodeParamControl.select);
    expect(resolution.options, contains('1024x1024'));
    expect(gen.params.map((p) => p.name), contains('aspect'));
    expect(gen.params.map((p) => p.name), contains('search'));
    expect(gen.params.map((p) => p.name), isNot(contains('cameraPrompt')));
  });

  test('defaultData seeds only params that declare a default value', () {
    final chat = nodeRegistry.get('TextChat')!.defaultData();
    expect(chat['systemPrompt'], '');
    expect(chat.containsKey('apiConfigId'), isFalse);
    expect(chat.containsKey('customParams'), isFalse);
  });

  test('ImagePreview exposes an image output for chaining downstream', () {
    final preview = nodeRegistry.get('ImagePreview')!;
    expect(preview.inputPorts.single.name, 'image');
    expect(preview.outputPorts.single.name, 'image');
    expect(preview.outputPorts.single.type, 'image');
  });
}

