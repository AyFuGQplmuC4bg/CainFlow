import 'package:cain_flow_mob/features/nodes/node_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry exposes the first CainFlow node definitions', () {
    expect(nodeRegistry.get('Text')?.title, 'Text Prompt');
    expect(nodeRegistry.get('ImageGenerate')?.outputPorts.single.name, 'image');
    expect(nodeRegistry.get('ImageSave')?.inputPorts.single.name, 'image');
    expect(nodeRegistry.all.map((definition) => definition.type), contains('TextChat'));
  });
}
