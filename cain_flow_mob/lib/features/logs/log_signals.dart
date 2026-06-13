import 'package:signals/signals.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  const LogEntry({
    required this.id,
    required this.level,
    required this.message,
    required this.createdAt,
    this.scope = '',
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      id: json['id']?.toString() ?? '',
      level: _levelFrom(json['level']),
      message: json['message']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      scope: json['scope']?.toString() ?? '',
    );
  }

  final String id;
  final LogLevel level;
  final String message;
  final DateTime createdAt;
  final String scope;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'level': level.name,
      'message': message,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (scope.isNotEmpty) 'scope': scope,
    };
  }
}

LogLevel _levelFrom(Object? value) {
  return switch (value?.toString()) {
    'warning' => LogLevel.warning,
    'error' => LogLevel.error,
    _ => LogLevel.info,
  };
}

class LogSignals {
  LogSignals({this.capacity = 200, this.onChanged});

  final int capacity;

  /// Optional hook invoked after the ring changes, used by the app to
  /// persist logs through a repository. Tests can leave this null.
  void Function(List<LogEntry> entries)? onChanged;

  final entries = signal<List<LogEntry>>(const []);

  late final hasErrors = computed(
    () => entries.value.any((entry) => entry.level == LogLevel.error),
  );

  void add(LogLevel level, String message, {String scope = ''}) {
    final now = DateTime.now().toUtc();
    final next = [
      LogEntry(
        id: '${now.microsecondsSinceEpoch}-${entries.value.length}',
        level: level,
        message: message,
        createdAt: now,
        scope: scope,
      ),
      ...entries.value,
    ];
    entries.value = next.take(capacity).toList();
    onChanged?.call(entries.value);
  }

  void clear() {
    entries.value = const [];
    onChanged?.call(entries.value);
  }

  /// Replaces all entries, keeping only the newest [capacity] items.
  void replaceAll(List<LogEntry> next) {
    entries.value = next.take(capacity).toList();
  }
}

final logSignals = LogSignals();
