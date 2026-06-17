import 'dart:convert';

import '../settings/provider_settings.dart';

class ProviderRequest {
  const ProviderRequest({
    required this.url,
    required this.method,
    required this.headers,
    required this.body,
    this.multipart = const [],
  });

  final String url;
  final String method;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
  final List<ProviderMultipartPart> multipart;

  String get redactedUrl => redactUrlSecrets(url);

  Map<String, String> get redactedHeaders {
    return {
      for (final entry in headers.entries) entry.key: _redactHeader(entry),
    };
  }
}

class ProviderMultipartPart {
  const ProviderMultipartPart({
    required this.field,
    required this.filename,
    required this.contentType,
    required this.bytes,
  });

  final String field;
  final String filename;
  final String contentType;
  final List<int> bytes;
}

abstract final class ProviderRequestBuilder {
  static ProviderRequest buildChatRequest({
    required ProviderConfig provider,
    required ModelConfig model,
    required String prompt,
    String systemPrompt = '',
    Map<String, dynamic> customParams = const {},
    List<String> referenceImages = const [],
  }) {
    return switch (model.protocol) {
      ModelProtocol.google => _buildGoogleChatRequest(
        provider: provider,
        model: model,
        prompt: prompt,
        systemPrompt: systemPrompt,
        customParams: customParams,
        referenceImages: referenceImages,
      ),
      // Async-image providers have no chat path; use the OpenAI-compatible shape.
      ModelProtocol.openai ||
      ModelProtocol.newApiImageAsync => _buildOpenAiChatRequest(
        provider: provider,
        model: model,
        prompt: prompt,
        systemPrompt: systemPrompt,
        customParams: customParams,
        referenceImages: referenceImages,
      ),
    };
  }

  static ProviderRequest buildImageRequest({
    required ProviderConfig provider,
    required ModelConfig model,
    required String prompt,
    String resolution = '',
    String aspect = '',
    String quality = '',
    String moderation = '',
    String background = '',
    bool search = false,
    int generationCount = 1,
    Map<String, dynamic> customParams = const {},
    List<String> referenceImages = const [],
    String maskImage = '',
  }) {
    return switch (model.protocol) {
      ModelProtocol.google => _buildGoogleImageRequest(
        provider: provider,
        model: model,
        prompt: prompt,
        customParams: customParams,
        referenceImages: referenceImages,
      ),
      ModelProtocol.openai ||
      ModelProtocol.newApiImageAsync => _buildOpenAiImageRequest(
        provider: provider,
        model: model,
        prompt: prompt,
        resolution: resolution,
        aspect: aspect,
        quality: quality,
        moderation: moderation,
        background: background,
        search: search,
        generationCount: generationCount,
        customParams: customParams,
        referenceImages: referenceImages,
        maskImage: maskImage,
      ),
    };
  }
}

ProviderRequest _buildOpenAiChatRequest({
  required ProviderConfig provider,
  required ModelConfig model,
  required String prompt,
  required String systemPrompt,
  required Map<String, dynamic> customParams,
  List<String> referenceImages = const [],
}) {
  // With reference images, OpenAI expects a content array of text + image_url
  // parts; otherwise a plain string content keeps requests simple.
  final Object userContent = referenceImages.isEmpty
      ? prompt
      : <Map<String, dynamic>>[
          {'type': 'text', 'text': prompt},
          for (final image in referenceImages)
            {
              'type': 'image_url',
              'image_url': {'url': image},
            },
        ];
  final messages = <Map<String, dynamic>>[
    if (systemPrompt.trim().isNotEmpty)
      {'role': 'system', 'content': systemPrompt.trim()},
    {'role': 'user', 'content': userContent},
  ];
  return ProviderRequest(
    url: _resolveOpenAiUrl(provider, '/chat/completions'),
    method: 'POST',
    headers: _openAiHeaders(provider),
    body: {'model': model.modelId, 'messages': messages, ...customParams},
  );
}

ProviderRequest _buildOpenAiImageRequest({
  required ProviderConfig provider,
  required ModelConfig model,
  required String prompt,
  required String resolution,
  required String aspect,
  required String quality,
  required String moderation,
  required String background,
  required bool search,
  required int generationCount,
  required Map<String, dynamic> customParams,
  List<String> referenceImages = const [],
  String maskImage = '',
}) {
  final useEdits = referenceImages.isNotEmpty || maskImage.trim().isNotEmpty;
  final multipart = <ProviderMultipartPart>[];
  final body = <String, dynamic>{
    'model': model.modelId,
    'prompt': prompt,
    'n': generationCount < 1 ? 1 : generationCount,
    if (referenceImages.isNotEmpty && !useEdits) 'image_urls': referenceImages,
    ...customParams,
  };
  if (_isOpenAiImageSize(resolution)) body['size'] = resolution;
  if (_isOpenAiImageQuality(quality)) body['quality'] = quality;
  if (_isOpenAiImageModeration(moderation)) body['moderation'] = moderation;
  if (_isOpenAiImageBackground(background)) body['background'] = background;
  if (useEdits) {
    for (var index = 0; index < referenceImages.length; index += 1) {
      multipart.add(
        _multipartImagePart(
          field: 'image',
          value: referenceImages[index],
          fallbackName: 'reference_${index + 1}',
        ),
      );
    }
    if (maskImage.trim().isNotEmpty) {
      multipart.add(
        _multipartImagePart(
          field: 'mask',
          value: maskImage.trim(),
          fallbackName: 'mask',
        ),
      );
    }
  }

  return ProviderRequest(
    url: _resolveOpenAiUrl(
      provider,
      useEdits ? '/images/edits' : '/images/generations',
    ),
    method: 'POST',
    headers: useEdits ? _multipartHeaders(provider) : _openAiHeaders(provider),
    body: body,
    multipart: multipart,
  );
}

ProviderRequest _buildGoogleChatRequest({
  required ProviderConfig provider,
  required ModelConfig model,
  required String prompt,
  required String systemPrompt,
  required Map<String, dynamic> customParams,
  List<String> referenceImages = const [],
}) {
  final body = <String, dynamic>{
    'contents': [
      {
        'parts': [
          {'text': prompt},
          ..._googleImageParts(referenceImages),
        ],
      },
    ],
    ...customParams,
  };
  if (systemPrompt.trim().isNotEmpty) {
    body['systemInstruction'] = {
      'parts': [
        {'text': systemPrompt.trim()},
      ],
    };
  }

  return ProviderRequest(
    url: _resolveGoogleUrl(provider, model),
    method: 'POST',
    headers: _jsonHeaders(),
    body: body,
  );
}

ProviderRequest _buildGoogleImageRequest({
  required ProviderConfig provider,
  required ModelConfig model,
  required String prompt,
  required Map<String, dynamic> customParams,
  List<String> referenceImages = const [],
}) {
  return ProviderRequest(
    url: _resolveGoogleUrl(provider, model),
    method: 'POST',
    headers: _jsonHeaders(),
    body: {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            ..._googleImageParts(referenceImages),
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
      },
      ...customParams,
    },
  );
}

/// Converts reference images (data URIs or base64) into Gemini inlineData
/// parts. Plain `http(s)` URLs are skipped (Gemini needs inline bytes).
List<Map<String, dynamic>> _googleImageParts(List<String> referenceImages) {
  final parts = <Map<String, dynamic>>[];
  for (final image in referenceImages) {
    final match = RegExp(
      r'^data:([^;]+);base64,(.*)$',
    ).firstMatch(image.trim());
    if (match != null) {
      parts.add({
        'inlineData': {'mimeType': match.group(1), 'data': match.group(2)},
      });
    } else if (!image.startsWith('http')) {
      parts.add({
        'inlineData': {'mimeType': 'image/png', 'data': image},
      });
    }
  }
  return parts;
}

Map<String, String> _openAiHeaders(ProviderConfig provider) {
  return {
    ..._jsonHeaders(),
    if (provider.apiKey.trim().isNotEmpty)
      'Authorization': 'Bearer ${provider.apiKey.trim()}',
  };
}

Map<String, String> _multipartHeaders(ProviderConfig provider) {
  return {
    'Accept': 'application/json',
    if (provider.apiKey.trim().isNotEmpty)
      'Authorization': 'Bearer ${provider.apiKey.trim()}',
  };
}

ProviderMultipartPart _multipartImagePart({
  required String field,
  required String value,
  required String fallbackName,
}) {
  final trimmed = value.trim();
  final match = RegExp(r'^data:([^;]+);base64,(.+)$', caseSensitive: false)
      .firstMatch(trimmed);
  if (match != null) {
    final contentType = match.group(1) ?? 'image/png';
    final bytes = base64Decode(match.group(2) ?? '');
    return ProviderMultipartPart(
      field: field,
      filename: '$fallbackName${_extensionForMimeType(contentType)}',
      contentType: contentType,
      bytes: bytes,
    );
  }

  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return ProviderMultipartPart(
      field: field,
      filename: '$fallbackName.url',
      contentType: 'text/uri-list',
      bytes: utf8.encode(trimmed),
    );
  }

  final bytes = base64Decode(_stripDataUri(trimmed));
  return ProviderMultipartPart(
    field: field,
    filename: '$fallbackName.png',
    contentType: 'image/png',
    bytes: bytes,
  );
}

String _extensionForMimeType(String contentType) {
  return switch (contentType.toLowerCase()) {
    'image/jpeg' => '.jpg',
    'image/webp' => '.webp',
    'image/gif' => '.gif',
    _ => '.png',
  };
}

String _stripDataUri(String value) {
  final trimmed = value.trim();
  final index = trimmed.indexOf(',');
  if (trimmed.startsWith('data:') && index >= 0) {
    return trimmed.substring(index + 1);
  }
  return trimmed;
}

Map<String, String> _jsonHeaders() {
  return const {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
}

String _resolveOpenAiUrl(ProviderConfig provider, String path) {
  final endpoint = normalizeProviderEndpoint(provider.endpoint);
  if (!provider.autoComplete) return endpoint;
  final base = _normalizeOpenAiBase(endpoint);
  if (base.toLowerCase().endsWith(path)) return base;
  return '$base$path';
}

String _resolveGoogleUrl(ProviderConfig provider, ModelConfig model) {
  final endpoint = normalizeProviderEndpoint(provider.endpoint);
  if (!provider.autoComplete) return endpoint;
  final base = endpoint
      .replaceFirst(
        RegExp(r'/v\d+(beta)?/models/?.*$', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'/+$'), '');
  return '$base/v1beta/models/${Uri.encodeComponent(model.modelId)}:generateContent?key=${Uri.encodeQueryComponent(provider.apiKey)}';
}

String normalizeProviderEndpoint(String endpoint) {
  final trimmed = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) return '';
  return trimmed.contains('://') ? trimmed : 'http://$trimmed';
}

String _normalizeOpenAiBase(String endpoint) {
  final cleaned = endpoint
      .replaceFirst(
        RegExp(
          r'/(chat/completions|images/(generations|edits)|responses)$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(RegExp(r'/+$'), '');
  if (RegExp(r'/v\d+$', caseSensitive: false).hasMatch(cleaned)) return cleaned;
  return '$cleaned/v1';
}

String redactUrlSecrets(String url) {
  return url.replaceAllMapped(
    RegExp(r'([?&](?:key|api_key|apiKey)=)([^&#]+)', caseSensitive: false),
    (match) =>
        '${match.group(1)}${maskSecret(Uri.decodeComponent(match.group(2)!))}',
  );
}

String _redactHeader(MapEntry<String, String> entry) {
  if (entry.key.toLowerCase() == 'authorization') {
    final value = entry.value;
    final bearer = RegExp(
      r'^Bearer\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (bearer != null) return 'Bearer ${maskSecret(bearer.group(1)!)}';
    return maskSecret(value);
  }
  return entry.value;
}

bool _isOpenAiImageSize(String value) {
  return RegExp(r'^\d{2,5}x\d{2,5}$').hasMatch(value.trim().toLowerCase());
}

bool _isOpenAiImageQuality(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'low' || normalized == 'medium' || normalized == 'high';
}

bool _isOpenAiImageModeration(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'auto' || normalized == 'low';
}

bool _isOpenAiImageBackground(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'auto' ||
      normalized == 'transparent' ||
      normalized == 'opaque';
}
