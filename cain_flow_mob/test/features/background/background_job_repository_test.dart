import 'package:cain_flow_mob/core/models/flow_connection.dart';
import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/core/models/workflow_document.dart';
import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/background/background_job_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackgroundJobRepository', () {
    test('stores and restores queued and running job snapshots', () {
      final store = _MemoryLocalKvStore();
      final repository = BackgroundJobRepository(store: store);
      final workflow = WorkflowDocument(
        name: 'Queued workflow',
        canvas: const WorkflowCanvas(x: 24, y: 12, zoom: 0.75),
        nodes: const [
          FlowNode(
            id: 'node_prompt',
            type: 'Text',
            x: 16,
            y: 24,
            data: {'text': 'hello world'},
          ),
          FlowNode(
            id: 'node_image',
            type: 'ImageGenerate',
            x: 220,
            y: 24,
            data: {'model': 'gpt-image-1'},
          ),
        ],
        connections: const [
          FlowConnection(
            id: 'conn_prompt_image',
            from: FlowEndpoint(
              nodeId: 'node_prompt',
              port: 'text',
              type: 'text',
            ),
            to: FlowEndpoint(
              nodeId: 'node_image',
              port: 'prompt',
              type: 'text',
            ),
            type: 'text',
          ),
        ],
        version: WorkflowDocument.defaultVersion,
      );
      final queuedAt = DateTime.utc(2026, 6, 15, 10, 30);
      final runningAt = queuedAt.add(const Duration(seconds: 5));

      final queued = BackgroundJobSnapshot(
        jobId: 'job-42',
        workflow: workflow,
        status: BackgroundJobStatus.queued,
        createdAt: queuedAt,
        updatedAt: queuedAt,
        asyncTask: const BackgroundAsyncTaskMetadata(
          taskId: 'task-queued',
          provider: 'openai',
          pollUrl: 'https://example.com/tasks/task-queued',
          state: 'submitted',
          requestToken: 'req-queued',
        ),
      );

      expect(repository.saveJob(queued), isTrue);

      final restoredQueued = repository.loadJob('job-42');
      expect(restoredQueued, isNotNull);
      expect(restoredQueued!.jobId, 'job-42');
      expect(restoredQueued.status, BackgroundJobStatus.queued);
      expect(restoredQueued.createdAt, queuedAt);
      expect(restoredQueued.updatedAt, queuedAt);
      expect(restoredQueued.workflow.toJson(), workflow.toJson());
      expect(restoredQueued.asyncTask, isNotNull);
      expect(restoredQueued.asyncTask!.taskId, 'task-queued');
      expect(restoredQueued.asyncTask!.provider, 'openai');
      expect(
        restoredQueued.asyncTask!.pollUrl,
        'https://example.com/tasks/task-queued',
      );
      expect(restoredQueued.asyncTask!.state, 'submitted');
      expect(restoredQueued.asyncTask!.requestToken, 'req-queued');

      final running = restoredQueued.copyWith(
        status: BackgroundJobStatus.running,
        updatedAt: runningAt,
        asyncTask: restoredQueued.asyncTask!.copyWith(state: 'running'),
      );

      expect(repository.saveJob(running), isTrue);

      final restoredRunning = repository.loadJob('job-42');
      expect(restoredRunning, isNotNull);
      expect(restoredRunning!.status, BackgroundJobStatus.running);
      expect(restoredRunning.updatedAt, runningAt);
      expect(restoredRunning.workflow.toJson(), workflow.toJson());
      expect(restoredRunning.asyncTask, isNotNull);
      expect(restoredRunning.asyncTask!.taskId, 'task-queued');
      expect(restoredRunning.asyncTask!.state, 'running');
    });
  });
}

class _MemoryLocalKvStore implements LocalKvStore {
  final Map<String, Object> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    return _values[key] as bool? ?? defaultValue;
  }

  @override
  int getInt(String key, {int defaultValue = 0}) {
    return _values[key] as int? ?? defaultValue;
  }

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  void remove(String key) {
    _values.remove(key);
  }

  @override
  bool setBool(String key, bool value) {
    _values[key] = value;
    return true;
  }

  @override
  bool setInt(String key, int value) {
    _values[key] = value;
    return true;
  }

  @override
  bool setString(String key, String value) {
    _values[key] = value;
    return true;
  }
}
