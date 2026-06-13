import 'dart:convert';
import 'dart:typed_data';

import '../../core/models/flow_node.dart';
import '../../core/network/provider_client.dart';
import '../logs/log_signals.dart';
import '../media/media_asset.dart';
import '../settings/provider_settings.dart';
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
      case 'TextChat':
        return _executeTextChat(node, context);
      case 'ImageGenerate':
        return _executeImageGenerate(node, context);
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

    final request = ProviderRequestBuilder.buildImageRequest(
      provider: provider,
      model: model,
      prompt: prompt,
      size: _stringFrom(node.data['size']) ?? '',
      quality: _stringFrom(node.data['quality']) ?? '',
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

  Future<NodeExecutionResult> _executeImageSave(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final input = context.inputs['image'];
    final payload = await _persistImagePayload(input, fileNameSeed: node.id);
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
      ModelProtocol.openai => _openAiChatText(decoded) ?? '',
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
  }) async {
    if (input is Map) {
      final map = Map<String, dynamic>.from(input);
      final kind = _stringFrom(map['kind']);
      if (kind == 'asset') return map;
      if (kind == 'url') return map;
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
