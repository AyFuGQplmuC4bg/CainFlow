import 'dart:convert';
import 'dart:io';

import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/core/network/provider_error.dart';
import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;

  tearDown(() async {
    await server.close(force: true);
  });

  ProviderRequest requestFor(HttpServer s, {String path = '/v1/chat'}) {
    return ProviderRequest(
      url: 'http://${s.address.host}:${s.port}$path',
      method: 'POST',
      headers: const {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer sk-secret-token',
      },
      body: const {'model': 'gpt-4.1', 'prompt': 'hi'},
    );
  }

  test('sends JSON body and decodes UTF-8 response', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? receivedBody;
    server.listen((req) async {
      receivedBody = await utf8.decoder.bind(req).join();
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write('{"ok": true, "text": "héllo"}');
      await req.response.close();
    });

    final client = DartIoProviderClient();
    final response = await client.send(requestFor(server));

    expect(response.statusCode, 200);
    expect(response.isSuccess, isTrue);
    expect(response.body, contains('héllo'));
    expect(receivedBody, contains('"model":"gpt-4.1"'));
  });

  test('maps a slow response to a sanitized timeout error', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      req.response.statusCode = 200;
      await req.response.close();
    });

    final client = DartIoProviderClient();

    await expectLater(
      client.send(
        requestFor(server),
        options: const ProviderRequestOptions(
          timeout: Duration(milliseconds: 100),
        ),
      ),
      throwsA(
        isA<ProviderTransportException>().having(
          (e) => e.error.category,
          'category',
          ProviderErrorCategory.timeout,
        ),
      ),
    );
  });

  test('throws ProviderRequestCanceled when token is canceled upfront', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response.statusCode = 200;
      await req.response.close();
    });

    final client = DartIoProviderClient();
    final token = ProviderCancellationToken()..cancel();

    await expectLater(
      client.send(
        requestFor(server),
        options: ProviderRequestOptions(cancellationToken: token),
      ),
      throwsA(isA<ProviderRequestCanceled>()),
    );
  });

  test('error output never exposes the authorization secret', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await Future<void>.delayed(const Duration(seconds: 2));
      await req.response.close();
    });

    final client = DartIoProviderClient();

    try {
      await client.send(
        requestFor(server),
        options: const ProviderRequestOptions(
          timeout: Duration(milliseconds: 100),
        ),
      );
      fail('expected timeout');
    } on ProviderTransportException catch (e) {
      final dump = '${e.error.safeUrl} ${e.error.safeHeaders} ${e.error.message}';
      expect(dump, isNot(contains('sk-secret-token')));
      expect(e.error.safeHeaders['Authorization'], contains('Bearer'));
    }
  });
}
