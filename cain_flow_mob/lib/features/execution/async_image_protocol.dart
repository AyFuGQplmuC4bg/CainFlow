import '../settings/provider_settings.dart';
import 'provider_request_builder.dart';

/// Pure helpers for the NewAPI-style async image protocol:
/// submit a generation task, poll its status, then extract the result URL.
///
/// Field shapes mirror the web app's `provider-request-utils.js` extractors so
/// the same providers work across both clients.
abstract final class AsyncImageProtocol {
  /// Builds the task-submission request (POST). Endpoint resolution reuses the
  /// OpenAI-style base; the async submit path is `/v1/images/generations`
  /// unless the provider endpoint already targets a specific path.
  static ProviderRequest buildSubmitRequest({
    required ProviderConfig provider,
    required ModelConfig model,
    required String prompt,
    String size = '',
    Map<String, dynamic> customParams = const {},
    List<String> referenceImages = const [],
    String? maskImage,
  }) {
    final body = <String, dynamic>{
      'model': model.modelId,
      'prompt': prompt,
      ...customParams,
    };
    if (size.isNotEmpty) body['size'] = size;
    if (referenceImages.isNotEmpty) body['image_urls'] = referenceImages;
    if (maskImage != null && maskImage.trim().isNotEmpty) {
      body['mask'] = maskImage.trim();
    }

    return ProviderRequest(
      url: _submitUrl(provider),
      method: 'POST',
      headers: _headers(provider),
      body: body,
    );
  }

  /// Builds the status-poll request (GET) for a submitted [taskId].
  static ProviderRequest buildPollRequest({
    required ProviderConfig provider,
    required String taskId,
  }) {
    return ProviderRequest(
      url: '${_pollBase(provider)}/$taskId',
      method: 'GET',
      headers: _headers(provider),
      body: const {},
    );
  }

  static String extractTaskId(Map<String, dynamic> result) {
    final data = result['data'];
    return _firstString([
      result['id'],
      result['task_id'],
      result['taskId'],
      if (data is Map) data['id'],
      if (data is Map) data['task_id'],
    ]);
  }

  /// Normalized lifecycle status: one of `completed`, `failed`, or `pending`.
  static AsyncImageStatus extractStatus(Map<String, dynamic> result) {
    final data = result['data'];
    final raw = _firstString([
      result['status'],
      result['state'],
      result['task_status'],
      if (data is Map) data['status'],
      if (data is Map) data['state'],
      if (data is Map) data['task_status'],
    ]).toLowerCase();

    if (_completedStates.contains(raw)) return AsyncImageStatus.completed;
    if (_failedStates.contains(raw)) return AsyncImageStatus.failed;
    return AsyncImageStatus.pending;
  }

  static String extractResultUrl(Map<String, dynamic> result) {
    final data = result['data'];
    final source = data is Map ? Map<String, dynamic>.from(data) : result;
    return _firstString([
      source['image_url'],
      source['url'],
      source['content_url'],
      _firstOfList(source['image_urls']),
      _firstOfList(source['result_urls']),
    ]);
  }

  static String _submitUrl(ProviderConfig provider) {
    final endpoint = normalizeProviderEndpoint(provider.endpoint);
    if (!provider.autoComplete) return endpoint;
    final base = endpoint.replaceAll(RegExp(r'/+$'), '');
    if (base.contains('/images/') || base.contains('/generations')) {
      return base;
    }
    final withVersion = RegExp(r'/v\d+$').hasMatch(base) ? base : '$base/v1';
    return '$withVersion/images/generations';
  }

  static String _pollBase(ProviderConfig provider) {
    // The poll endpoint appends the task id to the submit path, e.g.
    // POST .../images/generations -> GET .../images/generations/{taskId}.
    return _submitUrl(provider);
  }

  static Map<String, String> _headers(ProviderConfig provider) {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (provider.apiKey.trim().isNotEmpty)
        'Authorization': 'Bearer ${provider.apiKey.trim()}',
    };
  }
}

enum AsyncImageStatus { pending, completed, failed }

const _completedStates = {
  'completed',
  'succeeded',
  'success',
  'done',
  'finished',
};
const _failedStates = {'failed', 'error', 'canceled', 'cancelled'};

String _firstString(List<Object?> candidates) {
  for (final value in candidates) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value != null && value is! String) {
      final s = value.toString().trim();
      if (s.isNotEmpty) return s;
    }
  }
  return '';
}

String? _firstOfList(Object? value) {
  if (value is List && value.isNotEmpty) {
    final first = value.first;
    if (first is String) return first;
  }
  return null;
}
