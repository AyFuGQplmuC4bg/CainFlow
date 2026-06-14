import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/models/flow_node.dart';
import '../../core/network/provider_client.dart';
import '../logs/log_signals.dart';
import '../media/image_ops.dart';
import '../media/media_asset.dart';
import '../settings/provider_settings.dart';
import 'async_image_protocol.dart';
import 'execution_services.dart';
import 'node_executor.dart';
import 'provider_request_builder.dart';

/// Concrete executor for CainFlow node types. Backed by [ExecutionServices]
/// so the [WorkflowRunner] can stay orchestration-only.
class CainFlowNodeExecutor implements NodeExecutor {
  const CainFlowNodeExecutor({required this.services});

  final ExecutionServices services;

  @override
  Future<NodeExecutionResult> execute(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    switch (node.type) {
      case 'Text':
        return _executeText(node);
      case 'TextMerge':
        return _executeTextMerge(node, context);
      case 'TextSplit':
        return _executeTextSplit(node, context);
      case 'TextChat':
        return _executeTextChat(node, context);
      case 'ImageImport':
        return _executeImageImport(node);
      case 'ImageGenerate':
        return _executeImageGenerate(node, context);
      case 'ImagePreview':
        return _executeImagePreview(node, context);
      case 'ImageResize':
        return _executeImageResize(node, context);
      case 'ImageMerge':
        return _executeImageMerge(node, context);
      case 'ImageCompare':
        return _executeImageCompare(node, context);
      case 'ImageSave':
        return _executeImageSave(node, context);
      default:
        throw UnsupportedError('Unsupported node type: ${node.type}');
    }
  }

  NodeExecutionResult _executeText(FlowNode node) {
    final value =
        _stringFrom(node.data['text']) ?? _stringFrom(node.extra['text']) ?? '';
    return NodeExecutionResult(nodeId: node.id, outputs: {'text': value});
  }

  /// Concatenates connected text inputs (text_1..n) with a separator.
  NodeExecutionResult _executeTextMerge(
    FlowNode node,
    NodeExecutionContext context,
  ) {
    final separator = _unescape(_stringFrom(node.data['separator']) ?? '\n');
    final parts = <String>[];
    for (final entry in context.inputs.entries) {
      if (entry.key.startsWith('text')) {
        final value = _stringFrom(entry.value);
        if (value != null && value.isNotEmpty) parts.add(value);
      }
    }
    return NodeExecutionResult(
      nodeId: node.id,
      outputs: {'text': parts.join(separator)},
    );
  }

  /// Splits the input text by a separator into part_1..3 outputs.
  NodeExecutionResult _executeTextSplit(
    FlowNode node,
    NodeExecutionContext context,
  ) {
    final separator = _unescape(_stringFrom(node.data['separator']) ?? '\n');
    final input = _stringFrom(context.inputs['text']) ??
        _stringFrom(node.data['text']) ??
        '';
    final pieces = separator.isEmpty
        ? [input]
        : input.split(separator);
    final outputs = <String, dynamic>{};
    for (var i = 0; i < 3; i++) {
      outputs['part_${i + 1}'] = i < pieces.length ? pieces[i] : '';
    }
    return NodeExecutionResult(nodeId: node.id, outputs: outputs);
  }

  /// ImageImport resolves the asset chosen in the editor (stored as
  /// `data.assetId`) into a passthrough asset payload for downstream nodes.
  NodeExecutionResult _executeImageImport(FlowNode node) {
    final assetId = _stringFrom(node.data['assetId']);
    if (assetId == null || assetId.isEmpty) {
      throw StateError('ImageImport node ${node.id} has no selected image');
    }
    final asset = services.mediaRepository
        .loadAll()
        .where((a) => a.id == assetId)
        .firstOrNull;
    if (asset == null) {
      throw StateError('Imported image $assetId no longer exists');
    }
    return NodeExecutionResult(
      nodeId: node.id,
      outputs: {'image': _assetPayload(asset)},
    );
  }

  /// ImagePreview passes its input image straight to its output so the canvas
  /// thumbnail can render it; it performs no network or disk work.
  NodeExecutionResult _executeImagePreview(
    FlowNode node,
    NodeExecutionContext context,
  ) {
    final input = context.inputs['image'];
    return NodeExecutionResult(
      nodeId: node.id,
      outputs: input == null ? const {} : {'image': input},
    );
  }

  /// Resizes the input image to the configured box and saves the result.
  Future<NodeExecutionResult> _executeImageResize(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final bytes = await _loadImageBytes(context.inputs['image']);
    final width = _intFrom(node.data['width']) ?? 512;
    final height = _intFrom(node.data['height']) ?? 512;
    final fit = switch (_stringFrom(node.data['fit'])) {
      'cover' => ImageFit.cover,
      'stretch' => ImageFit.stretch,
      _ => ImageFit.contain,
    };
    final out = ImageOps.resize(bytes, width: width, height: height, fit: fit);
    final payload = await _saveImageBytes(out, fileNameSeed: '${node.id}-resize');
    return NodeExecutionResult(nodeId: node.id, outputs: {'image': payload});
  }

  /// Merges connected image inputs (image_1..n) into one image.
  Future<NodeExecutionResult> _executeImageMerge(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final keys = context.inputs.keys.where((k) => k.startsWith('image')).toList()
      ..sort();
    final images = <Uint8List>[];
    for (final key in keys) {
      images.add(await _loadImageBytes(context.inputs[key]));
    }
    if (images.isEmpty) {
      throw StateError('ImageMerge node ${node.id} has no image inputs');
    }
    final layout = switch (_stringFrom(node.data['layout'])) {
      'vertical' => MergeLayout.vertical,
      'grid' => MergeLayout.grid,
      _ => MergeLayout.horizontal,
    };
    final out = ImageOps.merge(images, layout: layout);
    final payload = await _saveImageBytes(out, fileNameSeed: '${node.id}-merge');
    return NodeExecutionResult(nodeId: node.id, outputs: {'image': payload});
  }

  /// Places imageA and imageB side by side.
  Future<NodeExecutionResult> _executeImageCompare(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final a = await _loadImageBytes(context.inputs['imageA']);
    final b = await _loadImageBytes(context.inputs['imageB']);
    final out = ImageOps.compare(a, b);
    final payload = await _saveImageBytes(out, fileNameSeed: '${node.id}-compare');
    return NodeExecutionResult(nodeId: node.id, outputs: {'image': payload});
  }

  /// Resolves an image payload (`{kind: asset|url|b64}`) into raw bytes.
  /// Asset payloads read the local file; url payloads are downloaded.
  Future<Uint8List> _loadImageBytes(Object? input) async {
    if (input is Map) {
      final map = Map<String, dynamic>.from(input);
      final kind = _stringFrom(map['kind']);
      if (kind == 'asset') {
        final relativePath = _stringFrom(map['relativePath']) ?? '';
        final root = await services.mediaRepository.mediaRoot();
        final file = File(
          '${root.path}${Platform.pathSeparator}$relativePath',
        );
        return Uint8List.fromList(await file.readAsBytes());
      }
      final b64 = _stringFrom(map['b64_json']) ?? _stringFrom(map['base64']);
      if (b64 != null && b64.isNotEmpty) {
        return Uint8List.fromList(base64Decode(_stripDataUri(b64)));
      }
    }
    if (input is String && input.isNotEmpty) {
      return Uint8List.fromList(base64Decode(_stripDataUri(input)));
    }
    throw StateError('No decodable image input available');
  }

  Future<Map<String, dynamic>> _saveImageBytes(
    Uint8List bytes, {
    required String fileNameSeed,
  }) async {
    final asset = await services.mediaRepository.saveBytes(
      workflowId: services.workflowId,
      fileName: '$fileNameSeed.png',
      mimeType: 'image/png',
      bytes: bytes,
    );
    return _assetPayload(asset);
  }

  /// Collects image inputs into provider-ready reference strings: local assets
  /// become `data:` URIs (base64); remote URLs pass through unchanged. Scans
  /// any input port whose name suggests an image (`image*`, `mask`).
  Future<List<String>> _collectReferenceImages(
    Map<String, dynamic> inputs,
  ) async {
    final keys = inputs.keys
        .where((k) => k.startsWith('image') || k == 'mask')
        .toList()
      ..sort();
    final refs = <String>[];
    for (final key in keys) {
      final ref = await _imageInputToReference(inputs[key]);
      if (ref != null) refs.add(ref);
    }
    return refs;
  }

  Future<String?> _imageInputToReference(Object? input) async {
    if (input is Map) {
      final map = Map<String, dynamic>.from(input);
      final kind = _stringFrom(map['kind']);
      if (kind == 'url') {
        final url = _stringFrom(map['url']);
        return (url != null && url.isNotEmpty) ? url : null;
      }
      if (kind == 'asset') {
        final bytes = await _loadImageBytes(map);
        return 'data:${_stringFrom(map['mimeType']) ?? 'image/png'};base64,'
            '${base64Encode(bytes)}';
      }
      final b64 = _stringFrom(map['b64_json']) ?? _stringFrom(map['base64']);
      if (b64 != null && b64.isNotEmpty) {
        return 'data:image/png;base64,${_stripDataUri(b64)}';
      }
    }
    return null;
  }

  Future<NodeExecutionResult> _executeTextChat(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final settings = services.settingsRepository.load();
    final model = _resolveModel(
      node: node,
      settings: settings,
      activeModelId: settings.runtime.activeChatModelId,
    );
    final provider = _resolveProvider(node: node, settings: settings, model: model);
    final prompt = _resolvePrompt(node: node, inputs: context.inputs);

    final request = ProviderRequestBuilder.buildChatRequest(
      provider: provider,
      model: model,
      prompt: prompt,
      systemPrompt: _stringFrom(node.data['systemPrompt']) ?? '',
      customParams: _customParamsFrom(node.data['customParams']),
      referenceImages: await _collectReferenceImages(context.inputs),
    );

    final response = await _send(node: node, request: request, scope: 'TextChat');
    final text = _parseChatText(model.protocol, response.body);
    return NodeExecutionResult(nodeId: node.id, outputs: {'text': text});
  }

  Future<NodeExecutionResult> _executeImageGenerate(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final settings = services.settingsRepository.load();
    final model = _resolveModel(
      node: node,
      settings: settings,
      activeModelId: settings.runtime.activeImageModelId,
    );
    final provider = _resolveProvider(node: node, settings: settings, model: model);
    final prompt = _resolvePrompt(node: node, inputs: context.inputs);

    if (model.protocol == ModelProtocol.newApiImageAsync) {
      return _executeAsyncImageGenerate(
        node: node,
        context: context,
        settings: settings,
        model: model,
        provider: provider,
        prompt: prompt,
      );
    }

    final request = ProviderRequestBuilder.buildImageRequest(
      provider: provider,
      model: model,
      prompt: prompt,
      size: _stringFrom(node.data['size']) ?? '',
      quality: _stringFrom(node.data['quality']) ?? '',
      customParams: _customParamsFrom(node.data['customParams']),
      referenceImages: await _collectReferenceImages(context.inputs),
    );

    final response =
        await _send(node: node, request: request, scope: 'ImageGenerate');
    final image = await _parseImage(
      protocol: model.protocol,
      body: response.body,
      fileNameSeed: node.id,
    );
    return NodeExecutionResult(nodeId: node.id, outputs: {'image': image});
  }

  /// Async image flow: submit a task, poll until completed/failed/timeout
  /// (honoring cancellation), then resolve the result URL into an output.
  Future<NodeExecutionResult> _executeAsyncImageGenerate({
    required FlowNode node,
    required NodeExecutionContext context,
    required ProviderSettings settings,
    required ModelConfig model,
    required ProviderConfig provider,
    required String prompt,
  }) async {
    final submit = AsyncImageProtocol.buildSubmitRequest(
      provider: provider,
      model: model,
      prompt: prompt,
      size: _stringFrom(node.data['size']) ?? '',
      customParams: _customParamsFrom(node.data['customParams']),
    );
    final submitResponse =
        await _send(node: node, request: submit, scope: 'ImageGenerate(async)');
    final submitJson = _tryDecode(submitResponse.body);
    if (submitJson == null) {
      throw StateError('Async submit response was not valid JSON');
    }
    final taskId = AsyncImageProtocol.extractTaskId(submitJson);
    if (taskId.isEmpty) {
      throw StateError('Async submit did not return a task id');
    }
    services.logs.add(
      LogLevel.info,
      'Async image task submitted: $taskId',
      scope: 'ImageGenerate(async)',
    );

    final interval =
        Duration(seconds: settings.runtime.asyncPollIntervalSeconds.clamp(1, 60));
    final deadline = DateTime.now().add(
      Duration(seconds: settings.runtime.asyncTimeoutSeconds.clamp(5, 3600)),
    );

    var attempt = 0;
    while (true) {
      if (context.isCanceled()) {
        throw StateError('Async image task canceled');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Async image task timed out after $taskId');
      }
      await Future<void>.delayed(interval);
      if (context.isCanceled()) {
        throw StateError('Async image task canceled');
      }

      attempt += 1;
      final poll = AsyncImageProtocol.buildPollRequest(
        provider: provider,
        taskId: taskId,
      );
      final pollResponse = await services.providerClient.send(poll);
      if (!pollResponse.isSuccess) {
        // Transient poll failure: log and keep trying until the deadline.
        services.logs.add(
          LogLevel.warning,
          'Async poll #$attempt failed (${pollResponse.statusCode}), retrying',
          scope: 'ImageGenerate(async)',
        );
        continue;
      }
      final pollJson = _tryDecode(pollResponse.body);
      if (pollJson == null) continue;

      final status = AsyncImageProtocol.extractStatus(pollJson);
      services.logs.add(
        LogLevel.info,
        'Async poll #$attempt: ${status.name}',
        scope: 'ImageGenerate(async)',
      );
      if (status == AsyncImageStatus.failed) {
        throw StateError('Async image task failed: $taskId');
      }
      if (status == AsyncImageStatus.completed) {
        final url = AsyncImageProtocol.extractResultUrl(pollJson);
        if (url.isEmpty) {
          throw StateError('Async image completed without a result URL');
        }
        return NodeExecutionResult(
          nodeId: node.id,
          outputs: {
            'image': {'kind': 'url', 'url': url},
          },
        );
      }
    }
  }

  Future<NodeExecutionResult> _executeImageSave(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final input = context.inputs['image'];
    final downloadRemote = _stringFrom(node.data['downloadRemote']) == 'true';
    final payload = await _persistImagePayload(
      input,
      fileNameSeed: node.id,
      downloadRemote: downloadRemote,
    );
    return NodeExecutionResult(nodeId: node.id, outputs: {'image': payload});
  }

  // --- Sending -------------------------------------------------------------

  Future<ProviderResponse> _send({
    required FlowNode node,
    required ProviderRequest request,
    required String scope,
  }) async {
    services.logs.add(
      LogLevel.info,
      '$scope request started: ${request.redactedUrl}',
      scope: scope,
    );
    try {
      final response = await services.providerClient.send(request);
      if (!response.isSuccess) {
        final error = response.toError(request);
        services.logs.add(
          LogLevel.error,
          '$scope failed (${error.statusCode} ${error.category.name}): ${error.safeUrl}',
          scope: scope,
        );
        throw ProviderTransportException(error);
      }
      services.logs.add(LogLevel.info, '$scope succeeded', scope: scope);
      return response;
    } on ProviderTransportException catch (e) {
      services.logs.add(
        LogLevel.error,
        '$scope failed (${e.error.category.name}): ${e.error.message}',
        scope: scope,
      );
      rethrow;
    }
  }

  // --- Resolution helpers --------------------------------------------------

  ModelConfig _resolveModel({
    required FlowNode node,
    required ProviderSettings settings,
    required String activeModelId,
  }) {
    final candidateId =
        _stringFrom(node.data['apiConfigId']) ??
        _stringFrom(node.extra['apiConfigId']) ??
        (activeModelId.isNotEmpty ? activeModelId : null);
    if (candidateId != null) {
      for (final model in settings.models) {
        if (model.id == candidateId) return model;
      }
    }
    throw StateError('No model configured for node ${node.id}');
  }

  ProviderConfig _resolveProvider({
    required FlowNode node,
    required ProviderSettings settings,
    required ModelConfig model,
  }) {
    final candidateId =
        _stringFrom(node.data['providerId']) ??
        _stringFrom(node.extra['providerId']);
    final ids = [
      ?candidateId,
      ...model.providerIds,
    ];
    for (final id in ids) {
      for (final provider in settings.providers) {
        if (provider.id == id) return provider;
      }
    }    throw StateError('No provider configured for node ${node.id}');
  }

  String _resolvePrompt({
    required FlowNode node,
    required Map<String, dynamic> inputs,
  }) {
    return _stringFrom(inputs['prompt']) ??
        _stringFrom(node.data['prompt']) ??
        _stringFrom(node.extra['prompt']) ??
        '';
  }

  // --- Response parsing ----------------------------------------------------

  String _parseChatText(ModelProtocol protocol, String body) {
    final decoded = _tryDecode(body);
    if (decoded == null) return body;
    return switch (protocol) {
      ModelProtocol.openai || ModelProtocol.newApiImageAsync =>
        _openAiChatText(decoded) ?? '',
      ModelProtocol.google => _googleText(decoded) ?? '',
    };
  }

  Future<Map<String, dynamic>> _parseImage({
    required ModelProtocol protocol,
    required String body,
    required String fileNameSeed,
  }) async {
    final decoded = _tryDecode(body);
    if (decoded == null) {
      throw StateError('Image response was not valid JSON');
    }

    // OpenAI image: { data: [ { url } | { b64_json } ] }
    if (protocol == ModelProtocol.openai) {
      final data = decoded['data'];
      if (data is List && data.isNotEmpty) {
        final first = data.first;
        if (first is Map) {
          final url = _stringFrom(first['url']);
          if (url != null && url.isNotEmpty) {
            return {'kind': 'url', 'url': url};
          }
          final b64 = _stringFrom(first['b64_json']);
          if (b64 != null && b64.isNotEmpty) {
            return _saveBase64(b64, fileNameSeed: fileNameSeed);
          }
        }
      }
    }

    // Gemini image: candidates[0].content.parts[].inlineData.data
    final inline = _googleInlineImage(decoded);
    if (inline != null) {
      return _saveBase64(
        inline.data,
        fileNameSeed: fileNameSeed,
        mimeType: inline.mimeType,
      );
    }

    throw StateError('No image payload found in provider response');
  }

  // --- Image persistence ---------------------------------------------------

  Future<Map<String, dynamic>> _persistImagePayload(
    Object? input, {
    required String fileNameSeed,
    bool downloadRemote = false,
  }) async {
    if (input is Map) {
      final map = Map<String, dynamic>.from(input);
      final kind = _stringFrom(map['kind']);
      if (kind == 'asset') return map;
      if (kind == 'url') {
        final url = _stringFrom(map['url']) ?? '';
        if (downloadRemote && url.isNotEmpty) {
          return _downloadUrl(url, fileNameSeed: fileNameSeed);
        }
        return map;
      }
      final b64 = _stringFrom(map['b64_json']) ?? _stringFrom(map['base64']);
      if (b64 != null && b64.isNotEmpty) {
        return _saveBase64(
          b64,
          fileNameSeed: fileNameSeed,
          mimeType: _stringFrom(map['mimeType']) ?? 'image/png',
        );
      }
    }
    if (input is String && input.isNotEmpty) {
      // Bare base64 string.
      return _saveBase64(input, fileNameSeed: fileNameSeed);
    }
    throw StateError('No image input available to save');
  }

  /// Downloads a remote image URL and stores it as a local asset.
  Future<Map<String, dynamic>> _downloadUrl(
    String url, {
    required String fileNameSeed,
  }) async {
    services.logs.add(LogLevel.info, 'Downloading image: $url', scope: 'ImageSave');
    final media = await services.downloader.download(url);
    final asset = await services.mediaRepository.saveBytes(
      workflowId: services.workflowId,
      fileName: '$fileNameSeed.${_extensionFor(media.mimeType)}',
      mimeType: media.mimeType,
      bytes: media.bytes,
    );
    return _assetPayload(asset);
  }

  Future<Map<String, dynamic>> _saveBase64(
    String b64, {
    required String fileNameSeed,
    String mimeType = 'image/png',
  }) async {
    final bytes = Uint8List.fromList(base64Decode(_stripDataUri(b64)));
    final asset = await services.mediaRepository.saveBytes(
      workflowId: services.workflowId,
      fileName: '$fileNameSeed.${_extensionFor(mimeType)}',
      mimeType: mimeType,
      bytes: bytes,
    );
    return _assetPayload(asset);
  }

  Map<String, dynamic> _assetPayload(MediaAsset asset) {
    return {
      'kind': 'asset',
      'assetId': asset.id,
      'relativePath': asset.relativePath,
      'thumbnailRelativePath': asset.thumbnailRelativePath,
      'mimeType': asset.mimeType,
      'byteLength': asset.byteLength,
    };
  }
}

class _InlineImage {
  const _InlineImage(this.data, this.mimeType);
  final String data;
  final String mimeType;
}

Map<String, dynamic>? _tryDecode(String body) {
  try {
    final decoded = jsonDecode(body);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

String? _openAiChatText(Map<String, dynamic> json) {
  final choices = json['choices'];
  if (choices is List && choices.isNotEmpty) {
    final message = (choices.first as Map?)?['message'];
    if (message is Map) return _stringFrom(message['content']);
  }
  return null;
}

String? _googleText(Map<String, dynamic> json) {
  final parts = _googleParts(json);
  if (parts == null) return null;
  final buffer = StringBuffer();
  for (final part in parts) {
    if (part is Map) {
      final text = _stringFrom(part['text']);
      if (text != null) buffer.write(text);
    }
  }
  final result = buffer.toString();
  return result.isEmpty ? null : result;
}

_InlineImage? _googleInlineImage(Map<String, dynamic> json) {
  final parts = _googleParts(json);
  if (parts == null) return null;
  for (final part in parts) {
    if (part is Map) {
      final inline = part['inlineData'] ?? part['inline_data'];
      if (inline is Map) {
        final data = _stringFrom(inline['data']);
        if (data != null && data.isNotEmpty) {
          return _InlineImage(
            data,
            _stringFrom(inline['mimeType'] ?? inline['mime_type']) ?? 'image/png',
          );
        }
      }
    }
  }
  return null;
}

List<dynamic>? _googleParts(Map<String, dynamic> json) {
  final candidates = json['candidates'];
  if (candidates is List && candidates.isNotEmpty) {
    final content = (candidates.first as Map?)?['content'];
    if (content is Map) {
      final parts = content['parts'];
      if (parts is List) return parts;
    }
  }
  return null;
}

String _stripDataUri(String value) {
  final match = RegExp(r'^data:[^;]+;base64,(.*)$').firstMatch(value.trim());
  return match != null ? match.group(1)! : value.trim();
}

String _extensionFor(String mimeType) {
  return switch (mimeType.toLowerCase()) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'png',
  };
}

String? _stringFrom(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// Converts literal escape sequences typed in a text field (`\n`, `\t`) into
/// their control characters so separators behave as expected.
String _unescape(String value) {
  return value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\r', '\r');
}

int? _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Normalizes a node's `customParams` entry into a request param map.
///
/// Accepts a `Map` (preferred) and coerces string-typed scalars produced by
/// the editor form (`"7"`, `"true"`) into `num`/`bool` so providers receive
/// properly typed JSON. Non-map values yield an empty map.
Map<String, dynamic> _customParamsFrom(Object? value) {
  if (value is! Map) return const {};
  final result = <String, dynamic>{};
  value.forEach((key, raw) {
    final name = key?.toString() ?? '';
    if (name.isEmpty) return;
    result[name] = _coerceScalar(raw);
  });
  return result;
}

Object? _coerceScalar(Object? raw) {
  if (raw is! String) return raw;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return raw;
  if (trimmed == 'true') return true;
  if (trimmed == 'false') return false;
  final asInt = int.tryParse(trimmed);
  if (asInt != null) return asInt;
  final asDouble = double.tryParse(trimmed);
  if (asDouble != null) return asDouble;
  return raw;
}
