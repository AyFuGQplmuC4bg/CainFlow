import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../../l10n/app_localizations.dart';
import 'log_signals.dart';

class LogPanel extends SignalWidget {
  const LogPanel({super.key, this.logs});

  final LogSignals? logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = logs ?? logSignals;
    final entries = state.entries.value;

    return SafeArea(
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Text(context.l10n.logs, style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: context.l10n.clearLogs,
                    onPressed: state.clear,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (entries.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    context.l10n.noLogsYet,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _LogTile(entry: entries[index]);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (entry.level) {
      LogLevel.error => theme.colorScheme.error,
      LogLevel.warning => theme.colorScheme.secondary,
      LogLevel.info => theme.colorScheme.primary,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_iconFor(entry.level), color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.message),
                  if (entry.scope.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.scope,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(LogLevel level) {
  return switch (level) {
    LogLevel.error => Icons.error_outline_rounded,
    LogLevel.warning => Icons.warning_amber_rounded,
    LogLevel.info => Icons.info_outline_rounded,
  };
}
