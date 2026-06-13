import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../execution/cain_flow_node_executor.dart';
import '../execution/execution_services.dart';
import '../execution/execution_signals.dart';
import '../logs/log_panel.dart';
import '../logs/log_signals.dart';
import '../media/media_repository.dart';
import '../nodes/node_registry.dart';
import '../settings/provider_settings.dart';
import '../settings/settings_screen.dart';
import '../../core/network/provider_client.dart';
import '../../core/network/retrying_provider_client.dart';
import '../../core/storage/mmkv_local_kv_store.dart';
import 'workbench_execution_controller.dart';
import 'workbench_signals.dart';
import 'widgets/connection_layer.dart';
import 'widgets/node_card.dart';

/// Default production controller wired to MMKV-backed services and the
/// real HTTP provider client with retry support. Built lazily so widget
/// rendering does not require native MMKV to be initialized.
WorkbenchExecutionController _buildDefaultController() {
  final store = MmkvLocalKvStore();
  final settingsRepository = ProviderSettingsRepository(store: store);
  final ProviderClient client = RetryingProviderClient(
    inner: DartIoProviderClient(),
    maxRetries: settingsRepository.load().runtime.retryCount,
  );
  final services = ExecutionServices(
    settingsRepository: settingsRepository,
    providerClient: client,
    mediaRepository: MediaRepository(store: store),
    logs: logSignals,
  );
  return WorkbenchExecutionController(
    workbench: workbenchSignals,
    executor: CainFlowNodeExecutor(services: services),
    executionSignals: executionSignals,
    logs: logSignals,
  );
}

WorkbenchExecutionController? _defaultController;
WorkbenchExecutionController get workbenchExecutionController =>
    _defaultController ??= _buildDefaultController();

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
          final content = [
            Text('Workflows', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _RailAction(
              icon: Icons.add_rounded,
              label: 'New workflow',
              onTap: () {},
            ),
            const SizedBox(height: 8),
            _WorkflowTile(
              title: state.activeWorkflowName.value,
              subtitle: state.graphSummary.value,
              selected: true,
            ),
            if (!isCompact) ...[
              const Spacer(),
              Text(
                'MMKV persistence boundary ready',
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
              onTap: state.clearSelection,
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
                  onSelect: () => state.selectNode(node.id),
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
  });

  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
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
