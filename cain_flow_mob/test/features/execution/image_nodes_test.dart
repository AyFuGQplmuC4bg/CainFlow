import 'dart:io';
import 'dart:typed_data';

import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/execution/cain_flow_node_executor.dart';
import 'package:cain_flow_mob/features/execution/execution_services.dart';
import 'package:cain_flow_mob/features/execution/node_executor.dart';
import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:cain_flow_mob/features/logs/log_signals.dart';
import 'package:cain_flow_mob/features/media/media_repository.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory root;
  late MediaRepository media;
  late CainFlowNodeExecutor executor;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cainflow_imgnodes');
    final store = _MemStore();
    media = MediaRepository(store: store, mediaRoot: root);
    executor = CainFlowNodeExecutor(
      services: ExecutionServices(
        settingsRepository: ProviderSettingsRepository(store: store),
        providerClient: _NoopClient(),
        mediaRepository: media,
        logs: LogSignals(),
        workflowId: 'wf',
      ),
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  NodeExecutionContext ctx(Map<String, dynamic> inputs) {
    return NodeExecutionContext(
      inputs: inputs,
      previousResults: const {},
      isCanceled: () => false,
    );
  }

  Future<Map<String, dynamic>> assetPayload(int w, int h) async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: w, height: h)..clear(img.ColorRgb8(10, 20, 30))),
    );
    final asset = await media.saveBytes(
      workflowId: 'wf',
      fileName: 'in.png',
      mimeType: 'image/png',
      bytes: bytes,
    );
    return {
      'kind': 'asset',
      'assetId': asset.id,
      'relativePath': asset.relativePath,
      'mimeType': 'image/png',
    };
  }

  Future<img.Image> decodeOutput(Map<String, dynamic> payload) async {
    final file = File(
      '${root.path}${Platform.pathSeparator}${payload['relativePath']}',
    );
    return img.decodePng(file.readAsBytesSync())!;
  }

  test('ImageResize scales to the target box (contain)', () async {
    final input = await assetPayload(40, 20);
    final result = await executor.execute(
      const FlowNode(
        id: 'r',
        type: 'ImageResize',
        x: 0,
        y: 0,
        data: {'width': 20, 'height': 20, 'fit': 'contain'},
      ),
      ctx({'image': input}),
    );
    final out = await decodeOutput(result.outputs['image'] as Map<String, dynamic>);
    expect(out.width, 20);
    expect(out.height, 10);
  });

  test('ImageMerge combines inputs horizontally', () async {
    final a = await assetPayload(30, 30);
    final b = await assetPayload(30, 30);
    final result = await executor.execute(
      const FlowNode(
        id: 'm',
        type: 'ImageMerge',
        x: 0,
        y: 0,
        data: {'layout': 'horizontal'},
      ),
      ctx({'image_1': a, 'image_2': b}),
    );
    final out = await decodeOutput(result.outputs['image'] as Map<String, dynamic>);
    expect(out.width > out.height, isTrue);
  });

  test('ImageCompare places two images side by side', () async {
    final a = await assetPayload(20, 20);
    final b = await assetPayload(20, 20);
    final result = await executor.execute(
      const FlowNode(id: 'c', type: 'ImageCompare', x: 0, y: 0),
      ctx({'imageA': a, 'imageB': b}),
    );
    final out = await decodeOutput(result.outputs['image'] as Map<String, dynamic>);
    expect(out.width > out.height, isTrue);
  });

  test('ImageCrop returns the requested region', () async {
    final input = await assetPayload(100, 80);
    final result = await executor.execute(
      const FlowNode(
        id: 'crop',
        type: 'ImageCrop',
        x: 0,
        y: 0,
        data: {'x': 10, 'y': 10, 'width': 40, 'height': 30},
      ),
      ctx({'image': input}),
    );
    final out = await decodeOutput(result.outputs['image'] as Map<String, dynamic>);
    expect(out.width, 40);
    expect(out.height, 30);
  });

  test('ImageAnnotate keeps the image dimensions', () async {
    final input = await assetPayload(60, 60);
    final result = await executor.execute(
      const FlowNode(
        id: 'ann',
        type: 'ImageAnnotate',
        x: 0,
        y: 0,
        data: {
          'shapes': [
            {'type': 'rect', 'x1': 5, 'y1': 5, 'x2': 40, 'y2': 40},
          ],
        },
      ),
      ctx({'image': input}),
    );
    final out = await decodeOutput(result.outputs['image'] as Map<String, dynamic>);
    expect(out.width, 60);
    expect(out.height, 60);
  });
}

class _NoopClient implements ProviderClient {
  @override
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    return const ProviderResponse(statusCode: 200, body: '{}');
  }
}

class _MemStore implements LocalKvStore {
  final Map<String, Object> _v = {};
  @override
  bool containsKey(String key) => _v.containsKey(key);
  @override
  bool getBool(String key, {bool defaultValue = false}) =>
      _v[key] as bool? ?? defaultValue;
  @override
  int getInt(String key, {int defaultValue = 0}) =>
      _v[key] as int? ?? defaultValue;
  @override
  String? getString(String key) => _v[key] as String?;
  @override
  void remove(String key) => _v.remove(key);
  @override
  bool setBool(String key, bool value) {
    _v[key] = value;
    return true;
  }

  @override
  bool setInt(String key, int value) {
    _v[key] = value;
    return true;
  }

  @override
  bool setString(String key, String value) {
    _v[key] = value;
    return true;
  }
}
