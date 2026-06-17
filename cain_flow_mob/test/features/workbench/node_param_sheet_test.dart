import 'package:cain_flow_mob/features/nodes/node_registry.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:cain_flow_mob/features/workbench/widgets/node_param_sheet.dart';
import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required WorkbenchNode node,
    required ValueChanged<Map<String, dynamic>> onChanged,
    VoidCallback? onDelete,
    List<ModelConfig> models = const [],
    List<ProviderConfig> providers = const [],
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NodeParamSheet(
            node: node,
            definition: nodeRegistry.get(node.type),
            models: models,
            providers: providers,
            onChanged: onChanged,
            onDelete: onDelete ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('editing a text field writes back through onChanged', (
    tester,
  ) async {
    Map<String, dynamic>? captured;
    await pump(
      tester,
      node: const WorkbenchNode(
        id: 'n',
        type: 'Text',
        title: 'Text Prompt',
        x: 0,
        y: 0,
      ),
      onChanged: (data) => captured = data,
    );

    await tester.enterText(
      find.byKey(const ValueKey('param_text')),
      'hello world',
    );
    expect(captured?['text'], 'hello world');
  });

  testWidgets('model picker lists models filtered by task type', (
    tester,
  ) async {
    Map<String, dynamic>? captured;
    await pump(
      tester,
      node: const WorkbenchNode(
        id: 'c',
        type: 'TextChat',
        title: 'Text Chat',
        x: 0,
        y: 0,
      ),
      models: const [
        ModelConfig(
          id: 'm-chat',
          name: 'Chatter',
          modelId: 'gpt',
          taskType: ModelTaskType.chat,
          protocol: ModelProtocol.openai,
          providerIds: ['p'],
        ),
        ModelConfig(
          id: 'm-img',
          name: 'Painter',
          modelId: 'dalle',
          taskType: ModelTaskType.image,
          protocol: ModelProtocol.openai,
          providerIds: ['p'],
        ),
      ],
      onChanged: (data) => captured = data,
    );

    await tester.tap(find.byKey(const ValueKey('param_apiConfigId')));
    await tester.pumpAndSettle();
    // Chat model is offered; image model is filtered out.
    expect(find.text('Chatter').hitTestable(), findsOneWidget);
    expect(find.text('Painter'), findsNothing);

    await tester.tap(find.text('Chatter').last);
    await tester.pumpAndSettle();
    expect(captured?['apiConfigId'], 'm-chat');
  });

  testWidgets('model picker writes provider when selected model has choices', (
    tester,
  ) async {
    Map<String, dynamic>? captured;
    await pump(
      tester,
      node: const WorkbenchNode(
        id: 'c',
        type: 'TextChat',
        title: 'Text Chat',
        x: 0,
        y: 0,
      ),
      models: const [
        ModelConfig(
          id: 'm-chat',
          name: 'Chatter',
          modelId: 'gpt',
          taskType: ModelTaskType.chat,
          protocol: ModelProtocol.openai,
          providerIds: ['prov_fast', 'prov_slow'],
        ),
      ],
      providers: const [
        ProviderConfig(
          id: 'prov_fast',
          name: 'Fast Provider',
          protocol: ModelProtocol.openai,
          apiKey: 'fast-key',
          endpoint: 'https://fast.example.com',
        ),
        ProviderConfig(
          id: 'prov_slow',
          name: 'Slow Provider',
          protocol: ModelProtocol.openai,
          apiKey: 'slow-key',
          endpoint: 'https://slow.example.com',
        ),
      ],
      onChanged: (data) => captured = data,
    );

    await tester.tap(find.byKey(const ValueKey('param_apiConfigId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chatter').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('param_providerId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Slow Provider').last);
    await tester.pumpAndSettle();

    expect(captured?['apiConfigId'], 'm-chat');
    expect(captured?['providerId'], 'prov_slow');
  });

  testWidgets('delete button invokes onDelete', (tester) async {
    var deleted = false;
    await pump(
      tester,
      node: const WorkbenchNode(
        id: 'n',
        type: 'ImageSave',
        title: 'Image Save',
        x: 0,
        y: 0,
      ),
      onChanged: (_) {},
      onDelete: () => deleted = true,
    );

    await tester.tap(find.byTooltip('Delete node'));
    expect(deleted, isTrue);
  });

  testWidgets('ImageGenerate exposes the web-aligned params', (tester) async {
    await pump(
      tester,
      node: const WorkbenchNode(
        id: 'img',
        type: 'ImageGenerate',
        title: 'Image Generate',
        x: 0,
        y: 0,
      ),
      onChanged: (_) {},
      models: const [
        ModelConfig(
          id: 'm-img',
          name: 'Painter',
          modelId: 'gpt-image-1',
          taskType: ModelTaskType.image,
          protocol: ModelProtocol.openai,
          providerIds: ['p'],
        ),
      ],
    );

    expect(find.byKey(const ValueKey('param_apiConfigId')), findsOneWidget);
    expect(find.byKey(const ValueKey('param_resolution')), findsOneWidget);
    expect(find.byKey(const ValueKey('param_aspect')), findsOneWidget);
    expect(find.byKey(const ValueKey('param_quality')), findsOneWidget);
    expect(find.byKey(const ValueKey('param_moderation')), findsOneWidget);
    expect(find.byKey(const ValueKey('param_background')), findsOneWidget);
    expect(find.byKey(const ValueKey('param_search')), findsOneWidget);
    expect(find.byKey(const ValueKey('param_generationCount')), findsOneWidget);
    expect(find.byKey(const ValueKey('param_customParams')), findsOneWidget);
  });
}
