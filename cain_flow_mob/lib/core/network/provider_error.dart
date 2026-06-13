import '../../features/execution/provider_request_builder.dart';
import '../../features/settings/provider_settings.dart';

enum ProviderErrorCategory {
  auth,
  rateLimit,
  timeout,
  forbidden,
  modelNotFound,
  invalidRequest,
  server,
  unknown,
}

class ProviderError {
  const ProviderError({
    required this.category,
    required this.statusCode,
    required this.safeUrl,
    required this.safeHeaders,
    required this.message,
    required this.rawBodyPreview,
  });

  factory ProviderError.fromResponse({
    required int statusCode,
    required String url,
    required Map<String, String> headers,
    required String body,
  }) {
    return ProviderError(
      category: _categoryFrom(statusCode, body),
      statusCode: statusCode,
      safeUrl: redactUrlSecrets(url),
      safeHeaders: {
        for (final entry in headers.entries)
          entry.key: entry.key.toLowerCase() == 'authorization'
              ? _maskAuthorization(entry.value)
              : entry.value,
      },
      message: _messageFrom(statusCode, body),
      rawBodyPreview: body.length > 600 ? '${body.substring(0, 600)}...' : body,
    );
  }

  final ProviderErrorCategory category;
  final int statusCode;
  final String safeUrl;
  final Map<String, String> safeHeaders;
  final String message;
  final String rawBodyPreview;
}

ProviderErrorCategory _categoryFrom(int statusCode, String body) {
  final normalized = body.toLowerCase();
  if (statusCode == 401 || normalized.contains('unauthorized')) {
    return ProviderErrorCategory.auth;
  }
  if (statusCode == 403 || normalized.contains('forbidden')) {
    return ProviderErrorCategory.forbidden;
  }
  if (statusCode == 404 || normalized.contains('model not found')) {
    return ProviderErrorCategory.modelNotFound;
  }
  if (statusCode == 408 || statusCode == 504 || normalized.contains('timeout')) {
    return ProviderErrorCategory.timeout;
  }
  if (statusCode == 429 || normalized.contains('rate limit')) {
    return ProviderErrorCategory.rateLimit;
  }
  if (statusCode >= 400 && statusCode < 500) {
    return ProviderErrorCategory.invalidRequest;
  }
  if (statusCode >= 500) return ProviderErrorCategory.server;
  return ProviderErrorCategory.unknown;
}

String _messageFrom(int statusCode, String body) {
  if (body.trim().isEmpty) return 'Provider request failed ($statusCode)';
  return body.length > 240 ? '${body.substring(0, 240)}...' : body;
}

String _maskAuthorization(String value) {
  final bearer = RegExp(r'^Bearer\s+(.+)$', caseSensitive: false).firstMatch(value);
  if (bearer != null) return 'Bearer ${maskSecret(bearer.group(1)!)}';
  return maskSecret(value);
}
