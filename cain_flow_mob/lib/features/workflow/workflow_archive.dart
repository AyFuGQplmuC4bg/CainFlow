import 'dart:convert';

import '../../core/models/workflow_document.dart';

class WorkflowArchive {
  const WorkflowArchive({required this.name, required this.document});

  factory WorkflowArchive.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    return WorkflowArchive(
      name: json['name']?.toString() ?? 'Imported Workflow',
      document: data is Map
          ? WorkflowDocument.fromJson(Map<String, dynamic>.from(data))
          : WorkflowDocument.empty(),
    );
  }

  final String name;
  final WorkflowDocument document;

  Map<String, dynamic> toJson() {
    return {'name': name, 'data': document.toJson()};
  }
}

String exportWorkflowArchive(WorkflowArchive archive) {
  return const JsonEncoder.withIndent('  ').convert(archive.toJson());
}

WorkflowArchive importWorkflowArchive(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) {
    throw const FormatException('Workflow archive must be a JSON object.');
  }
  return WorkflowArchive.fromJson(Map<String, dynamic>.from(decoded));
}
