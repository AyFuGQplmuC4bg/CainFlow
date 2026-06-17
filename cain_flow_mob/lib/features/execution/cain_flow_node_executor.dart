import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/models/flow_node.dart';
import '../../core/network/provider_client.dart';
import '../background/background_job_repository.dart';
import '../camera/camera_prompt.dart';
import '../logs/log_signals.dart';
import '../media/image_ops.dart';
import '../media/media_asset.dart';
import '../settings/provider_settings.dart';
import 'async_image_protocol.dart';
import 'execution_services.dart';
import 'node_executor.dart';
import 'provider_request_builder.dart';
import 'streaming_parser.dart';

/// Concrete executor for CainFlow node types. Backed by [ExecutionServices]
/// so the [WorkflowRunner] can stay orchestration-only.
class CainFlowNodeExecutor implements NodeExecutor {
  CainFlowNodeExecutor({required this.services});

  final ExecutionServices services;

  /// Per-node loop iteration counters for [ControlLoop], keyed by node id.
  final Map<String, int> _loopCounters = {};

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
      case 'ImageCrop':
        return _executeImageCrop(node, context);
      case 'ImageAnnotate':
        return _executeImageAnnotate(node, context);
      case 'CameraControl':
        return _executeCameraControl(node, context);
      case 'ImageSave':
        return _executeImageSave(node, context);
      case 'ControlCondition':
        return _executeControlCondition(node, context);
      case 'ControlLoop':
        return _executeControlLoop(node, context);
      default:
        throw UnsupportedError('Unsupported node type: ${node.type}');
    }
  }

  /// Routes the input value to the `true` or `false` output port based on a
  /// comparison. Only the chosen port carries a value, so only that branch's
  /// downstream nodes run under the iterative engine.
  NodeExecutionResult _executeControlCondition(
    FlowNode node,
    NodeExecutionContext context,
  ) {
    final value =
        _stringFrom(context.inputs['value']) ??
        _stringFrom(node.data['value']) ??
        '';
    final compareTo = _stringFrom(node.data['compareTo']) ?? '';
    final op = _stringFrom(node.data['operator']) ?? '==';
    final matched = switch (op) {
      '!=' => value != compareTo,
      'contains' => value.contains(compareTo),
      'notEmpty' => value.trim().isNotEmpty,
      _ => value == compareTo,
    };
    return NodeExecutionResult(
      nodeId: node.id,
      outputs: matched ? {'true': value} : {'false': value},
      message: matched ? 'true' : 'false',
    );
  }

  /// Emits the input on the `loop` port for the first N executions, then on
  /// `done`. Iteration count is tracked per node id across re-executions.
  NodeExecutionResult _executeControlLoop(
    FlowNode node,
    NodeExecutionContext context,
  ) {
    final limit = _intFrom(node.data['count']) ?? 1;
    final iteration = _loopCounters[node.id] ?? 0;
    final value =
        _stringFrom(context.inputs['value']) ??
        _stringFrom(node.data['value']) ??
        '';
    if (iteration < limit) {
      _loopCounters[node.id] = iteration + 1;
      return NodeExecutionResult(
        nodeId: node.id,
        outputs: {'loop': value},
        message: 'iteration ${iteration + 1}/$limit',
      );
    }
    _loopCounters.remove(node.id);
    return NodeExecutionResult(
      nodeId: node.id,
      outputs: {'done': value},
      message: 'done',
    );
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
    final input =
        _stringFrom(context.inputs['text']) ??
        _stringFrom(node.data['text']) ??
        '';
    final pieces = separator.isEmpty ? [input] : input.split(separator);
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
    final payload = await _saveImageBytes(
      out,
      fileNameSeed: '${node.id}-resize',
    );
    return NodeExecutionResult(nodeId: node.id, outputs: {'image': payload});
  }

  /// Merges connected image inputs (image_1..n) into one image.
  Future<NodeExecutionResult> _executeImageMerge(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final keys =
        context.inputs.keys.where((k) => k.startsWith('image')).toList()
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
    final payload = await _saveImageBytes(
      out,
      fileNameSeed: '${node.id}-merge',
    );
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
    final payload = await _saveImageBytes(
      out,
      fileNameSeed: '${node.id}-compare',
    );
    return NodeExecutionResult(nodeId: node.id, outputs: {'image': payload});
  }

  /// Crops the input image to the configured rectangle.
  Future<NodeExecutionResult> _executeImageCrop(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final bytes = await _loadImageBytes(context.inputs['image']);
    final out = ImageOps.crop(
      bytes,
      x: _intFrom(node.data['x']) ?? 0,
      y: _intFrom(node.data['y']) ?? 0,
      width: _intFrom(node.data['width']) ?? 256,
      height: _intFrom(node.data['height']) ?? 256,
    );
    final payload = await _saveImageBytes(out, fileNameSeed: '${node.id}-crop');
    return NodeExecutionResult(nodeId: node.id, outputs: {'image': payload});
  }

  /// Draws annotation shapes (from the `shapes` JSON param) onto the image.
  Future<NodeExecutionResult> _executeImageAnnotate(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    final bytes = await _loadImageBytes(context.inputs['image']);
    final raw = node.data['shapes'];
    final shapes = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final s in raw) {
        if (s is Map) shapes.add(Map<String, dynamic>.from(s));
      }
    }
    final out = ImageOps.annotate(bytes, shapes);
    final payload = await _saveImageBytes(
      out,
      fileNameSeed: '${node.id}-annotate',
    );
    return NodeExecutionResult(nodeId: node.id, outputs: {'image': payload});
  }

  /// Builds the camera-instruction prompt from the node's 5D viewpoint params
  /// (pitch/yaw/distance/fov/roll), ported from the web camera-control node.
  NodeExecutionResult _executeCameraControl(
    FlowNode node,
    NodeExecutionContext context,
  ) {
    final state = CameraState.fromData(node.data);
    return NodeExecutionResult(
      nodeId: node.id,
      outputs: {'text': CameraPrompt.generate(state)},
    );
  }

  /// Resolves an image payload (`{kind: asset|url|b64}`) into raw bytes.
  /// Asset payloads read the local file; url payloads are downloaded.
  Future<Uint8List> _loadImageBytes(Object? input) async {
    if (input is Map) {
      final map = Map<String, dynamic>.from(input);
      final kind = _stringFrom(map['kind']);
      if (kind == 'images') {
        final items = map['items'];
        if (items is List && items.isNotEmpty) {
          return _loadImageBytes(items.last);
        }
      }
      if (kind == 'asset') {
        final relativePath = _stringFrom(map['relativePath']) ?? '';
        final root = await services.mediaRepository.mediaRoot();
        final file = File('${root.path}${Platform.pathSeparator}$relativePath');
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

  /// Collects image inputs into provider-ready references. `mask` is separated
  /// from normal reference images so providers can send it as a dedicated
  /// request field.
  Future<_CollectedImageInputs> _collectImageInputs(
    Map<String, dynamic> inputs,
  ) async {
    final keys =
        inputs.keys.where((k) => k.startsWith('image') || k == 'mask').toList()
          ..sort();
    final refs = <String>[];
    String? maskImage;
    for (final key in keys) {
      final ref = await _imageInputToReference(inputs[key]);
      if (ref == null) continue;
      if (key == 'mask') {
        maskImage = ref;
      } else {
        refs.add(ref);
      }
    }
    return _CollectedImageInputs(referenceImages: refs, maskImage: maskImage);
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
    final provider = _resolveProvider(
      node: node,
      settings: settings,
      model: model,
    );
    final prompt = _resolvePrompt(node: node, inputs: context.inputs);

    final streaming = _stringFrom(node.data['stream']) == 'true';
    final customParams = Map<String, dynamic>.from(
      _customParamsFrom(node.data['customParams']),
    );
    if (streaming) customParams['stream'] = true;

    final request = ProviderRequestBuilder.buildChatRequest(
      provider: provider,
      model: model,
      prompt: prompt,
      systemPrompt: _stringFrom(node.data['systemPrompt']) ?? '',
      customParams: customParams,
      referenceImages: (await _collectImageInputs(
        context.inputs,
      )).referenceImages,
    );

    final response = await _send(
      node: node,
      request: request,
      scope: 'TextChat',
      providerName: provider.name,
      modelName: model.modelId,
      options: _requestOptions(settings.runtime.requestTimeoutSeconds),
    );
    // Streaming responses arrive as SSE; accumulate deltas. The buffered
    // (non-stream) body is parsed normally. We detect SSE by the data: prefix.
    final text = streaming || response.body.contains('data:')
        ? _parseStreamOrBuffered(model.protocol, response.body)
        : _parseChatText(model.protocol, response.body);
    return NodeExecutionResult(nodeId: node.id, outputs: {'text': text});
  }

  /// Parses an SSE-accumulated body, falling back to the buffered parser when
  /// no streaming deltas are present.
  String _parseStreamOrBuffered(ModelProtocol protocol, String body) {
    final streamed = StreamingParser.accumulate(body, protocol);
    if (streamed.isNotEmpty) return streamed;
    return _parseChatText(protocol, body);
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
    final provider = _resolveProvider(
      node: node,
      settings: settings,
      model: model,
    );
    final prompt = _resolveImagePrompt(node: node, inputs: context.inputs);

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

    final imageInputs = await _collectImageInputs(context.inputs);
    final request = ProviderRequestBuilder.buildImageRequest(
      provider: provider,
      model: model,
      prompt: prompt,
      resolution: _stringFrom(node.data['resolution']) ?? '',
      aspect: _stringFrom(node.data['aspect']) ?? '',
      quality: _stringFrom(node.data['quality']) ?? '',
      moderation: _stringFrom(node.data['moderation']) ?? '',
      background: _stringFrom(node.data['background']) ?? '',
      search: _stringFrom(node.data['search']) == 'true',
      generationCount: _intFrom(node.data['generationCount']) ?? 1,
      customParams: _customParamsFrom(node.data['customParams']),
      referenceImages: imageInputs.referenceImages,
      maskImage: imageInputs.maskImage ?? '',
    );

    final response = await _send(
      node: node,
      request: request,
      scope: 'ImageGenerate',
      providerName: provider.name,
      modelName: model.modelId,
      options: _requestOptions(settings.runtime.requestTimeoutSeconds),
    );
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
    final requestOptions = _requestOptions(
      settings.runtime.requestTimeoutSeconds,
    );
    final restoredTask = services.loadAsyncTaskForNode(node.id);
    final imageInputs = await _collectImageInputs(context.inputs);
    final interval = Duration(
      seconds: settings.runtime.asyncPollIntervalSeconds.clamp(1, 60),
    );
    final timeout = Duration(
      seconds: settings.runtime.asyncTimeoutSeconds.clamp(5, 3600),
    );
    final deadline =
        _parseDateTime(restoredTask?.deadlineAt) ?? DateTime.now().add(timeout);
    var asyncTask =
        restoredTask ??
        await _submitAsyncImageTask(
          node: node,
          provider: provider,
          model: model,
          prompt: prompt,
          imageInputs: imageInputs,
          interval: interval,
          deadline: deadline,
          requestOptions: requestOptions,
        );

    var attempt = asyncTask.pollAttempts;
    while (true) {
      if (context.isCanceled()) {
        asyncTask = asyncTask.copyWith(
          state: 'canceled',
          lastError: 'Async image task canceled',
        );
        _saveAsyncTask(node: node, task: asyncTask);
        throw StateError('Async image task canceled');
      }
      if (DateTime.now().isAfter(deadline)) {
        asyncTask = asyncTask.copyWith(
          state: 'timed_out',
          deadlineAt: deadline.toUtc().toIso8601String(),
          lastError: 'Async image task timed out: ${asyncTask.taskId}',
        );
        _saveAsyncTask(node: node, task: asyncTask);
        throw StateError('Async image task timed out: ${asyncTask.taskId}');
      }
      final scheduledPoll =
          _parseDateTime(asyncTask.nextPollAt) ?? DateTime.now().add(interval);
      final wait = scheduledPoll.difference(DateTime.now());
      if (!wait.isNegative && wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
      if (context.isCanceled()) {
        asyncTask = asyncTask.copyWith(
          state: 'canceled',
          lastError: 'Async image task canceled',
        );
        _saveAsyncTask(node: node, task: asyncTask);
        throw StateError('Async image task canceled');
      }

      attempt += 1;
      asyncTask = asyncTask.copyWith(
        state: 'polling',
        pollAttempts: attempt,
        deadlineAt: deadline.toUtc().toIso8601String(),
        nextPollAt: DateTime.now().add(interval).toUtc().toIso8601String(),
        lastError: '',
      );
      _saveAsyncTask(node: node, task: asyncTask);
      services.executionSignals?.setPollProgress(node.id, '轮询 $attempt');
      final taskId = asyncTask.taskId;
      final poll = AsyncImageProtocol.buildPollRequest(
        provider: provider,
        taskId: taskId,
      );
      final pollResponse = await services.providerClient.send(
        poll,
        options: requestOptions,
      );
      if (!pollResponse.isSuccess) {
        // Transient poll failure: log and keep trying until the deadline.
        services.logs.add(
          LogLevel.warning,
          'Async poll #$attempt failed (${pollResponse.statusCode}), retrying',
          scope: 'ImageGenerate(async)',
        );
        asyncTask = asyncTask.copyWith(
          state: 'poll_error',
          lastError: 'Async poll failed with status ${pollResponse.statusCode}',
        );
        _saveAsyncTask(node: node, task: asyncTask);
        continue;
      }
      final pollJson = _tryDecode(pollResponse.body);
      if (pollJson == null) {
        asyncTask = asyncTask.copyWith(
          state: 'poll_error',
          lastError: 'Async poll response was not valid JSON',
        );
        _saveAsyncTask(node: node, task: asyncTask);
        continue;
      }

      final status = AsyncImageProtocol.extractStatus(pollJson);
      services.logs.add(
        LogLevel.info,
        'Async poll #$attempt: ${status.name}',
        scope: 'ImageGenerate(async)',
      );
      if (status == AsyncImageStatus.failed) {
        asyncTask = asyncTask.copyWith(
          state: 'failed',
          lastError: 'Async image task failed: ${asyncTask.taskId}',
        );
        _saveAsyncTask(node: node, task: asyncTask);
        throw StateError('Async image task failed: ${asyncTask.taskId}');
      }
      if (status == AsyncImageStatus.completed) {
        final url = AsyncImageProtocol.extractResultUrl(pollJson);
        if (url.isEmpty) {
          throw StateError('Async image completed without a result URL');
        }
        _saveAsyncTask(
          node: node,
          task: asyncTask.copyWith(state: 'completed', lastError: ''),
        );
        return NodeExecutionResult(
          nodeId: node.id,
          outputs: {
            'image': {'kind': 'url', 'url': url},
          },
        );
      }
      asyncTask = asyncTask.copyWith(
        state: status.name,
        deadlineAt: deadline.toUtc().toIso8601String(),
        nextPollAt: DateTime.now().add(interval).toUtc().toIso8601String(),
        lastError: '',
      );
      _saveAsyncTask(node: node, task: asyncTask);
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
    String providerName = '',
    String modelName = '',
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    services.logs.add(
      LogLevel.info,
      '$scope request started: ${request.redactedUrl}',
      scope: scope,
    );
    try {
      final response = await services.providerClient.send(
        request,
        options: options,
      );
      if (!response.isSuccess) {
        final error = response.toError(request);
        services.logs.add(
          LogLevel.error,
          '$scope failed (${error.statusCode} ${error.category.name}): ${error.safeUrl}',
          scope: scope,
        );
        services.statistics?.record(
          provider: providerName,
          model: modelName,
          success: false,
        );
        throw ProviderTransportException(error);
      }
      services.logs.add(LogLevel.info, '$scope succeeded', scope: scope);
      services.statistics?.record(provider: providerName, model: modelName);
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

  Future<BackgroundAsyncTaskMetadata> _submitAsyncImageTask({
    required FlowNode node,
    required ProviderConfig provider,
    required ModelConfig model,
    required String prompt,
    required _CollectedImageInputs imageInputs,
    required Duration interval,
    required DateTime deadline,
    required ProviderRequestOptions requestOptions,
  }) async {
    final submit = AsyncImageProtocol.buildSubmitRequest(
      provider: provider,
      model: model,
      prompt: prompt,
      size: _stringFrom(node.data['resolution']) ?? '',
      customParams: _customParamsFrom(node.data['customParams']),
      referenceImages: imageInputs.referenceImages,
      maskImage: imageInputs.maskImage,
    );
    final submitResponse = await _send(
      node: node,
      request: submit,
      scope: 'ImageGenerate(async)',
      providerName: provider.name,
      modelName: model.modelId,
      options: requestOptions,
    );
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
    final task = BackgroundAsyncTaskMetadata(
      taskId: taskId,
      provider: provider.id,
      pollUrl: AsyncImageProtocol.buildPollRequest(
        provider: provider,
        taskId: taskId,
      ).url,
      state: 'submitted',
      nodeId: node.id,
      pollAttempts: 0,
      nextPollAt: DateTime.now().add(interval).toUtc().toIso8601String(),
      deadlineAt: deadline.toUtc().toIso8601String(),
      lastError: '',
    );
    _saveAsyncTask(node: node, task: task);
    return task;
  }

  void _saveAsyncTask({
    required FlowNode node,
    required BackgroundAsyncTaskMetadata task,
  }) {
    final jobId = services.activeBackgroundJobId;
    if (jobId.isEmpty) return;
    services.backgroundCoordinator?.saveAsyncTask(jobId, task);
    services.executionSignals?.backgroundJobId.value = jobId;
    services.logs.add(
      LogLevel.info,
      'Async task ${task.taskId} persisted for ${node.id}: ${task.state}',
      scope: 'ImageGenerate(async)',
    );
  }

  ProviderRequestOptions _requestOptions(int requestTimeoutSeconds) {
    final timeout = requestTimeoutSeconds.clamp(1, 3600);
    return ProviderRequestOptions(timeout: Duration(seconds: timeout));
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
    final ids = [?candidateId, ...model.providerIds];
    for (final id in ids) {
      for (final provider in settings.providers) {
        if (provider.id == id) return provider;
      }
    }
    throw StateError('No provider configured for node ${node.id}');
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

  String _resolveImagePrompt({
    required FlowNode node,
    required Map<String, dynamic> inputs,
  }) {
    final prompt = _resolvePrompt(node: node, inputs: inputs).trim();
    final systemPrompt = (_stringFrom(inputs['system_prompt']) ?? '').trim();
    final cameraPrompt = (_stringFrom(inputs['camera_prompt']) ?? '').trim();

    final sections = <String>[
      if (prompt.isNotEmpty) prompt,
      if (systemPrompt.isNotEmpty) 'System instruction:\n$systemPrompt',
      if (cameraPrompt.isNotEmpty)
        'Camera composition instruction:\n$cameraPrompt',
    ];
    return sections.join('\n\n').trim();
  }

  // --- Response parsing ----------------------------------------------------

  String _parseChatText(ModelProtocol protocol, String body) {
    final decoded = _tryDecode(body);
    if (decoded == null) return body;
    return switch (protocol) {
      ModelProtocol.openai ||
      ModelProtocol.newApiImageAsync => _openAiChatText(decoded) ?? '',
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
        final images = <Map<String, dynamic>>[];
        for (var i = 0; i < data.length; i++) {
          final item = data[i];
          if (item is! Map) continue;
          final url = _stringFrom(item['url']);
          if (url != null && url.isNotEmpty) {
            images.add({'kind': 'url', 'url': url});
            continue;
          }
          final b64 = _stringFrom(item['b64_json']);
          if (b64 != null && b64.isNotEmpty) {
            images.add(
              await _saveBase64(b64, fileNameSeed: '${fileNameSeed}_${i + 1}'),
            );
          }
        }
        if (images.length == 1) return images.first;
        if (images.length > 1) {
          return _imageBundle(images);
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
      if (kind == 'images') {
        final items = map['items'];
        if (items is! List || items.isEmpty) {
          throw StateError('No image bundle items available to save');
        }
        final savedItems = <Map<String, dynamic>>[];
        for (var i = 0; i < items.length; i++) {
          savedItems.add(
            await _persistImagePayload(
              items[i],
              fileNameSeed: '${fileNameSeed}_${i + 1}',
              downloadRemote: downloadRemote,
            ),
          );
        }
        return _imageBundle(savedItems);
      }
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
    services.logs.add(
      LogLevel.info,
      'Downloading image: $url',
      scope: 'ImageSave',
    );
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

  Map<String, dynamic> _imageBundle(List<Map<String, dynamic>> images) {
    final preview = Map<String, dynamic>.from(images.last)..remove('kind');
    return {
      ...preview,
      'kind': 'images',
      'items': images,
      'count': images.length,
    };
  }
}

class _InlineImage {
  const _InlineImage(this.data, this.mimeType);
  final String data;
  final String mimeType;
}

class _CollectedImageInputs {
  const _CollectedImageInputs({required this.referenceImages, this.maskImage});

  final List<String> referenceImages;
  final String? maskImage;
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
            _stringFrom(inline['mimeType'] ?? inline['mime_type']) ??
                'image/png',
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

DateTime? _parseDateTime(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim());
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
