import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signals/signals_flutter.dart';

import '../../app/theme/cain_tokens.dart';
import '../../l10n/app_localizations.dart';

import '../execution/cain_flow_node_executor.dart';
import '../execution/execution_services.dart';
import '../execution/execution_signals.dart';
import '../history/history_repository.dart';
import '../history/run_history_screen.dart';
import '../logs/log_panel.dart';
import '../logs/log_signals.dart';
import '../media/media_repository.dart';
import '../nodes/node_registry.dart';
import '../camera/camera_prompt.dart';
import '../nodes/node_definition.dart';
import '../settings/provider_settings.dart';
import '../statistics/request_statistics.dart';
import '../settings/settings_screen.dart';
import '../background/background_service_channel.dart';
import '../workflow/workflow_manager.dart';
import '../workflow/workflow_repository.dart';
import 'workbench_workflow_mapper.dart';
import '../../core/models/workflow_document.dart';
import '../../core/network/provider_client.dart';
import '../../core/network/retrying_provider_client.dart';
import '../../core/storage/in_memory_local_kv_store.dart';
import '../../core/storage/local_kv_store.dart';
import '../../core/storage/mmkv_local_kv_store.dart';
import 'workbench_autosave.dart';
import 'completion_feedback.dart';
import 'workbench_execution_controller.dart';
import 'workbench_history.dart';
import 'workbench_signals.dart';
import 'connection_rules.dart';
import 'widgets/connection_layer.dart';
import 'widgets/node_card.dart';
import 'camera_editor_screen.dart';
import 'widgets/node_param_sheet.dart';

/// Default production controller wired to MMKV-backed services and the
/// real HTTP provider client with retry support. Built lazily so widget
/// rendering does not require native MMKV to be initialized.
WorkbenchExecutionController _buildDefaultController() {
  final store = _safeStore();
  final settingsRepository = ProviderSettingsRepository(store: store);
  final runtime = settingsRepository.load().runtime;
  final ProviderClient client = RetryingProviderClient(
    inner: DartIoProviderClient(),
    maxRetries: runtime.retryCount,
  );
  final services = ExecutionServices(
    settingsRepository: settingsRepository,
    providerClient: client,
    mediaRepository: MediaRepository(store: store),
    logs: logSignals,
    statistics: RequestStatistics(store: store),
    executionSignals: executionSignals,
  );
  return WorkbenchExecutionController(
    workbench: workbenchSignals,
    executor: CainFlowNodeExecutor(services: services),
    executionSignals: executionSignals,
    logs: logSignals,
    maxConcurrency: runtime.maxConcurrency,
    historyRepository: HistoryRepository(store: store),
    feedback: CompletionFeedback(
      soundEnabledProvider: () =>
          settingsRepository.load().runtime.completionSoundEnabled,
      hapticsEnabledProvider: () =>
          settingsRepository.load().runtime.completionHapticsEnabled,
    ),
  );
}

WorkbenchExecutionController? _defaultController;
WorkbenchExecutionController get workbenchExecutionController =>
    _defaultController ??= _buildDefaultController();

/// Global undo/redo history bound to the shared workbench signals.
final WorkbenchHistory workbenchHistory = () {
  final history = WorkbenchHistory(workbench: workbenchSignals);
  workbenchSignals.onBeforeMutation = history.record;
  return history;
}();

/// Lazily-built workflow manager backed by MMKV, used by the Workflows rail.
/// Also restores the last active workflow (including image previews) on startup.
WorkflowManager? _defaultWorkflowManager;
WorkflowManager get workflowManager {
  if (_defaultWorkflowManager != null) return _defaultWorkflowManager!;
  final store = _safeStore();
  final repo = WorkflowRepository(store: store);
  final manager = WorkflowManager(
    repository: repo,
    workbench: workbenchSignals,
    media: MediaRepository(store: store),
    flushActive: () => workflowAutoSave.flush(),
    onWorkflowApplied: _restoreImageOutputs,
  );
  // Assign BEFORE calling refresh/switchTo so any re-entrant access to
  // workflowManager (e.g. via flushActive → workflowAutoSave → workflowManager)
  // returns the already-created instance instead of starting a new init.
  _defaultWorkflowManager = manager;
  manager.refresh();

  // Restore the workflow that was open when the app was last closed.
  final lastId = repo.loadActiveId();
  if (lastId != null && lastId.isNotEmpty) {
    manager.switchTo(lastId);
  }

  return manager;
}

/// Auto-save: debounced, only fires when the workflow already has a saved ID.
WorkflowAutoSave? _autoSave;
WorkflowAutoSave get workflowAutoSave {
  return _autoSave ??= WorkflowAutoSave(
    workbench: workbenchSignals,
    manager: workflowManager,
  );
}

/// Restores `imageOutputs` from `_lastOutput` fields baked into each node's
/// data map when a workflow document is loaded.
void _restoreImageOutputs(WorkflowDocument document) {
  for (final node in document.nodes) {
    final last = node.data['_lastOutput'];
    if (last is Map) {
      executionSignals.setImageOutput(node.id, Map<String, dynamic>.from(last));
    }
  }
}

/// Returns the native MMKV store, falling back to an in-memory store when
/// MMKV is not initialized (e.g. widget tests).
LocalKvStore _safeStore() {
  try {
    return MmkvLocalKvStore();
  } catch (_) {
    return InMemoryLocalKvStore();
  }
}

class WorkbenchScreen extends SignalWidget {
  const WorkbenchScreen({super.key, this.controller});

  /// Injected controller for tests. When null, the lazily-built default
  /// controller is resolved on first Run/Stop.
  final WorkbenchExecutionController? controller;

  WorkbenchExecutionController get _controller =>
      controller ?? workbenchExecutionController;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 860;
    return isCompact ? _buildCompact(context) : _buildWide(context);
  }

  // ---- Compact scaffold (phone / narrow tablet) ----------------------------

  Widget _buildCompact(BuildContext context) {
    final state = workbenchSignals;
    // Read signals here so the scaffold reacts to state changes.
    final running = state.runState.value == WorkbenchRunState.running;
    final canUndo = workbenchHistory.canUndo.value;
    final canRedo = workbenchHistory.canRedo.value;
    final hasErrors = logSignals.hasErrors.value;
    final workflowName = state.activeWorkflowName.value;

    return Scaffold(
      appBar: AppBar(
        // DrawerButton auto-inserted when drawer is set and leading is null.
        title: _AppTitle(workflowName: workflowName),
        actions: [
          IconButton(
            tooltip: context.l10n.addNode,
            onPressed: () => _showNodePicker(context),
            icon: const Icon(Icons.add_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton.icon(
              onPressed: running ? _stopRun : _startRun,
              icon: Icon(
                running ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(running ? context.l10n.stop : context.l10n.run),
            ),
          ),
          PopupMenuButton<_OverflowAction>(
            tooltip: context.l10n.moreActions,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) => _handleOverflow(context, action),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _OverflowAction.undo,
                enabled: canUndo,
                child: _OverflowItem(Icons.undo_rounded, context.l10n.undo),
              ),
              PopupMenuItem(
                value: _OverflowAction.redo,
                enabled: canRedo,
                child: _OverflowItem(Icons.redo_rounded, context.l10n.redo),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _OverflowAction.save,
                child: _OverflowItem(
                  Icons.save_outlined,
                  context.l10n.saveWorkflow,
                ),
              ),
              PopupMenuItem(
                value: _OverflowAction.history,
                child: _OverflowItem(
                  Icons.history_rounded,
                  context.l10n.history,
                ),
              ),
              PopupMenuItem(
                value: _OverflowAction.logs,
                child: _OverflowItem(
                  hasErrors
                      ? Icons.error_outline_rounded
                      : Icons.receipt_long_outlined,
                  context.l10n.logs,
                ),
              ),
              PopupMenuItem(
                value: _OverflowAction.settings,
                child: _OverflowItem(Icons.tune_rounded, context.l10n.settings),
              ),
            ],
          ),
        ],
      ),
      drawer: const _WorkflowDrawer(),
      body: const _CompactBody(),
    );
  }

  void _handleOverflow(BuildContext context, _OverflowAction action) {
    final state = workbenchSignals;
    switch (action) {
      case _OverflowAction.undo:
        workbenchHistory.undo();
      case _OverflowAction.redo:
        workbenchHistory.redo();
      case _OverflowAction.save:
        final id = workflowManager.save();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.savedWorkflowSnack(state.activeWorkflowName.value),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        logSignals.add(
          LogLevel.info,
          'Workflow saved: $id',
          scope: 'workbench',
        );
      case _OverflowAction.history:
        _showHistory(context);
      case _OverflowAction.logs:
        _showLogs(context);
      case _OverflowAction.settings:
        _showSettings(context);
    }
  }

  // ---- Wide scaffold (desktop / landscape tablet) --------------------------

  Widget _buildWide(BuildContext context) {
    final state = workbenchSignals;
    final running = state.runState.value == WorkbenchRunState.running;
    final canUndo = workbenchHistory.canUndo.value;
    final canRedo = workbenchHistory.canRedo.value;
    final hasErrors = logSignals.hasErrors.value;
    final workflowName = state.activeWorkflowName.value;

    return Scaffold(
      appBar: AppBar(
        title: _AppTitle(workflowName: workflowName),
        actions: [
          IconButton(
            tooltip: context.l10n.importWorkflow,
            onPressed: () => _showSettings(context),
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: context.l10n.undo,
            onPressed: canUndo ? workbenchHistory.undo : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: context.l10n.redo,
            onPressed: canRedo ? workbenchHistory.redo : null,
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            tooltip: context.l10n.saveWorkflow,
            onPressed: () {
              final id = workflowManager.save();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.l10n.savedWorkflowSnack(
                      state.activeWorkflowName.value,
                    ),
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
              logSignals.add(
                LogLevel.info,
                'Workflow saved: $id',
                scope: 'workbench',
              );
            },
            icon: const Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: context.l10n.logs,
            onPressed: () => _showLogs(context),
            icon: Icon(
              hasErrors
                  ? Icons.error_outline_rounded
                  : Icons.receipt_long_outlined,
            ),
          ),
          IconButton(
            tooltip: context.l10n.history,
            onPressed: () => _showHistory(context),
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: context.l10n.settings,
            onPressed: () => _showSettings(context),
            icon: const Icon(Icons.tune_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: running ? _stopRun : _startRun,
              icon: Icon(
                running ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(running ? context.l10n.stop : context.l10n.run),
            ),
          ),
        ],
      ),
      body: const Row(
        children: [
          SizedBox(width: 280, child: _WorkflowRail()),
          VerticalDivider(),
          Expanded(child: _CanvasStage()),
          VerticalDivider(),
          SizedBox(width: 320, child: _InspectorRail()),
        ],
      ),
    );
  }

  Future<void> _startRun() async {
    if (!_supportsAndroidForegroundService) {
      await _controller.run();
      return;
    }

    final workflow = workbenchSignalsToWorkflow(workbenchSignals);
    final queuedJobId = _controller.queueBackgroundRun(workflow);
    try {
      await backgroundTaskBridge.startForegroundService(
        jobId: queuedJobId ?? '',
        workflow: workflow.toJson(),
      );
    } catch (error) {
      logSignals.add(
        LogLevel.error,
        'Failed to start Android background task: $error',
        scope: 'background_service',
      );
      _controller.stop();
    }
  }

  Future<void> _stopRun() async {
    if (!_supportsAndroidForegroundService) {
      _controller.stop();
      return;
    }

    final jobId = executionSignals.backgroundJobId.value.trim();
    try {
      await backgroundTaskBridge.stopForegroundService(jobId: jobId);
    } catch (error) {
      logSignals.add(
        LogLevel.warning,
        'Failed to stop Android background task cleanly: $error',
        scope: 'background_service',
      );
    } finally {
      _controller.stop();
    }
  }
}

bool get _supportsAndroidForegroundService =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<void> _showHistory(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        RunHistoryScreen(repository: HistoryRepository(store: _safeStore())),
  );
}

Future<void> _showSettings(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SettingsScreen(),
  );
}

Future<void> _showLogs(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const LogPanel(),
  );
}

/// Bottom-sheet list of registered node types; tapping one adds it.
Future<void> _showNodePicker(BuildContext context) async {
  final type = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      final theme = Theme.of(context);
      // Cap the sheet at 70% of screen height; the node list scrolls inside.
      final maxHeight = MediaQuery.of(context).size.height * 0.7;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  context.l10n.addNode,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final definition in nodeRegistry.all)
                      ListTile(
                        title: Text(definition.title),
                        subtitle: Text(definition.description),
                        onTap: () => Navigator.of(context).pop(definition.type),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (type == null) return;
  final id = workbenchSignals.addNode(type);
  workbenchSignals.selectNode(id);
}

/// Opens the parameter editor sheet for [nodeId].
Future<void> _openNodeEditor(BuildContext context, String nodeId) async {
  final node = workbenchSignals.nodes.value
      .where((n) => n.id == nodeId)
      .cast<WorkbenchNode?>()
      .firstWhere((n) => n != null, orElse: () => null);
  if (node == null) return;
  final models = _loadModels();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => NodeParamSheet(
      node: node,
      definition: nodeRegistry.get(node.type),
      models: models,
      onChanged: (data) => workbenchSignals.updateNodeData(nodeId, data),
      onPickImage: () => _pickAndStoreImage(),
      onEditCamera: (current) => _editCamera(context, nodeId, current),
      onDelete: () {
        workbenchSignals.removeNode(nodeId);
        Navigator.of(sheetContext).pop();
      },
    ),
  );
}

/// Opens the full-screen camera viewpoint editor and returns updated data.
/// Resolves the image connected to the node's `image` port so the editor can
/// project it onto the live preview billboard.
Future<Map<String, dynamic>?> _editCamera(
  BuildContext context,
  String nodeId,
  Map<String, dynamic> current,
) {
  return Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      builder: (_) => CameraEditorScreen(
        initial: CameraState.fromData(current),
        referenceImagePayload: _resolveUpstreamImagePayload(nodeId, 'image'),
        media: MediaRepository(store: _safeStore()),
      ),
    ),
  );
}

/// Finds the image payload feeding [toPort] of [nodeId] by following the
/// incoming connection to its source node's published image output. Mirrors
/// the web `findConnectedInputImage`.
Object? _resolveUpstreamImagePayload(String nodeId, String toPort) {
  final connection = workbenchSignals.connections.value
      .where((c) => c.toNodeId == nodeId && c.toPort == toPort)
      .cast<WorkbenchConnection?>()
      .firstWhere((c) => c != null, orElse: () => null);
  if (connection == null) return null;
  return executionSignals.imageOutputs.value[connection.fromNodeId];
}

/// Handles a port tap for point-select connections: an output port arms a
/// pending connection; an input port completes it (with rejection feedback).
void _handlePortTap(
  BuildContext context,
  String nodeId,
  NodePortDefinition port,
  bool isOutput,
) {
  final state = workbenchSignals;
  if (isOutput) {
    state.beginConnection(nodeId, port.name, port.type);
    return;
  }
  if (state.pendingConnection.value == null) return;
  final rejection = state.completeConnection(nodeId, port.name, port.type);
  if (rejection != ConnectionRejection.none) {
    final message = switch (rejection) {
      ConnectionRejection.selfConnection => context.l10n.cannotConnectSelf,
      ConnectionRejection.typeMismatch => context.l10n.portTypeMismatch,
      ConnectionRejection.cycle => context.l10n.connectionCycle,
      ConnectionRejection.none => '',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

List<ModelConfig> _loadModels() {
  try {
    final store = _safeStore();
    return ProviderSettingsRepository(store: store).load().models;
  } catch (_) {
    return const [];
  }
}

/// Picks an image from the gallery, stores its bytes via [MediaRepository],
/// and returns the new asset id (or null if the user cancelled).
Future<String?> _pickAndStoreImage() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  final store = _safeStore();
  final media = MediaRepository(store: store);
  final asset = await media.saveBytes(
    workflowId: workbenchSignals.activeWorkflowName.value,
    fileName: picked.name,
    mimeType: _mimeForName(picked.name),
    bytes: bytes,
  );
  return asset.id;
}

String _mimeForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/png';
}

/// Prompts for a name and creates a new (empty) workflow.
Future<void> _createWorkflow(BuildContext context) async {
  final name = await _promptForName(context, title: context.l10n.newWorkflow);
  if (name == null || name.isEmpty) return;
  workflowManager.newWorkflow(name: name);
}

/// Shows rename/delete actions for a saved workflow [id].
Future<void> _workflowActions(BuildContext context, String id) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(context.l10n.rename),
            onTap: () => Navigator.of(context).pop('rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(context.l10n.delete),
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ),
    ),
  );
  if (action == 'rename') {
    if (!context.mounted) return;
    final name = await _promptForName(
      context,
      title: context.l10n.renameWorkflow,
    );
    if (name != null && name.isNotEmpty) workflowManager.rename(id, name);
  } else if (action == 'delete') {
    await workflowManager.delete(id);
  }
}

Future<String?> _promptForName(BuildContext context, {required String title}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.nameLabel),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(context.l10n.ok),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Shared AppBar title widget (logo LED + wordmark + workflow name)
// ---------------------------------------------------------------------------

class _AppTitle extends StatelessWidget {
  const _AppTitle({required this.workflowName});
  final String workflowName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(right: 10, top: 2),
          decoration: BoxDecoration(
            color: CainTokens.phosphor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: CainTokens.phosphor.withValues(alpha: 0.7),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CAINFLOW'),
              Text(
                workflowName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CainTokens.mono(10.5, color: CainTokens.inkFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overflow menu enum + item helper (compact AppBar)
// ---------------------------------------------------------------------------

enum _OverflowAction { undo, redo, save, history, logs, settings }

class _OverflowItem extends StatelessWidget {
  const _OverflowItem(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: CainTokens.inkDim),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Compact body: full-screen canvas + sliding mini-inspector
// ---------------------------------------------------------------------------

class _CompactBody extends SignalWidget {
  const _CompactBody();

  @override
  Widget build(BuildContext context) {
    final selected = workbenchSignals.selectedNode.value;
    return Stack(
      children: [
        const Positioned.fill(child: _CanvasStage()),
        // Mini-inspector slides up from the bottom when a node is selected.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: 0,
          right: 0,
          bottom: selected != null ? 0 : -200,
          child: const _MiniInspector(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mini-inspector: compact bottom panel for the selected node
// ---------------------------------------------------------------------------

class _MiniInspector extends SignalWidget {
  const _MiniInspector();

  @override
  Widget build(BuildContext context) {
    final state = workbenchSignals;
    final selected = state.selectedNode.value;
    if (selected == null) return const SizedBox.shrink();

    final snap = executionSignals.nodeStates.value[selected.id];
    final now = executionSignals.nowTick.value;
    final badge = _miniNodeBadge(selected.type);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: CainTokens.panel,
        border: Border(top: BorderSide(color: CainTokens.panelEdge)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              // Type badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: badge.color.withValues(alpha: 0.5)),
                ),
                child: Text(
                  badge.code,
                  style: CainTokens.mono(
                    9,
                    weight: FontWeight.w700,
                    color: badge.color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Node title + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selected.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CainTokens.display(13, weight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    _MiniStatusLine(snapshot: snap, now: now),
                  ],
                ),
              ),
              // Actions
              IconButton(
                tooltip: context.l10n.editTooltip,
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: CainTokens.inkDim,
                onPressed: () => _openNodeEditor(context, selected.id),
              ),
              IconButton(
                tooltip: context.l10n.deleteTooltip,
                icon: const Icon(Icons.delete_outline, size: 20),
                color: CainTokens.danger.withValues(alpha: 0.8),
                onPressed: () {
                  workbenchSignals.removeNode(selected.id);
                  workbenchSignals.clearSelection();
                },
              ),
              IconButton(
                tooltip: context.l10n.clearSelection,
                icon: const Icon(Icons.close_rounded, size: 20),
                color: CainTokens.inkFaint,
                onPressed: state.clearSelection,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline badge data for the mini-inspector (mirrors node_card.dart logic).
({Color color, String code}) _miniNodeBadge(String type) {
  if (type.startsWith('Control')) {
    return (color: CainTokens.signalControl, code: _miniCode(type));
  }
  if (type.startsWith('Image') || type == 'CameraControl') {
    return (color: CainTokens.signalImage, code: _miniCode(type));
  }
  return (color: CainTokens.signalText, code: _miniCode(type));
}

String _miniCode(String type) {
  final caps = type.replaceAll(RegExp('[^A-Z]'), '');
  if (caps.length >= 2) return caps.substring(0, caps.length.clamp(0, 3));
  return type.substring(0, type.length.clamp(0, 3)).toUpperCase();
}

class _MiniStatusLine extends StatelessWidget {
  const _MiniStatusLine({required this.snapshot, required this.now});
  final NodeRunSnapshot? snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    if (snap == null) {
      return Text(
        context.l10n.statePending,
        style: CainTokens.mono(10, color: CainTokens.inkFaint),
      );
    }
    final label = _nodeStateLabel(snap.state, context.l10n);
    final color = switch (snap.state) {
      NodeRunState.failed => CainTokens.danger,
      NodeRunState.completed => CainTokens.ok,
      NodeRunState.running => CainTokens.phosphor,
      NodeRunState.skipped => CainTokens.idle,
      _ => CainTokens.inkFaint,
    };
    final duration = snap.durationAt(now);
    final suffix = duration == null
        ? ''
        : snap.state == NodeRunState.running
        ? '  ${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s'
        : '  ${(duration.inMilliseconds / 1000).toStringAsFixed(2)}s';
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label$suffix', style: CainTokens.mono(10, color: color)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Workflow drawer (compact mode)
// ---------------------------------------------------------------------------

class _WorkflowDrawer extends SignalWidget {
  const _WorkflowDrawer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manager = workflowManager;
    final state = workbenchSignals;

    final activeId = manager.activeWorkflowId.value;
    final workflows = manager.workflows.value;
    final activeName = state.activeWorkflowName.value;
    final graphSummary = state.graphSummary.value;

    return Drawer(
      backgroundColor: CainTokens.panel,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: BoxDecoration(
                color: CainTokens.panelHigh,
                border: Border(bottom: BorderSide(color: CainTokens.panelEdge)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: CainTokens.phosphor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: CainTokens.phosphor.withValues(alpha: 0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'CAINFLOW',
                        style: CainTokens.display(
                          14,
                          weight: FontWeight.w700,
                          color: CainTokens.phosphor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CainTokens.mono(11, color: CainTokens.inkFaint),
                  ),
                ],
              ),
            ),
            // Quick actions
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showNodePicker(context);
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(context.l10n.addNode),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CainTokens.signalText,
                        side: BorderSide(
                          color: CainTokens.signalText.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _createWorkflow(context);
                      },
                      icon: const Icon(Icons.note_add_outlined, size: 16),
                      label: Text(context.l10n.newWorkflow),
                    ),
                  ),
                ],
              ),
            ),
            // Workflows section header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                context.l10n.workflows,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: CainTokens.inkFaint,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            // Workflow list
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _WorkflowTile(
                    title: activeName,
                    subtitle: graphSummary,
                    selected: true,
                    onLongPress: activeId == null
                        ? null
                        : () => _workflowActions(context, activeId),
                  ),
                  for (final wf in workflows)
                    if (wf.id != activeId) ...[
                      const SizedBox(height: 6),
                      _WorkflowTile(
                        title: wf.name,
                        subtitle: wf.id,
                        selected: false,
                        onTap: () {
                          Navigator.of(context).pop();
                          manager.switchTo(wf.id);
                        },
                        onLongPress: () => _workflowActions(context, wf.id),
                      ),
                    ],
                  // Hint text
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      context.l10n.workflowHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: CainTokens.inkFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Bottom links
            ListTile(
              dense: true,
              leading: Icon(
                Icons.receipt_long_outlined,
                size: 20,
                color: CainTokens.inkDim,
              ),
              title: Text(
                context.l10n.logs,
                style: CainTokens.mono(12, color: CainTokens.inkDim),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _showLogs(context);
              },
            ),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.tune_rounded,
                size: 20,
                color: CainTokens.inkDim,
              ),
              title: Text(
                context.l10n.settings,
                style: CainTokens.mono(12, color: CainTokens.inkDim),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _showSettings(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _WorkflowRail extends SignalWidget {
  const _WorkflowRail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = workbenchSignals;
    final manager = workflowManager;

    // Read every signal here, in SignalWidget.build, so the rail re-renders on
    // change. LayoutBuilder.builder runs outside SignalWidget's tracking scope,
    // so signals read only inside it would not trigger rebuilds.
    final activeId = manager.activeWorkflowId.value;
    final workflows = manager.workflows.value;
    final activeName = state.activeWorkflowName.value;
    final graphSummary = state.graphSummary.value;

    return ColoredBox(
      color: CainTokens.panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < 260;
          final content = [
            Text(context.l10n.workflows, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _RailAction(
              icon: Icons.add_rounded,
              label: context.l10n.addNode,
              onTap: () => _showNodePicker(context),
            ),
            const SizedBox(height: 8),
            _RailAction(
              icon: Icons.note_add_outlined,
              label: context.l10n.newWorkflow,
              onTap: () => _createWorkflow(context),
            ),
            const SizedBox(height: 8),
            // Active (possibly unsaved) workflow.
            _WorkflowTile(
              title: activeName,
              subtitle: graphSummary,
              selected: true,
              onLongPress: activeId == null
                  ? null
                  : () => _workflowActions(context, activeId),
            ),
            // Other saved workflows.
            for (final wf in workflows)
              if (wf.id != activeId) ...[
                const SizedBox(height: 8),
                _WorkflowTile(
                  title: wf.name,
                  subtitle: wf.id,
                  selected: false,
                  onTap: () => manager.switchTo(wf.id),
                  onLongPress: () => _workflowActions(context, wf.id),
                ),
              ],
            if (!isCompact) ...[
              const Spacer(),
              Text(
                context.l10n.workflowHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ];

          if (isCompact) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: content,
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content,
            ),
          );
        },
      ),
    );
  }
}

class _CanvasStage extends SignalStatefulWidget {
  const _CanvasStage();

  @override
  State<_CanvasStage> createState() => _CanvasStageState();
}

class _CanvasStageState extends State<_CanvasStage> {
  final Map<int, Offset> _touchPoints = {};
  double? _pinchStartDistance;
  double? _pinchStartZoom;

  bool get _isMobilePlatform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  bool get _isDesktopPlatform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      _ => false,
    };
  }

  void _handlePointerSignal(PointerSignalEvent event, WorkbenchSignals state) {
    if (!_isDesktopPlatform || event is! PointerScrollEvent) return;

    final zoomDelta = -event.scrollDelta.dy * 0.0015;
    if (zoomDelta == 0) return;
    state.setZoomAroundViewportPoint(
      state.zoom.value + zoomDelta,
      NodeOffset(event.localPosition.dx, event.localPosition.dy),
    );
  }

  void _handleTouchPointerDown(PointerDownEvent event) {
    if (!_isTouchGesturePointer(event)) return;
    _touchPoints[event.pointer] = event.localPosition;
    _resetPinchBaseline();
  }

  void _handleTouchPointerMove(PointerMoveEvent event, WorkbenchSignals state) {
    if (!_isTouchGesturePointer(event) ||
        !_touchPoints.containsKey(event.pointer)) {
      return;
    }

    _touchPoints[event.pointer] = event.localPosition;
    if (_touchPoints.length < 2) return;

    final points = _touchPoints.values.take(2).toList(growable: false);
    final distance = (points[0] - points[1]).distance;
    if (distance == 0) return;

    _pinchStartDistance ??= distance;
    _pinchStartZoom ??= state.zoom.value;

    final midpoint = Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
    state.setZoomAroundViewportPoint(
      _pinchStartZoom! * (distance / _pinchStartDistance!),
      NodeOffset(midpoint.dx, midpoint.dy),
    );
  }

  void _handleTouchPointerEnd(PointerEvent event) {
    if (!_isTouchGesturePointer(event)) return;
    _touchPoints.remove(event.pointer);
    _resetPinchBaseline();
  }

  bool _isTouchGesturePointer(PointerEvent event) {
    return _isMobilePlatform && event.kind == PointerDeviceKind.touch;
  }

  void _resetPinchBaseline() {
    _pinchStartDistance = null;
    _pinchStartZoom = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = workbenchSignals;
    final zoom = state.zoom.value;
    final pan = state.panOffset.value;
    final displayNodes = [
      for (final node in state.nodes.value)
        WorkbenchNode(
          id: node.id,
          type: node.type,
          title: node.title,
          x: pan.dx + node.x * zoom,
          y: pan.dy + node.y * zoom,
        ),
    ];

    return Listener(
      onPointerSignal: (event) => _handlePointerSignal(event, state),
      onPointerDown: _handleTouchPointerDown,
      onPointerMove: (event) => _handleTouchPointerMove(event, state),
      onPointerUp: _handleTouchPointerEnd,
      onPointerCancel: _handleTouchPointerEnd,
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Stack(
          children: [
            const Positioned.fill(child: _WorkbenchGrid()),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  state.clearSelection();
                  state.cancelPendingConnection();
                },
                onLongPress: () => _showNodePicker(context),
                onPanUpdate: (details) {
                  if (_isMobilePlatform && _touchPoints.length > 1) return;
                  state.moveCanvas(
                    NodeOffset(details.delta.dx, details.delta.dy),
                  );
                },
                child: ConnectionLayer(
                  nodes: displayNodes,
                  connections: state.connections.value,
                  zoom: zoom,
                  imageOutputs: executionSignals.imageOutputs.value.keys
                      .toSet(),
                ),
              ),
            ),
            for (final node in displayNodes)
              Positioned(
                left: node.x,
                top: node.y,
                child: Transform.scale(
                  scale: zoom,
                  alignment: Alignment.topLeft,
                  child: NodeCard(
                    node: node,
                    definition: nodeRegistry.get(node.type),
                    selected: state.selectedNodeId.value == node.id,
                    imagePayload: _cardImagePayload(node),
                    runState: executionSignals.nodeStates.value[node.id]?.state,
                    pollText: executionSignals.pollProgress.value[node.id],
                    pendingFromPort:
                        state.pendingConnection.value?.fromNodeId == node.id
                        ? state.pendingConnection.value?.fromPort
                        : null,
                    onSelect: () => state.selectNode(node.id),
                    onOpen: () => _openNodeEditor(context, node.id),
                    onPortTap: (port, isOutput) =>
                        _handlePortTap(context, node.id, port, isOutput),
                    onMove: (offset) {
                      if (_isMobilePlatform && _touchPoints.length > 1) return;
                      state.moveNode(
                        node.id,
                        NodeOffset(offset.dx / zoom, offset.dy / zoom),
                      );
                    },
                  ),
                ),
              ),
            Positioned(
              left: 16,
              bottom: 16,
              child: _StatusChip(
                label: _executionStatusLabel(
                  executionSignals.workflowState.value,
                  context.l10n,
                ),
                value: executionSignals.isRunning.value
                    ? '${executionSignals.completedCount.value}/'
                          '${executionSignals.totalCount.value}'
                    : state.graphSummary.value,
                color: _statusColor(executionSignals.workflowState.value),
              ),
            ),
            const Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _RunTimerOverlay(),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: _CanvasControls(
                zoom: zoom,
                onZoomOut: () => state.setZoom(zoom - 0.1),
                onZoomIn: () => state.setZoom(zoom + 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Image payload to preview on a node card: a CameraControl node prefers its
  /// stored viewpoint snapshot (`data.cameraPreview`); all others fall back to
  /// the live execution output.
  Map<String, dynamic>? _cardImagePayload(WorkbenchNode node) {
    if (node.type == 'CameraControl') {
      final preview = node.data['cameraPreview'];
      if (preview is Map) {
        return Map<String, dynamic>.from(preview);
      }
    }
    return executionSignals.imageOutputs.value[node.id];
  }
}

/// Bottom-center capsule shown while a workflow runs: live elapsed time and a
/// cancel button. Fades out when not running.
class _RunTimerOverlay extends SignalWidget {
  const _RunTimerOverlay();

  @override
  Widget build(BuildContext context) {
    final running = executionSignals.isRunning.value;
    // Build nothing when idle so no infinite spinner animation lingers.
    if (!running) return const SizedBox.shrink();

    final elapsed = executionSignals.workflowElapsedAt(
      executionSignals.nowTick.value,
    );
    final seconds = elapsed == null
        ? '0.0s'
        : '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: CainTokens.void0.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: CainTokens.phosphorDim),
        boxShadow: [
          BoxShadow(
            color: CainTokens.phosphor.withValues(alpha: 0.18),
            blurRadius: 22,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 7, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(CainTokens.phosphor),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'RUN',
              style: CainTokens.mono(
                10,
                color: CainTokens.phosphorDim,
                weight: FontWeight.w700,
                spacing: 1.5,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              seconds,
              style: CainTokens.mono(
                14,
                color: CainTokens.phosphor,
                weight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: () => workbenchExecutionController.stop(),
              style: TextButton.styleFrom(foregroundColor: CainTokens.danger),
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: Text(context.l10n.cancelRun),
            ),
          ],
        ),
      ),
    );
  }
}

class _InspectorRail extends SignalWidget {
  const _InspectorRail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = workbenchSignals;
    final selected = state.selectedNode.value;

    return ColoredBox(
      color: CainTokens.panel,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.inspector, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (selected == null)
              Text(
                context.l10n.selectNodeHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...[
              Text(selected.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text(
                '${selected.type} at ${selected.x.toStringAsFixed(0)}, ${selected.y.toStringAsFixed(0)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _NodeStatusLine(
                snapshot: executionSignals.nodeStates.value[selected.id],
                now: executionSignals.nowTick.value,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: state.clearSelection,
                icon: const Icon(Icons.close_rounded),
                label: Text(context.l10n.clearSelection),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkflowTile extends StatelessWidget {
  const _WorkflowTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? CainTokens.phosphorGlow : CainTokens.panelHigh,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? CainTokens.phosphor : CainTokens.panelEdge,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Accent strip standing in for a left edge marker.
            Container(
              width: 3,
              height: 30,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: selected ? CainTokens.phosphor : CainTokens.panelEdge,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(
              Icons.account_tree_outlined,
              size: 18,
              color: selected ? CainTokens.phosphor : CainTokens.inkDim,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CainTokens.display(
                      13,
                      weight: FontWeight.w600,
                      color: selected ? CainTokens.phosphor : CainTokens.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CainTokens.mono(10, color: CainTokens.inkFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CanvasControls extends StatelessWidget {
  const _CanvasControls({
    required this.zoom,
    required this.onZoomOut,
    required this.onZoomIn,
  });

  final double zoom;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CainTokens.void0.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: CainTokens.panelEdge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: context.l10n.zoomOut,
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${(zoom * 100).round()}%',
              textAlign: TextAlign.center,
              style: CainTokens.mono(11.5, color: CainTokens.phosphor),
            ),
          ),
          IconButton(
            tooltip: context.l10n.zoomIn,
            onPressed: onZoomIn,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _RailAction extends StatelessWidget {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final led = color ?? CainTokens.phosphor;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CainTokens.void0.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: CainTokens.panelEdge),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: led,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: led.withValues(alpha: 0.7), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$label - $value',
              style: CainTokens.mono(
                11.5,
                color: CainTokens.inkDim,
                spacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Status LED color for the bottom-left readout.
Color _statusColor(WorkflowExecutionState state) {
  return switch (state) {
    WorkflowExecutionState.running => CainTokens.phosphor,
    WorkflowExecutionState.completed => CainTokens.ok,
    WorkflowExecutionState.failed => CainTokens.danger,
    WorkflowExecutionState.canceled => CainTokens.signalControl,
    WorkflowExecutionState.idle => CainTokens.idle,
  };
}

String _executionStatusLabel(
  WorkflowExecutionState state,
  AppLocalizations l10n,
) {
  return switch (state) {
    WorkflowExecutionState.idle => l10n.statusReady,
    WorkflowExecutionState.running => l10n.statusRunning,
    WorkflowExecutionState.completed => l10n.statusCompleted,
    WorkflowExecutionState.failed => l10n.statusFailed,
    WorkflowExecutionState.canceled => l10n.statusCanceled,
  };
}

String _nodeStateLabel(NodeRunState state, AppLocalizations l10n) {
  return switch (state) {
    NodeRunState.pending => l10n.statePending,
    NodeRunState.running => l10n.statusRunning,
    NodeRunState.completed => l10n.statusCompleted,
    NodeRunState.failed => l10n.statusFailed,
    NodeRunState.skipped => l10n.stateSkipped,
  };
}

class _NodeStatusLine extends StatelessWidget {
  const _NodeStatusLine({required this.snapshot, required this.now});

  final NodeRunSnapshot? snapshot;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = snapshot;
    final label = snap == null
        ? context.l10n.statePending
        : _nodeStateLabel(snap.state, context.l10n);
    final color = switch (snap?.state) {
      NodeRunState.failed => theme.colorScheme.error,
      NodeRunState.completed => Colors.green,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final duration = snap?.durationAt(now);
    final durationText = duration == null
        ? null
        : (snap!.state == NodeRunState.running
              ? context.l10n.runningDuration(
                  (duration.inMilliseconds / 1000).toStringAsFixed(1),
                )
              : context.l10n.elapsedDuration(
                  (duration.inMilliseconds / 1000).toStringAsFixed(2),
                ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 8),
            Text(
              context.l10n.statusLabel(label),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        if (durationText != null) ...[
          const SizedBox(height: 4),
          Text(
            durationText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (snap != null && snap.message.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            snap.message,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ],
    );
  }
}

class _WorkbenchGrid extends StatelessWidget {
  const _WorkbenchGrid();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _WorkbenchGridPainter());
  }
}

class _WorkbenchGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Oscilloscope grid: fine minor lines every 28px, brighter major lines
    // every 5th cell, plus a faint corner vignette for instrument depth.
    const minorGap = 28.0;
    const majorEvery = 5;

    final minor = Paint()
      ..color = CainTokens.gridMinor
      ..strokeWidth = 1;
    final major = Paint()
      ..color = CainTokens.gridMajor
      ..strokeWidth = 1;

    var i = 0;
    for (var x = 0.0; x <= size.width; x += minorGap, i++) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        i % majorEvery == 0 ? major : minor,
      );
    }
    i = 0;
    for (var y = 0.0; y <= size.height; y += minorGap, i++) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        i % majorEvery == 0 ? major : minor,
      );
    }

    // Subtle phosphor vignette from the bottom-left, like a CRT corner glow.
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [CainTokens.phosphorGlow, Colors.transparent],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.18, size.height * 0.92),
              radius: size.shortestSide * 0.7,
            ),
          );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
