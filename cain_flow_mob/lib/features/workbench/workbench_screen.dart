import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signals/signals_flutter.dart';

import '../execution/cain_flow_node_executor.dart';
import '../execution/execution_services.dart';
import '../execution/execution_signals.dart';
import '../history/history_repository.dart';
import '../logs/log_panel.dart';
import '../logs/log_signals.dart';
import '../media/media_repository.dart';
import '../nodes/node_registry.dart';
import '../nodes/node_definition.dart';
import '../settings/provider_settings.dart';
import '../statistics/request_statistics.dart';
import '../settings/settings_screen.dart';
import '../workflow/workflow_manager.dart';
import '../workflow/workflow_repository.dart';
import '../../core/network/provider_client.dart';
import '../../core/network/retrying_provider_client.dart';
import '../../core/storage/in_memory_local_kv_store.dart';
import '../../core/storage/local_kv_store.dart';
import '../../core/storage/mmkv_local_kv_store.dart';
import 'workbench_execution_controller.dart';
import 'workbench_history.dart';
import 'workbench_signals.dart';
import 'connection_rules.dart';
import 'widgets/connection_layer.dart';
import 'widgets/node_card.dart';
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
  );
  return WorkbenchExecutionController(
    workbench: workbenchSignals,
    executor: CainFlowNodeExecutor(services: services),
    executionSignals: executionSignals,
    logs: logSignals,
    maxConcurrency: runtime.maxConcurrency,
    historyRepository: HistoryRepository(store: store),
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
WorkflowManager? _defaultWorkflowManager;
WorkflowManager get workflowManager {
  if (_defaultWorkflowManager != null) return _defaultWorkflowManager!;
  final store = _safeStore();
  final manager = WorkflowManager(
    repository: WorkflowRepository(store: store),
    workbench: workbenchSignals,
    media: MediaRepository(store: store),
  );
  manager.refresh();
  return _defaultWorkflowManager = manager;
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
    final theme = Theme.of(context);
    final state = workbenchSignals;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('CainFlow'),
            Text(
              state.activeWorkflowName.value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Import workflow',
            onPressed: () => _showSettings(context),
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: 'Undo',
            onPressed: workbenchHistory.canUndo.value
                ? workbenchHistory.undo
                : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed: workbenchHistory.canRedo.value
                ? workbenchHistory.redo
                : null,
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            tooltip: 'Save workflow',
            onPressed: () {
              logSignals.add(
                LogLevel.info,
                'Workflow save requested',
                scope: 'workbench',
              );
            },
            icon: const Icon(Icons.save_outlined),
          ),
          IconButton(
            tooltip: 'Logs',
            onPressed: () => _showLogs(context),
            icon: Icon(
              logSignals.hasErrors.value
                  ? Icons.error_outline_rounded
                  : Icons.receipt_long_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => _showSettings(context),
            icon: const Icon(Icons.tune_rounded),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: () {
                if (state.runState.value == WorkbenchRunState.running) {
                  _controller.stop();
                } else {
                  _controller.run();
                }
              },
              icon: Icon(
                state.runState.value == WorkbenchRunState.running
                    ? Icons.stop_rounded
                    : Icons.play_arrow_rounded,
              ),
              label: Text(
                state.runState.value == WorkbenchRunState.running
                    ? 'Stop'
                    : 'Run',
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 860) {
            return const _CompactWorkbench();
          }
          return const Row(
            children: [
              SizedBox(width: 280, child: _WorkflowRail()),
              VerticalDivider(),
              Expanded(child: _CanvasStage()),
              VerticalDivider(),
              SizedBox(width: 320, child: _InspectorRail()),
            ],
          );
        },
      ),
    );
  }
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
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Add node', style: theme.textTheme.titleMedium),
            ),
            for (final definition in nodeRegistry.all)
              ListTile(
                title: Text(definition.title),
                subtitle: Text(definition.description),
                onTap: () => Navigator.of(context).pop(definition.type),
              ),
          ],
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
      onDelete: () {
        workbenchSignals.removeNode(nodeId);
        Navigator.of(sheetContext).pop();
      },
    ),
  );
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
      ConnectionRejection.selfConnection => 'Cannot connect a node to itself',
      ConnectionRejection.typeMismatch => 'Port types do not match',
      ConnectionRejection.cycle => 'That link would create a cycle',
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
  final name = await _promptForName(context, title: 'New workflow');
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
            title: const Text('Rename'),
            onTap: () => Navigator.of(context).pop('rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ],
      ),
    ),
  );
  if (action == 'rename') {
    if (!context.mounted) return;
    final name = await _promptForName(context, title: 'Rename workflow');
    if (name != null && name.isNotEmpty) workflowManager.rename(id, name);
  } else if (action == 'delete') {
    await workflowManager.delete(id);
  }
}

Future<String?> _promptForName(
  BuildContext context, {
  required String title,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _CompactWorkbench extends StatelessWidget {
  const _CompactWorkbench();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 180, child: _WorkflowRail()),
        Divider(),
        Expanded(child: _CanvasStage()),
      ],
    );
  }
}

class _WorkflowRail extends SignalWidget {
  const _WorkflowRail();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = workbenchSignals;

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxHeight < 260;
          final manager = workflowManager;
          final activeId = manager.activeWorkflowId.value;
          final content = [
            Text('Workflows', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _RailAction(
              icon: Icons.add_rounded,
              label: 'Add node',
              onTap: () => _showNodePicker(context),
            ),
            const SizedBox(height: 8),
            _RailAction(
              icon: Icons.note_add_outlined,
              label: 'New workflow',
              onTap: () => _createWorkflow(context),
            ),
            const SizedBox(height: 8),
            // Active (possibly unsaved) workflow.
            _WorkflowTile(
              title: state.activeWorkflowName.value,
              subtitle: state.graphSummary.value,
              selected: true,
              onLongPress: activeId == null
                  ? null
                  : () => _workflowActions(context, activeId),
            ),
            // Other saved workflows.
            for (final wf in manager.workflows.value)
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
                'Long-press a workflow to rename or delete',
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

class _CanvasStage extends SignalWidget {
  const _CanvasStage();

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

    return ColoredBox(
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
                state.moveCanvas(
                  NodeOffset(details.delta.dx, details.delta.dy),
                );
              },
              child: ConnectionLayer(
                nodes: displayNodes,
                connections: state.connections.value,
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
                  imagePayload: executionSignals.imageOutputs.value[node.id],
                  pendingFromPort:
                      state.pendingConnection.value?.fromNodeId == node.id
                          ? state.pendingConnection.value?.fromPort
                          : null,
                  onSelect: () => state.selectNode(node.id),
                  onOpen: () => _openNodeEditor(context, node.id),
                  onPortTap: (port, isOutput) =>
                      _handlePortTap(context, node.id, port, isOutput),
                  onMove: (offset) {
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
              label: _executionStatusLabel(executionSignals.workflowState.value),
              value: state.graphSummary.value,
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
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inspector', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (selected == null)
              Text(
                'Select a node to edit its settings.',
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
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: state.clearSelection,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Clear selection'),
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
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${(zoom * 100).round()}%',
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            icon: const Icon(Icons.add_rounded),
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
  const _StatusChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text('$label - $value'),
      ),
    );
  }
}

String _executionStatusLabel(WorkflowExecutionState state) {
  return switch (state) {
    WorkflowExecutionState.idle => 'Ready',
    WorkflowExecutionState.running => 'Running',
    WorkflowExecutionState.completed => 'Completed',
    WorkflowExecutionState.failed => 'Failed',
    WorkflowExecutionState.canceled => 'Canceled',
  };
}

String _nodeStateLabel(NodeRunState state) {
  return switch (state) {
    NodeRunState.pending => 'Pending',
    NodeRunState.running => 'Running',
    NodeRunState.completed => 'Completed',
    NodeRunState.failed => 'Failed',
    NodeRunState.skipped => 'Skipped',
  };
}

class _NodeStatusLine extends StatelessWidget {
  const _NodeStatusLine({required this.snapshot});

  final NodeRunSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = snapshot;
    final label = snap == null ? 'Pending' : _nodeStateLabel(snap.state);
    final color = switch (snap?.state) {
      NodeRunState.failed => theme.colorScheme.error,
      NodeRunState.completed => Colors.green,
      _ => theme.colorScheme.onSurfaceVariant,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 8),
            Text('Status: $label', style: theme.textTheme.bodyMedium),
          ],
        ),
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
    final paint = Paint()
      ..color = const Color(0xFF252B30)
      ..strokeWidth = 1;
    const gap = 28.0;

    for (var x = 0.0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
