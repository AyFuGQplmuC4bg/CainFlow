import 'package:cain_flow_mob/features/nodes/node_registry.dart';
import 'package:cain_flow_mob/features/workbench/widgets/node_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single-port output anchors inside the base card height', () {
    final def = nodeRegistry.get('Text'); // 0 in, 1 out
    final y = portAnchorY(def, isOutput: true, portIndex: 0, hasImage: false);
    expect(y, greaterThan(0));
    expect(y, lessThan(nodeCardHeight(def)));
  });

  test('card height grows with extra port rows', () {
    final twoPort = nodeRegistry.get('ImageSave'); // 1 in, 0 out
    final fourPort = nodeRegistry.get('ImageGenerate'); // 3 in (prompt+2), out
    expect(nodeCardHeight(fourPort), greaterThan(nodeCardHeight(twoPort)));
  });

  test('later input ports anchor lower than earlier ones', () {
    final gen = nodeRegistry.get('ImageGenerate');
    final first = portAnchorY(
      gen,
      isOutput: false,
      portIndex: 0,
      hasImage: false,
    );
    final last = portAnchorY(
      gen,
      isOutput: false,
      portIndex: 2,
      hasImage: false,
    );
    expect(last, greaterThan(first));
  });

  test('thumbnail increases card height and shifts anchors down', () {
    final gen = nodeRegistry.get('ImageGenerate');
    final noImg = portAnchorY(
      gen,
      isOutput: true,
      portIndex: 0,
      hasImage: false,
    );
    final withImg = portAnchorY(
      gen,
      isOutput: true,
      portIndex: 0,
      hasImage: true,
    );
    expect(withImg, greaterThan(noImg));
    expect(nodeCardHeight(gen, hasImage: true) - nodeCardHeight(gen), 84);
  });
}
