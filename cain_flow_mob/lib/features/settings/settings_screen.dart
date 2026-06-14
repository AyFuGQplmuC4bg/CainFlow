import 'package:flutter/material.dart';

import '../../core/network/provider_client.dart';
import '../../core/storage/mmkv_local_kv_store.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/locale_signal.dart';
import '../logs/log_signals.dart';
import '../workbench/workbench_signals.dart';
import '../workbench/workbench_workflow_mapper.dart';
import '../workflow/workflow_archive.dart';
import '../workflow/workflow_repository.dart';
import 'provider_health_checker.dart';
import 'provider_settings.dart';

class SettingsScreen extends StatefulWidget {
  SettingsScreen({
    super.key,
    this.repository,
    LogSignals? logs,
    WorkbenchSignals? workbench,
    this.workflowRepository,
  }) : logs = logs ?? logSignals,
       workbench = workbench ?? workbenchSignals;

  final ProviderSettingsRepository? repository;
  final LogSignals logs;
  final WorkbenchSignals workbench;
  final WorkflowRepository? workflowRepository;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late ProviderSettingsRepository _repository;
  late ProviderSettings _settings;
  final TextEditingController _importController = TextEditingController();
  String _archivePreview = '';
  String _archiveError = '';

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? defaultProviderSettingsRepository();
    _settings = _repository.load();
  }

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  void _persist(ProviderSettings next) {
    setState(() => _settings = next);
    _repository.save(next);
  }

  // Placeholder anchors replaced by Edit appends below.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SizedBox(
        height: 560,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text(context.l10n.settingsTitle, style: theme.textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: context.l10n.closeSettings,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildProvidersSection(theme),
            const SizedBox(height: 20),
            _buildModelsSection(theme),
            const SizedBox(height: 20),
            _buildRuntimeSection(theme),
            const SizedBox(height: 20),
            _buildLanguageSection(theme),
            const SizedBox(height: 20),
            _buildArchiveSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildProvidersSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(context.l10n.providers, style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _editProvider(),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.addProvider),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_settings.providers.isEmpty)
          _EmptySettingsLine(label: context.l10n.noProviders)
        else
          for (final provider in _settings.providers)
            _SettingTile(
              icon: Icons.key_outlined,
              title: provider.name,
              subtitle: '${provider.protocol.name} - ${provider.maskedApiKey}',
              onEdit: () => _editProvider(existing: provider),
              onDelete: () => _deleteProvider(provider),
            ),
      ],
    );
  }

  Widget _buildModelsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(context.l10n.models, style: theme.textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _editModel(),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.addModel),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_settings.models.isEmpty)
          _EmptySettingsLine(label: context.l10n.noModels)
        else
          for (final model in _settings.models)
            _SettingTile(
              icon: Icons.memory_outlined,
              title: model.name,
              subtitle: '${model.taskType.name} - ${model.modelId}',
              onEdit: () => _editModel(existing: model),
              onDelete: () => _deleteModel(model),
            ),
      ],
    );
  }

  Widget _buildRuntimeSection(ThemeData theme) {
    final runtime = _settings.runtime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.runtimeSection, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('runtime-timeout-field'),
                initialValue: runtime.requestTimeoutSeconds.toString(),
                decoration: InputDecoration(
                  labelText: context.l10n.timeoutLabel,
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed == null) return;
                  _persist(
                    _settings.copyWith(
                      runtime: runtime.copyWith(requestTimeoutSeconds: parsed),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('runtime-retry-field'),
                initialValue: runtime.retryCount.toString(),
                decoration: InputDecoration(labelText: context.l10n.retryCountLabel),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed == null) return;
                  _persist(
                    _settings.copyWith(
                      runtime: runtime.copyWith(retryCount: parsed),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const Key('runtime-async-poll-field'),
                initialValue: runtime.asyncPollIntervalSeconds.toString(),
                decoration: InputDecoration(
                  labelText: context.l10n.asyncPollLabel,
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed == null) return;
                  _persist(
                    _settings.copyWith(
                      runtime:
                          runtime.copyWith(asyncPollIntervalSeconds: parsed),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                key: const Key('runtime-async-timeout-field'),
                initialValue: runtime.asyncTimeoutSeconds.toString(),
                decoration: InputDecoration(
                  labelText: context.l10n.asyncTimeoutLabel,
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed == null) return;
                  _persist(
                    _settings.copyWith(
                      runtime: runtime.copyWith(asyncTimeoutSeconds: parsed),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildActiveModelDropdown(
          label: context.l10n.activeChatModel,
          taskType: ModelTaskType.chat,
          selectedId: runtime.activeChatModelId,
          onChanged: (value) => _persist(
            _settings.copyWith(
              runtime: runtime.copyWith(activeChatModelId: value ?? ''),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildActiveModelDropdown(
          label: context.l10n.activeImageModel,
          taskType: ModelTaskType.image,
          selectedId: runtime.activeImageModelId,
          onChanged: (value) => _persist(
            _settings.copyWith(
              runtime: runtime.copyWith(activeImageModelId: value ?? ''),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          key: const Key('runtime-completion-sound-switch'),
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.completionSoundLabel),
          value: runtime.completionSoundEnabled,
          onChanged: (value) => _persist(
            _settings.copyWith(
              runtime: runtime.copyWith(completionSoundEnabled: value),
            ),
          ),
        ),
        SwitchListTile(
          key: const Key('runtime-completion-haptics-switch'),
          contentPadding: EdgeInsets.zero,
          title: Text(context.l10n.completionHapticsLabel),
          value: runtime.completionHapticsEnabled,
          onChanged: (value) => _persist(
            _settings.copyWith(
              runtime: runtime.copyWith(completionHapticsEnabled: value),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveModelDropdown({
    required String label,
    required ModelTaskType taskType,
    required String selectedId,
    required ValueChanged<String?> onChanged,
  }) {
    final candidates = _settings.models
        .where((model) => model.taskType == taskType)
        .toList();
    final value = candidates.any((model) => model.id == selectedId)
        ? selectedId
        : null;
    return DropdownButtonFormField<String?>(
      key: Key('active-${taskType.name}-model'),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(context.l10n.noneOption)),
        for (final model in candidates)
          DropdownMenuItem<String?>(value: model.id, child: Text(model.name)),
      ],
      onChanged: onChanged,
    );
  }

  Widget _buildLanguageSection(ThemeData theme) {
    final l10n = context.l10n;
    final current = localeSignal.value?.languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.language, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          key: const Key('language-picker'),
          initialValue: current,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(l10n.langSystem)),
            DropdownMenuItem<String?>(value: 'en', child: Text(l10n.langEnglish)),
            DropdownMenuItem<String?>(value: 'zh', child: Text(l10n.langChinese)),
          ],
          onChanged: (code) => setLocale(code == null ? null : Locale(code)),
        ),
      ],
    );
  }

  Widget _buildArchiveSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.workflowJson, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _exportCurrentGraph,
              icon: const Icon(Icons.download_outlined),
              label: Text(context.l10n.exportGraph),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('workflow-import-field'),
          controller: _importController,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: context.l10n.pasteJsonLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const Key('workflow-import-button'),
          onPressed: _importWorkflow,
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(context.l10n.importIntoWorkbench),
        ),
        if (_archiveError.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _archiveError,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (_archivePreview.isNotEmpty) ...[
          const SizedBox(height: 12),
          SelectableText(_archivePreview, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }

  void _exportCurrentGraph() {
    final document = workbenchSignalsToWorkflow(widget.workbench);
    final text = exportWorkflowArchive(
      WorkflowArchive(
        name: widget.workbench.activeWorkflowName.value,
        document: document,
      ),
    );
    setState(() {
      _archivePreview = text;
      _archiveError = '';
    });
    widget.logs.add(
      LogLevel.info,
      'Workflow graph exported',
      scope: 'settings',
    );
  }

  void _importWorkflow() {
    final source = _importController.text.trim();
    if (source.isEmpty) {
      setState(() => _archiveError = context.l10n.pasteFirst);
      return;
    }
    try {
      final archive = importWorkflowArchive(source);
      applyWorkflowToWorkbench(
        widget.workbench,
        archive.document,
        name: archive.name,
      );
      (widget.workflowRepository ?? _defaultWorkflowRepository()).saveWorkflow(
        _slugFor(archive.name),
        archive.document,
      );
      setState(() {
        _archiveError = '';
        _archivePreview = '';
      });
      widget.logs.add(
        LogLevel.info,
        'Workflow imported: ${archive.name}',
        scope: 'settings',
      );
      if (mounted) Navigator.of(context).maybePop();
    } on FormatException catch (error) {
      setState(() => _archiveError = context.l10n.invalidWorkflowJson(error.message));
      widget.logs.add(
        LogLevel.error,
        'Workflow import failed: invalid JSON',
        scope: 'settings',
      );
    } catch (_) {
      setState(() => _archiveError = context.l10n.couldNotImport);
      widget.logs.add(
        LogLevel.error,
        'Workflow import failed',
        scope: 'settings',
      );
    }
  }

  void _deleteProvider(ProviderConfig provider) {
    _persist(
      _settings.copyWith(
        providers: _settings.providers
            .where((item) => item.id != provider.id)
            .toList(),
      ),
    );
    widget.logs.add(
      LogLevel.info,
      'Provider removed: ${provider.name}',
      scope: 'settings',
    );
  }

  void _deleteModel(ModelConfig model) {
    _persist(
      _settings.copyWith(
        models: _settings.models
            .where((item) => item.id != model.id)
            .toList(),
      ),
    );
    widget.logs.add(
      LogLevel.info,
      'Model removed: ${model.name}',
      scope: 'settings',
    );
  }

  Future<void> _editProvider({ProviderConfig? existing}) async {
    final result = await showDialog<ProviderConfig>(
      context: context,
      builder: (context) => _ProviderEditDialog(existing: existing),
    );
    if (result == null) return;
    final providers = [..._settings.providers];
    final index = providers.indexWhere((item) => item.id == result.id);
    if (index >= 0) {
      providers[index] = result;
    } else {
      providers.add(result);
    }
    _persist(_settings.copyWith(providers: providers));
    widget.logs.add(
      LogLevel.info,
      'Provider saved: ${result.name}',
      scope: 'settings',
    );
  }

  Future<void> _editModel({ModelConfig? existing}) async {
    final result = await showDialog<ModelConfig>(
      context: context,
      builder: (context) => _ModelEditDialog(
        existing: existing,
        providers: _settings.providers,
      ),
    );
    if (result == null) return;
    final models = [..._settings.models];
    final index = models.indexWhere((item) => item.id == result.id);
    if (index >= 0) {
      models[index] = result;
    } else {
      models.add(result);
    }
    _persist(_settings.copyWith(models: models));
    widget.logs.add(
      LogLevel.info,
      'Model saved: ${result.name}',
      scope: 'settings',
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onEdit,
    this.onDelete,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEdit != null)
            IconButton(
              tooltip: context.l10n.editTooltip,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
          if (onDelete != null)
            IconButton(
              tooltip: context.l10n.deleteTooltip,
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _EmptySettingsLine extends StatelessWidget {
  const _EmptySettingsLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

ProviderSettingsRepository defaultProviderSettingsRepository() {
  return ProviderSettingsRepository(store: MmkvLocalKvStore());
}

WorkflowRepository _defaultWorkflowRepository() {
  return WorkflowRepository(store: MmkvLocalKvStore());
}

String _slugFor(String name) {
  final slug = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'imported-workflow' : slug;
}

String _newId(String prefix) {
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}';
}

class _ProviderEditDialog extends StatefulWidget {
  const _ProviderEditDialog({this.existing});

  final ProviderConfig? existing;

  @override
  State<_ProviderEditDialog> createState() => _ProviderEditDialogState();
}

class _ProviderEditDialogState extends State<_ProviderEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _endpoint;
  late final TextEditingController _apiKey;
  late ModelProtocol _protocol;
  String? _testMessage;
  bool _testOk = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _endpoint = TextEditingController(text: existing?.endpoint ?? '');
    _apiKey = TextEditingController(text: existing?.apiKey ?? '');
    _protocol = existing?.protocol ?? ModelProtocol.openai;
  }

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testMessage = 'Testing…';
      _testOk = false;
    });
    final provider = ProviderConfig(
      id: widget.existing?.id ?? 'probe',
      name: _name.text.trim(),
      protocol: _protocol,
      apiKey: _apiKey.text.trim(),
      endpoint: _endpoint.text.trim(),
    );
    final checker = ProviderHealthChecker(client: DartIoProviderClient());
    final result = await checker.check(provider);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = result.ok;
      _testMessage = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.existing == null ? context.l10n.addProviderTitle : context.l10n.editProviderTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('provider-name-field'),
              controller: _name,
              decoration: InputDecoration(labelText: context.l10n.nameLabel),
            ),
            TextField(
              key: const Key('provider-endpoint-field'),
              controller: _endpoint,
              decoration: InputDecoration(labelText: context.l10n.endpointLabel),
            ),
            TextField(
              key: const Key('provider-apikey-field'),
              controller: _apiKey,
              obscureText: true,
              decoration: InputDecoration(labelText: context.l10n.apiKeyLabel),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ModelProtocol>(
              key: const Key('provider-protocol-field'),
              initialValue: _protocol,
              decoration: InputDecoration(labelText: context.l10n.protocolLabel),
              items: const [
                DropdownMenuItem(
                  value: ModelProtocol.openai,
                  child: Text('openai'),
                ),
                DropdownMenuItem(
                  value: ModelProtocol.google,
                  child: Text('google'),
                ),
                DropdownMenuItem(
                  value: ModelProtocol.newApiImageAsync,
                  child: Text('newApiImageAsync'),
                ),
              ],
              onChanged: (value) => setState(
                () => _protocol = value ?? ModelProtocol.openai,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('provider-test-button'),
                icon: const Icon(Icons.wifi_tethering),
                label: Text(context.l10n.testConnection),
                onPressed: _testConnection,
              ),
            ),
            if (_testMessage != null)
              Text(
                _testMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _testOk
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const Key('provider-save-button'),
          onPressed: () {
            Navigator.of(context).pop(
              ProviderConfig(
                id: widget.existing?.id ?? _newId('prov'),
                name: _name.text.trim(),
                protocol: _protocol,
                apiKey: _apiKey.text.trim(),
                endpoint: _endpoint.text.trim(),
                autoComplete: widget.existing?.autoComplete ?? true,
              ),
            );
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}

class _ModelEditDialog extends StatefulWidget {
  const _ModelEditDialog({this.existing, required this.providers});

  final ModelConfig? existing;
  final List<ProviderConfig> providers;

  @override
  State<_ModelEditDialog> createState() => _ModelEditDialogState();
}

class _ModelEditDialogState extends State<_ModelEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _modelId;
  late ModelTaskType _taskType;
  late ModelProtocol _protocol;
  late List<String> _providerIds;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _modelId = TextEditingController(text: existing?.modelId ?? '');
    _taskType = existing?.taskType ?? ModelTaskType.chat;
    _protocol = existing?.protocol ?? ModelProtocol.openai;
    _providerIds = [...?existing?.providerIds];
  }

  @override
  void dispose() {
    _name.dispose();
    _modelId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedProvider = _providerIds.isNotEmpty ? _providerIds.first : null;
    final providerValue =
        widget.providers.any((item) => item.id == selectedProvider)
        ? selectedProvider
        : null;
    return AlertDialog(
      title: Text(widget.existing == null ? context.l10n.addModelTitle : context.l10n.editModelTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('model-name-field'),
              controller: _name,
              decoration: InputDecoration(labelText: context.l10n.nameLabel),
            ),
            TextField(
              key: const Key('model-id-field'),
              controller: _modelId,
              decoration: InputDecoration(labelText: context.l10n.modelIdLabel),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ModelTaskType>(
              key: const Key('model-task-field'),
              initialValue: _taskType,
              decoration: InputDecoration(labelText: context.l10n.taskTypeLabel),
              items: const [
                DropdownMenuItem(
                  value: ModelTaskType.chat,
                  child: Text('chat'),
                ),
                DropdownMenuItem(
                  value: ModelTaskType.image,
                  child: Text('image'),
                ),
                DropdownMenuItem(
                  value: ModelTaskType.video,
                  child: Text('video'),
                ),
              ],
              onChanged: (value) => setState(
                () => _taskType = value ?? ModelTaskType.chat,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ModelProtocol>(
              key: const Key('model-protocol-field'),
              initialValue: _protocol,
              decoration: InputDecoration(labelText: context.l10n.protocolLabel),
              items: const [
                DropdownMenuItem(
                  value: ModelProtocol.openai,
                  child: Text('openai'),
                ),
                DropdownMenuItem(
                  value: ModelProtocol.google,
                  child: Text('google'),
                ),
                DropdownMenuItem(
                  value: ModelProtocol.newApiImageAsync,
                  child: Text('newApiImageAsync'),
                ),
              ],
              onChanged: (value) => setState(
                () => _protocol = value ?? ModelProtocol.openai,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const Key('model-provider-field'),
              initialValue: providerValue,
              decoration: InputDecoration(labelText: context.l10n.providerLabel),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(context.l10n.noneOption),
                ),
                for (final provider in widget.providers)
                  DropdownMenuItem<String?>(
                    value: provider.id,
                    child: Text(provider.name),
                  ),
              ],
              onChanged: (value) => setState(
                () => _providerIds = value == null ? [] : [value],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: const Key('model-save-button'),
          onPressed: () {
            Navigator.of(context).pop(
              ModelConfig(
                id: widget.existing?.id ?? _newId('model'),
                name: _name.text.trim(),
                modelId: _modelId.text.trim(),
                taskType: _taskType,
                protocol: _protocol,
                providerIds: _providerIds,
              ),
            );
          },
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
