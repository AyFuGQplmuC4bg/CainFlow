import 'dart:convert';

import '../../core/network/provider_client.dart';
import '../execution/provider_request_builder.dart';
import '../settings/provider_settings.dart';

/// Outcome of a provider connectivity / auth probe.
class ProviderCheckResult {
  const ProviderCheckResult({
    required this.ok,
    required this.message,
    this.models = const [],
  });

  final bool ok;
  final String message;

  /// Model ids discovered from the endpoint, when available.
  final List<String> models;
}

/// Probes a provider endpoint for reachability/auth and can list its models.
/// Uses the shared [ProviderClient] so it honors the same transport.
class ProviderHealthChecker {
  const ProviderHealthChecker({required this.client});

  final ProviderClient client;

  /// Sends a lightweight request and classifies the response. For OpenAI this
  /// hits `/models`; for Google it lists models on the v1beta endpoint.
  Future<ProviderCheckResult> check(ProviderConfig provider) async {
    try {
      final request = _modelsRequest(provider);
      final response = await client.send(request);
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const ProviderCheckResult(
          ok: false,
          message: 'Authentication failed (check API key)',
        );
      }
      if (!response.isSuccess) {
        return ProviderCheckResult(
          ok: false,
          message: 'Endpoint returned ${response.statusCode}',
        );
      }
      final models = _parseModels(response.body);
      return ProviderCheckResult(
        ok: true,
        message: models.isEmpty
            ? 'Reachable'
            : 'Reachable (${models.length} models)',
        models: models,
      );
    } on ProviderTransportException catch (e) {
      return ProviderCheckResult(ok: false, message: e.error.message);
    } catch (e) {
      return ProviderCheckResult(ok: false, message: 'Error: $e');
    }
  }

  ProviderRequest _modelsRequest(ProviderConfig provider) {
    final endpoint = normalizeProviderEndpoint(provider.endpoint);
    if (provider.protocol == ModelProtocol.google) {
      final base = endpoint.replaceAll(RegExp(r'/+$'), '');
      return ProviderRequest(
        url: '$base/v1beta/models?key=${Uri.encodeQueryComponent(provider.apiKey)}',
        method: 'GET',
        headers: const {'Accept': 'application/json'},
        body: const {},
      );
    }
    // OpenAI-compatible: <base>/v1/models
    final base = endpoint.replaceAll(RegExp(r'/+$'), '');
    final withVersion = RegExp(r'/v\d+$').hasMatch(base) ? base : '$base/v1';
    return ProviderRequest(
      url: '$withVersion/models',
      method: 'GET',
      headers: {
        'Accept': 'application/json',
        if (provider.apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${provider.apiKey.trim()}',
      },
      body: const {},
    );
  }

  List<String> _parseModels(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return const [];
      // OpenAI: { data: [ { id } ] }
      final data = decoded['data'];
      if (data is List) {
        return [
          for (final item in data)
            if (item is Map && item['id'] != null) item['id'].toString(),
        ];
      }
      // Google: { models: [ { name: "models/gemini-..." } ] }
      final models = decoded['models'];
      if (models is List) {
        return [
          for (final item in models)
            if (item is Map && item['name'] != null)
              item['name'].toString().replaceFirst('models/', ''),
        ];
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }
}
