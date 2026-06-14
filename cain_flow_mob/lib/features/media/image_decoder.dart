import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'media_repository.dart';

/// Strips a `data:...;base64,` prefix from [value], returning the raw base64.
String stripDataUri(String value) {
  final match = RegExp(r'^data:[^;]+;base64,(.*)$').firstMatch(value.trim());
  return match != null ? match.group(1)! : value.trim();
}

/// Resolves an image payload (`{kind: asset|url|b64}` or a bare base64/data
/// string) to raw bytes. Asset payloads read the local file via [media];
/// `b64`/string payloads decode in-place. URL payloads are not fetched here
/// (the camera preview only needs local/inline images) and return null.
///
/// Shared by the executor and the camera editor so both decode identically.
Future<Uint8List?> imagePayloadToBytes(
  Object? payload,
  MediaRepository media,
) async {
  if (payload is Map) {
    final map = Map<String, dynamic>.from(payload);
    final kind = map['kind']?.toString();
    if (kind == 'asset') {
      final relativePath = map['relativePath']?.toString() ?? '';
      if (relativePath.isEmpty) return null;
      final root = await media.mediaRoot();
      final file = File(
        '${root.path}${Platform.pathSeparator}$relativePath',
      );
      if (!await file.exists()) return null;
      return Uint8List.fromList(await file.readAsBytes());
    }
    final b64 = map['b64_json']?.toString() ?? map['base64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      return Uint8List.fromList(base64Decode(stripDataUri(b64)));
    }
    return null;
  }
  if (payload is String && payload.isNotEmpty && !payload.startsWith('http')) {
    return Uint8List.fromList(base64Decode(stripDataUri(payload)));
  }
  return null;
}

/// Decodes an image payload into a [ui.Image] for canvas rendering, or null
/// when the payload is empty, remote, or fails to decode.
Future<ui.Image?> decodeImagePayload(
  Object? payload,
  MediaRepository media,
) async {
  try {
    final bytes = await imagePayloadToBytes(payload, media);
    if (bytes == null || bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}
