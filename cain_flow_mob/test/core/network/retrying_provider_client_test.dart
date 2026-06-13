import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/core/network/provider_error.dart';
import 'package:cain_flow_mob/core/network/retrying_provider_client.dart';
import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProviderRequest buildRequest() {
    return const ProviderRequest(
      url: 'http://localhost/v1/chat',
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: {'model': 'gpt-4.1'},
    );
  }

  test('returns immediately on first success without retrying', () async {
    final fake = _FakeProviderClient([
      _Outcome.response(const ProviderResponse(statusCode: 200, body: '{}')),
    ]);
    final client = RetryingProviderClient(inner: fake, maxRetries: 3);

    final response = await client.send(buildRequest());

    expect(response.statusCode, 200);
    expect(fake.calls, 1);
  });

  test('retries transient server errors up to maxRetries then succeeds', () async {
    final fake = _FakeProviderClient([
      _Outcome.response(const ProviderResponse(statusCode: 500, body: 'boom')),
      _Outcome.response(const ProviderResponse(statusCode: 503, body: 'boom')),
      _Outcome.response(const ProviderResponse(statusCode: 200, body: 'ok')),
    ]);
    final client = RetryingProviderClient(inner: fake, maxRetries: 3);

    final response = await client.send(buildRequest());

    expect(response.statusCode, 200);
    expect(fake.calls, 3);
  });

  test('stops after exhausting retries and returns last failure response', () async {
    final fake = _FakeProviderClient([
      _Outcome.response(const ProviderResponse(statusCode: 429, body: 'rate')),
      _Outcome.response(const ProviderResponse(statusCode: 429, body: 'rate')),
    ]);
    final client = RetryingProviderClient(inner: fake, maxRetries: 1);

    final response = await client.send(buildRequest());

    expect(response.statusCode, 429);
    expect(fake.calls, 2);
  });

  test('does not retry non-transient auth errors', () async {
    final fake = _FakeProviderClient([
      _Outcome.response(const ProviderResponse(statusCode: 401, body: 'no')),
    ]);
    final client = RetryingProviderClient(inner: fake, maxRetries: 5);

    final response = await client.send(buildRequest());

    expect(response.statusCode, 401);
    expect(fake.calls, 1);
  });

  test('retries transient transport exceptions', () async {
    final timeoutError = ProviderError(
      category: ProviderErrorCategory.timeout,
      statusCode: 0,
      safeUrl: 'http://localhost/v1/chat',
      safeHeaders: const {},
      message: 'timed out',
      rawBodyPreview: '',
    );
    final fake = _FakeProviderClient([
      _Outcome.throws(ProviderTransportException(timeoutError)),
      _Outcome.response(const ProviderResponse(statusCode: 200, body: 'ok')),
    ]);
    final client = RetryingProviderClient(inner: fake, maxRetries: 2);

    final response = await client.send(buildRequest());

    expect(response.statusCode, 200);
    expect(fake.calls, 2);
  });

  test('respects cancellation before retrying', () async {
    final fake = _FakeProviderClient([
      _Outcome.response(const ProviderResponse(statusCode: 500, body: 'boom')),
      _Outcome.response(const ProviderResponse(statusCode: 200, body: 'ok')),
    ]);
    final token = ProviderCancellationToken();
    final client = RetryingProviderClient(
      inner: fake,
      maxRetries: 3,
      delay: (attempt) async => token.cancel(),
    );

    await expectLater(
      client.send(
        buildRequest(),
        options: ProviderRequestOptions(cancellationToken: token),
      ),
      throwsA(isA<ProviderRequestCanceled>()),
    );
    expect(fake.calls, 1);
  });
}

class _Outcome {
  _Outcome.response(this.response) : error = null;
  _Outcome.throws(this.error) : response = null;

  final ProviderResponse? response;
  final Object? error;
}

class _FakeProviderClient implements ProviderClient {
  _FakeProviderClient(this._outcomes);

  final List<_Outcome> _outcomes;
  int calls = 0;

  @override
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    final outcome = _outcomes[calls];
    calls += 1;
    if (outcome.error != null) throw outcome.error!;
    return outcome.response!;
  }
}
