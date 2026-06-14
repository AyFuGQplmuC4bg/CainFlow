import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../core/models/workflow_document.dart';
import '../settings/provider_settings.dart';
import 'workflow_repository.dart';

/// Packs and restores a portable config bundle (providers, models, runtime
/// settings, and saved workflows) as a ZIP. Pure bytes in / bytes out so it
/// can be driven from a file picker or share sheet and unit-tested.
class ConfigArchive {
  ConfigArchive({
    required this.settingsRepository,
    required this.workflowRepository,
  });

  final ProviderSettingsRepository settingsRepository;
  final WorkflowRepository workflowRepository;

  static const settingsEntry = 'settings.json';
  static const workflowsDir = 'workflows/';

  /// Builds a ZIP containing settings.json and one JSON per workflow.
  Uint8List export() {
    final archive = Archive();

    final settingsBytes = utf8.encode(
      jsonEncode(settingsRepository.load().toJson()),
    );
    archive.addFile(
      ArchiveFile(settingsEntry, settingsBytes.length, settingsBytes),
    );

    for (final id in workflowRepository.listWorkflowIds()) {
      final doc = workflowRepository.loadWorkflow(id);
      if (doc == null) continue;
      final bytes = utf8.encode(jsonEncode(doc.toJson()));
      archive.addFile(
        ArchiveFile('$workflowsDir$id.json', bytes.length, bytes),
      );
    }

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  /// Restores a ZIP produced by [export]. Settings replace current settings;
  /// workflows are merged (overwriting same ids). Returns counts for logging.
  ConfigImportResult import(Uint8List zipBytes) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    var workflows = 0;
    var settingsImported = false;

    for (final file in archive.files) {
      if (!file.isFile) continue;
      final content = utf8.decode(file.content as List<int>);
      if (file.name == settingsEntry) {
        final decoded = jsonDecode(content);
        if (decoded is Map) {
          settingsRepository.save(
            ProviderSettings.fromJson(Map<String, dynamic>.from(decoded)),
          );
          settingsImported = true;
        }
      } else if (file.name.startsWith(workflowsDir) &&
          file.name.endsWith('.json')) {
        final id = file.name
            .substring(workflowsDir.length, file.name.length - 5);
        final decoded = jsonDecode(content);
        if (decoded is Map && id.isNotEmpty) {
          workflowRepository.saveWorkflow(
            id,
            WorkflowDocument.fromJson(Map<String, dynamic>.from(decoded)),
          );
          workflows += 1;
        }
      }
    }

    return ConfigImportResult(
      settingsImported: settingsImported,
      workflowsImported: workflows,
    );
  }
}

class ConfigImportResult {
  const ConfigImportResult({
    required this.settingsImported,
    required this.workflowsImported,
  });

  final bool settingsImported;
  final int workflowsImported;
}
