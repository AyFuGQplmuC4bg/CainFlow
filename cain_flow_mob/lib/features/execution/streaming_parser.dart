import 'dart:convert';

import '../settings/provider_settings.dart';

/// Parses Server-Sent Events (SSE) chat streaming chunks into text deltas.
///
/// OpenAI streams `data: {json}` lines where each json has
/// `choices[0].delta.content`; a final `data: [DONE]` terminates. Gemini
/// streams JSON objects with `candidates[0].content.parts[].text`.
abstract final class StreamingParser {
  /// Extracts the incremental text from one SSE `data:` payload, or null if
  /// the line carries no text (e.g. role-only delta, `[DONE]`, keep-alive).
  static String? deltaFromLine(String line, ModelProtocol protocol) {
    var data = line.trim();
    if (data.isEmpty) return null;
    if (data.startsWith('data:')) data = data.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    return switch (protocol) {
      ModelProtocol.google => _googleDelta(decoded),
      _ => _openAiDelta(decoded),
    };
  }

  /// Splits a raw streamed buffer into lines and joins all text deltas.
  static String accumulate(String raw, ModelProtocol protocol) {
    final buffer = StringBuffer();
    for (final line in const LineSplitter().convert(raw)) {
      final delta = deltaFromLine(line, protocol);
      if (delta != null) buffer.write(delta);
    }
    return buffer.toString();
  }

  static String? _openAiDelta(Map<dynamic, dynamic> json) {
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final delta = first['delta'];
        if (delta is Map && delta['content'] is String) {
          return delta['content'] as String;
        }
        // Some providers send full message on the final chunk.
        final message = first['message'];
        if (message is Map && message['content'] is String) {
          return message['content'] as String;
        }
      }
    }
    return null;
  }

  static String? _googleDelta(Map<dynamic, dynamic> json) {
    final candidates = json['candidates'];
    if (candidates is List && candidates.isNotEmpty) {
      final content = (candidates.first as Map?)?['content'];
      if (content is Map) {
        final parts = content['parts'];
        if (parts is List) {
          final buffer = StringBuffer();
          for (final part in parts) {
            if (part is Map && part['text'] is String) {
              buffer.write(part['text']);
            }
          }
          final text = buffer.toString();
          return text.isEmpty ? null : text;
        }
      }
    }
    return null;
  }
}
