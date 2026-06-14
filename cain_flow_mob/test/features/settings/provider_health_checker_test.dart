import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:cain_flow_mob/features/settings/provider_health_checker.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const provider = ProviderConfig(
    id: 'p',
    name: 'OpenAI',
    protocol: ModelProtocol.openai,
    apiKey: 'sk-secret',
    endpoint: 'https://api.example.com',
  );

  test('reports reachable and lists OpenAI models on success', () async {
    final checker = ProviderHealthChecker(
      client: _FakeClient(
        const ProviderResponse(
          statusCode: 200,
          body: '{"data":[{"id":"gpt-4.1"},{"id":"gpt-image-1"}]}',
        ),
      ),
    );
    final result = await checker.check(provider);
    expect(result.ok, isTrue);
    expect(result.models, containsAll(['gpt-4.1', 'gpt-image-1']));
  });

  test('flags auth failure on 401', () async {
    final checker = ProviderHealthChecker(
      client: _FakeClient(const ProviderResponse(statusCode: 401, body: '')),
    );
    final result = await checker.check(provider);
    expect(result.ok, isFalse);
    expect(result.message, contains('Authentication'));
  });

  test('parses Google model names by stripping the models/ prefix', () async {
    final checker = ProviderHealthChecker(
      client: _FakeClient(
        const ProviderResponse(
          statusCode: 200,
          body: '{"models":[{"name":"models/gemini-2.0-flash"}]}',
        ),
      ),
    );
    final result = await checker.check(
      const ProviderConfig(
        id: 'g',
        name: 'Google',
        protocol: ModelProtocol.google,
        apiKey: 'key',
        endpoint: 'https://generativelanguage.googleapis.com',
      ),
    );
    expect(result.ok, isTrue);
    expect(result.models, ['gemini-2.0-flash']);
  });
}

class _FakeClient implements ProviderClient {
  _FakeClient(this._response);
  final ProviderResponse _response;

  @override
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    return _response;
  }
}
