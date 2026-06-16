import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../workbench/widgets/node_image_thumbnail.dart';
import 'history_repository.dart';

class RunHistoryScreen extends StatelessWidget {
  const RunHistoryScreen({super.key, required this.repository});

  final HistoryRepository repository;

  @override
  Widget build(BuildContext context) {
    final entries = repository.loadAll();
    return Scaffold(
      appBar: AppBar(title: const Text('Run history')),
      body: entries.isEmpty
          ? const Center(child: Text('No successful results yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _HistoryTile(
                  entry: entry,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RunHistoryDetailScreen(entry: entry),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class RunHistoryDetailScreen extends StatelessWidget {
  const RunHistoryDetailScreen({super.key, required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final images = entry.outputs
        .where((output) => output.kind == RunOutputKind.image)
        .toList();
    final texts = entry.outputs
        .where((output) => output.kind == RunOutputKind.text)
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(entry.workflowName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _RunHeader(entry: entry),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Images', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: images.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemBuilder: (context, index) => NodeImageThumbnail(
                payload: images[index].toImagePayload(),
                size: 180,
              ),
            ),
          ],
          if (texts.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Text', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            for (final output in texts) ...[
              _TextOutputBlock(output: output),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onTap});

  final HistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstImage = entry.outputs
        .where((output) => output.kind == RunOutputKind.image)
        .cast<RunOutput?>()
        .firstWhere((output) => output != null, orElse: () => null);
    final firstText = entry.outputs
        .where((output) => output.kind == RunOutputKind.text)
        .map((output) => output.text)
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: SizedBox(
          width: 56,
          height: 56,
          child: firstImage == null
              ? Icon(
                  Icons.text_snippet_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : NodeImageThumbnail(
                  payload: firstImage.toImagePayload(),
                  size: 56,
                ),
        ),
        title: Text(entry.workflowName, maxLines: 1),
        subtitle: Text(
          [
            if (entry.stage?.label.isNotEmpty == true) entry.stage!.label,
            if (firstText.isNotEmpty) firstText,
            '${entry.outputs.length} outputs',
          ].join('  ·  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = entry.durationMillis <= 0
        ? ''
        : '${(entry.durationMillis / 1000).toStringAsFixed(1)}s';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.workflowName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              [
                _formatDate(entry.createdAt.toLocal()),
                if (duration.isNotEmpty) duration,
                if (entry.providerName.isNotEmpty) entry.providerName,
                if (entry.modelName.isNotEmpty) entry.modelName,
              ].join('  ·  '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (entry.stage != null) ...[
              const SizedBox(height: 10),
              Text(
                entry.stage!.label,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TextOutputBlock extends StatelessWidget {
  const _TextOutputBlock({required this.output});

  final RunOutput output;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    output.nodeTitle.isEmpty ? 'Text output' : output.nodeTitle,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: output.text));
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Copied')));
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ],
            ),
            SelectableText(output.text),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}
