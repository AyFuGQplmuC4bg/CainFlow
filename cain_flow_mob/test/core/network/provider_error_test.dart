import 'package:cain_flow_mob/core/network/provider_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider errors sanitize secrets in urls and headers', () {
    final error = ProviderError.fromResponse(
      statusCode: 401,
      url: 'https://example.com/v1/models?key=AIza-google-secret',
      headers: const {'Authorization': 'Bearer sk-live-secret'},
      body: '{"error":{"message":"invalid api key"}}',
    );

    expect(error.category, ProviderErrorCategory.auth);
    expect(error.safeUrl, contains('key=AIza...cret'));
    expect(error.safeHeaders['Authorization'], 'Bearer sk-...cret');
  });
}
