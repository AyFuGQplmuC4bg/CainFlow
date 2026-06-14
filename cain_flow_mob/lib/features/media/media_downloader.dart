import 'dart:io';
import 'dart:typed_data';

/// Downloads remote media to bytes using `dart:io` HttpClient. Kept tiny and
/// injectable so the executor can persist URL results to local assets.
class MediaDownloader {
  MediaDownloader({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  /// Fetches [url] and returns its bytes plus the response content type.
  /// Throws [MediaDownloadException] on non-2xx or transport errors.
  Future<DownloadedMedia> download(
    String url, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final client = _clientFactory();
    try {
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MediaDownloadException(
          'Download failed (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
      }
      final contentType =
          response.headers.contentType?.mimeType ?? 'image/png';
      return DownloadedMedia(
        bytes: builder.toBytes(),
        mimeType: contentType,
      );
    } on MediaDownloadException {
      rethrow;
    } catch (error) {
      throw MediaDownloadException('Download error: $error');
    } finally {
      client.close(force: true);
    }
  }
}

class DownloadedMedia {
  const DownloadedMedia({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

class MediaDownloadException implements Exception {
  const MediaDownloadException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'MediaDownloadException: $message';
}
