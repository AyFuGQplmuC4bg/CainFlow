import 'dart:io';

import 'package:cain_flow_mob/features/media/media_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloads bytes and reports content type', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final downloader = MediaDownloader();
    final result = await downloader.download(
      'http://${server.address.host}:${server.port}/a.png',
    );

    expect(result.bytes, [1, 2, 3, 4]);
    expect(result.mimeType, 'image/png');
  });

  test('throws MediaDownloadException on non-2xx', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 404;
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final downloader = MediaDownloader();
    await expectLater(
      downloader.download('http://${server.address.host}:${server.port}/x'),
      throwsA(isA<MediaDownloadException>()),
    );
  });
}
