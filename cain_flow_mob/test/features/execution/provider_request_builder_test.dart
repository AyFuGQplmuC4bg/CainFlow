import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const provider = ProviderConfig(
    id: 'prov_openai',
    name: 'OpenAI compatible',
    protocol: ModelProtocol.openai,
    apiKey: 'sk-live-secret',
    endpoint: 'https://api.example.com',
  );
  const chatModel = ModelConfig(
    id: 'model_chat',
    name: 'Chat',
    modelId: 'gpt-4.1',
    taskType: ModelTaskType.chat,
    protocol: ModelProtocol.openai,
    providerIds: ['prov_openai'],
  );

  test('builds OpenAI-compatible chat requests', () {
    final request = ProviderRequestBuilder.buildChatRequest(
      provider: provider,
      model: chatModel,
      prompt: 'Hello',
      systemPrompt: 'Be concise',
    );

    expect(request.url, 'https://api.example.com/v1/chat/completions');
    expect(request.headers['Authorization'], 'Bearer sk-live-secret');
    expect(request.redactedHeaders['Authorization'], 'Bearer sk-...cret');
    expect(request.body['model'], 'gpt-4.1');
    expect(request.body['messages'], hasLength(2));
  });

  test('builds Gemini generateContent chat requests', () {
    const googleProvider = ProviderConfig(
      id: 'prov_google',
      name: 'Google',
      protocol: ModelProtocol.google,
      apiKey: 'AIza-google-secret',
      endpoint: 'https://generativelanguage.googleapis.com',
    );
    const googleModel = ModelConfig(
      id: 'model_gemini',
      name: 'Gemini',
      modelId: 'gemini-3-flash-preview',
      taskType: ModelTaskType.chat,
      protocol: ModelProtocol.google,
      providerIds: ['prov_google'],
    );

    final request = ProviderRequestBuilder.buildChatRequest(
      provider: googleProvider,
      model: googleModel,
      prompt: 'Hello',
    );

    expect(
      request.url,
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=AIza-google-secret',
    );
    expect(request.body['contents'], isA<List>());
    expect(request.redactedUrl, contains('key=AIza...cret'));
  });

  test('builds OpenAI image generation requests', () {
    const imageModel = ModelConfig(
      id: 'model_image',
      name: 'Image',
      modelId: 'gpt-image-2',
      taskType: ModelTaskType.image,
      protocol: ModelProtocol.openai,
      providerIds: ['prov_openai'],
    );

    final request = ProviderRequestBuilder.buildImageRequest(
      provider: provider,
      model: imageModel,
      prompt: 'A small desk lamp',
      resolution: '1024x1024',
    );

    expect(request.url, 'https://api.example.com/v1/images/generations');
    expect(request.body['model'], 'gpt-image-2');
    expect(request.body['size'], '1024x1024');
  });

  test('builds OpenAI image edit requests when references are present', () {
    const imageModel = ModelConfig(
      id: 'model_image',
      name: 'Image',
      modelId: 'gpt-image-2',
      taskType: ModelTaskType.image,
      protocol: ModelProtocol.openai,
      providerIds: ['prov_openai'],
    );

    final request = ProviderRequestBuilder.buildImageRequest(
      provider: provider,
      model: imageModel,
      prompt: 'A small desk lamp',
      referenceImages: const ['https://cdn/a.png'],
      maskImage: 'data:image/png;base64,AAAA',
      moderation: 'auto',
      background: 'transparent',
      generationCount: 2,
    );

    expect(request.url, 'https://api.example.com/v1/images/edits');
    expect(request.body['model'], 'gpt-image-2');
    expect(request.body['prompt'], 'A small desk lamp');
    expect(request.body['moderation'], 'auto');
    expect(request.body['background'], 'transparent');
    expect(request.body['n'], 2);
    expect(request.headers.containsKey('Content-Type'), isFalse);
    expect(request.multipart, hasLength(2));
    expect(request.multipart.first.field, 'image');
    expect(request.multipart.first.contentType, 'text/uri-list');
    expect(
      String.fromCharCodes(request.multipart.first.bytes),
      'https://cdn/a.png',
    );
    expect(request.multipart.last.field, 'mask');
    expect(request.multipart.last.contentType, 'image/png');
  });

  test('ignores unsupported aspect and search at request-builder level', () {
    const imageModel = ModelConfig(
      id: 'model_image',
      name: 'Image',
      modelId: 'gpt-image-2',
      taskType: ModelTaskType.image,
      protocol: ModelProtocol.openai,
      providerIds: ['prov_openai'],
    );

    final request = ProviderRequestBuilder.buildImageRequest(
      provider: provider,
      model: imageModel,
      prompt: 'A small desk lamp',
      resolution: '1024x1024',
      aspect: '16:9',
      search: true,
    );

    expect(request.body['size'], '1024x1024');
    expect(request.body.containsKey('aspect'), isFalse);
    expect(request.body.containsKey('search'), isFalse);
  });
}
