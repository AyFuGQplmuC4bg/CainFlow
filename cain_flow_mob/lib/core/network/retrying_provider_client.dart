import '../../features/execution/provider_request_builder.dart';
import 'provider_client.dart';
import 'provider_error.dart';

/// Wraps a [ProviderClient] and retries only transient failures.
///
/// Transient categories: timeout, rate limit, server. Permanent categories
/// (auth, forbidden, model not found, invalid request) are never retried.
class RetryingProviderClient implements ProviderClient {
  RetryingProviderClient({
    required this.inner,
    this.maxRetries = 0,
    this.delay,
  });

  final ProviderClient inner;

  /// Number of additional attempts after the first try. 0 means no retry.
  final int maxRetries;

  /// Optional backoff hook invoked before each retry with the attempt index.
  final Future<void> Function(int attempt)? delay;

  static const _transientCategories = {
    ProviderErrorCategory.timeout,
    ProviderErrorCategory.rateLimit,
    ProviderErrorCategory.server,
  };

  @override
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    final token = options.cancellationToken;
    var attempt = 0;

    while (true) {
      token?.throwIfCanceled();

      ProviderResponse? response;
      ProviderError? error;
      try {
        response = await inner.send(request, options: options);
        if (response.isSuccess) return response;
        error = response.toError(request);
      } on ProviderRequestCanceled {
        rethrow;
      } on ProviderTransportException catch (e) {
        error = e.error;
      }

      final canRetry =
          attempt < maxRetries && _transientCategories.contains(error.category);
      if (!canRetry) {
        if (response != null) return response;
        throw ProviderTransportException(error);
      }

      attempt += 1;
      token?.throwIfCanceled();
      if (delay != null) await delay!(attempt);
    }
  }
}
