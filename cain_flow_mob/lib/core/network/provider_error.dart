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

String formatProviderErrorMessage(ProviderError error) {
  final detail = _compactProviderErrorDetail(error.message);
  return switch (error.category) {
    ProviderErrorCategory.auth => _joinProviderErrorMessage(
      '认证失败，请检查 API Key 是否正确。',
      detail,
    ),
    ProviderErrorCategory.rateLimit => _joinProviderErrorMessage(
      '请求过于频繁，请稍后重试。',
      detail,
    ),
    ProviderErrorCategory.timeout => _joinProviderErrorMessage(
      '请求超时，请稍后重试或调大超时设置。',
      detail,
    ),
    ProviderErrorCategory.forbidden => _joinProviderErrorMessage(
      '请求被服务端拒绝，请检查权限、IP 限制或人机验证。',
      detail,
    ),
    ProviderErrorCategory.modelNotFound => _joinProviderErrorMessage(
      '模型不存在或当前服务商不可用，请检查模型 ID 配置。',
      detail,
    ),
    ProviderErrorCategory.invalidRequest => _joinProviderErrorMessage(
      '请求参数无效，请检查节点输入或服务商配置。',
      detail,
    ),
    ProviderErrorCategory.server => _joinProviderErrorMessage(
      '服务端异常或网络连接失败，请稍后重试。',
      detail,
    ),
    ProviderErrorCategory.unknown => _joinProviderErrorMessage('模型请求失败。', detail),
  };
}

String _joinProviderErrorMessage(String prefix, String detail) {
  if (detail.isEmpty) return prefix;
  return '$prefix 详细信息: $detail';
}

String _compactProviderErrorDetail(String message) {
  final compact = message.trim().replaceAll(RegExp(r'\s+'), ' ');
  return compact.length > 240 ? '${compact.substring(0, 240)}...' : compact;
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
