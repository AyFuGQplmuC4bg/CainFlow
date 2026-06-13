import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../features/execution/provider_request_builder.dart';
import 'provider_error.dart';

abstract interface class ProviderClient {
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options,
  });
}

class ProviderRequestOptions {
  const ProviderRequestOptions({this.timeout, this.cancellationToken});

  final Duration? timeout;
  final ProviderCancellationToken? cancellationToken;
}

class ProviderCancellationToken {
  bool _canceled = false;

  bool get isCanceled => _canceled;

  void cancel() {
    _canceled = true;
  }

  void throwIfCanceled() {
    if (_canceled) {
      throw const ProviderRequestCanceled();
    }
  }
}

class ProviderRequestCanceled implements Exception {
  const ProviderRequestCanceled();

  @override
  String toString() => 'ProviderRequestCanceled';
}

/// Raised for transport-level failures (timeout, cancellation, socket errors)
/// where no HTTP status is available. Carries a sanitized [ProviderError].
class ProviderTransportException implements Exception {
  const ProviderTransportException(this.error);

  final ProviderError error;

  @override
  String toString() => 'ProviderTransportException(${error.category.name})';
}

class ProviderResponse {
  const ProviderResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  ProviderError toError(ProviderRequest request) {
    return ProviderError.fromResponse(
      statusCode: statusCode,
      url: request.url,
      headers: request.headers,
      body: body,
    );
  }
}

class DartIoProviderClient implements ProviderClient {
  DartIoProviderClient({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  @override
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    final token = options.cancellationToken;
    token?.throwIfCanceled();

    final client = _clientFactory();
    if (options.timeout != null) {
      client.connectionTimeout = options.timeout;
    }

    try {
      final future = _perform(client, request, options);
      final response = options.timeout != null
          ? await future.timeout(options.timeout!)
          : await future;
      token?.throwIfCanceled();
      return response;
    } on TimeoutException {
      client.close(force: true);
      throw ProviderTransportException(
        _transportError(request, ProviderErrorCategory.timeout, 'Request timed out'),
      );
    } on ProviderRequestCanceled {
      client.close(force: true);
      rethrow;
    } on SocketException catch (error) {
      client.close(force: true);
      throw ProviderTransportException(
        _transportError(
          request,
          ProviderErrorCategory.server,
          'Network error: ${error.message}',
        ),
      );
    } on HttpException catch (error) {
      client.close(force: true);
      throw ProviderTransportException(
        _transportError(
          request,
          ProviderErrorCategory.server,
          'HTTP error: ${error.message}',
        ),
      );
    } finally {
      client.close();
    }
  }

  Future<ProviderResponse> _perform(
    HttpClient client,
    ProviderRequest request,
    ProviderRequestOptions options,
  ) async {
    final token = options.cancellationToken;
    token?.throwIfCanceled();

    final uri = Uri.parse(request.url);
    final httpRequest = await client.openUrl(request.method, uri);

    token?.throwIfCanceled();

    request.headers.forEach((key, value) {
      httpRequest.headers.set(key, value);
    });

    final payload = utf8.encode(jsonEncode(request.body));
    httpRequest.add(payload);

    final httpResponse = await httpRequest.close();
    token?.throwIfCanceled();

    final body = await httpResponse.transform(utf8.decoder).join();
    token?.throwIfCanceled();

    final headers = <String, String>{};
    httpResponse.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });

    return ProviderResponse(
      statusCode: httpResponse.statusCode,
      body: body,
      headers: headers,
    );
  }

  ProviderError _transportError(
    ProviderRequest request,
    ProviderErrorCategory category,
    String message,
  ) {
    return ProviderError(
      category: category,
      statusCode: 0,
      safeUrl: request.redactedUrl,
      safeHeaders: request.redactedHeaders,
      message: message,
      rawBodyPreview: '',
    );
  }
}
