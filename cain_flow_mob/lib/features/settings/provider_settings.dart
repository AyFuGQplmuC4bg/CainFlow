import 'dart:convert';

import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';

enum ModelProtocol { openai, google, newApiImageAsync }

enum ModelTaskType { chat, image, video }

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.name,
    required this.protocol,
    required this.apiKey,
    required this.endpoint,
    this.autoComplete = true,
  });

  factory ProviderConfig.fromJson(Map<String, dynamic> json) {
    return ProviderConfig(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      protocol: _protocolFrom(json['protocol'] ?? json['type']),
      apiKey: json['apiKey']?.toString() ?? json['apikey']?.toString() ?? '',
      endpoint: json['endpoint']?.toString() ?? '',
      autoComplete: json['autoComplete'] is bool
          ? json['autoComplete'] as bool
          : true,
    );
  }

  final String id;
  final String name;
  final ModelProtocol protocol;
  final String apiKey;
  final String endpoint;
  final bool autoComplete;

  String get maskedApiKey => maskSecret(apiKey);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'protocol': protocol.name,
      'apiKey': apiKey,
      'endpoint': endpoint,
      'autoComplete': autoComplete,
    };
  }
}

class ModelConfig {
  const ModelConfig({
    required this.id,
    required this.name,
    required this.modelId,
    required this.taskType,
    required this.protocol,
    required this.providerIds,
  });

  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    final providerIds = json['providerIds'] is List
        ? (json['providerIds'] as List).map((item) => item.toString()).toList()
        : [if (json['providerId'] != null) json['providerId'].toString()];
    return ModelConfig(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      modelId: json['modelId']?.toString() ?? '',
      taskType: _taskTypeFrom(json['taskType']),
      protocol: _protocolFrom(json['protocol']),
      providerIds: providerIds.where((id) => id.isNotEmpty).toList(),
    );
  }

  final String id;
  final String name;
  final String modelId;
  final ModelTaskType taskType;
  final ModelProtocol protocol;
  final List<String> providerIds;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'modelId': modelId,
      'taskType': taskType.name,
      'protocol': protocol.name,
      'providerIds': providerIds,
    };
  }
}

class RuntimeSettings {
  const RuntimeSettings({
    this.requestTimeoutSeconds = 60,
    this.retryCount = 0,
    this.activeChatModelId = '',
    this.activeImageModelId = '',
    this.asyncPollIntervalSeconds = 2,
    this.asyncTimeoutSeconds = 300,
    this.maxConcurrency = 1,
    this.completionSoundEnabled = true,
    this.completionHapticsEnabled = true,
  });

  factory RuntimeSettings.defaults() => const RuntimeSettings();

  factory RuntimeSettings.fromJson(Map<String, dynamic> json) {
    return RuntimeSettings(
      requestTimeoutSeconds: _intFrom(json['requestTimeoutSeconds'], 60),
      retryCount: _intFrom(json['retryCount'], 0),
      activeChatModelId: json['activeChatModelId']?.toString() ?? '',
      activeImageModelId: json['activeImageModelId']?.toString() ?? '',
      asyncPollIntervalSeconds: _intFrom(json['asyncPollIntervalSeconds'], 2),
      asyncTimeoutSeconds: _intFrom(json['asyncTimeoutSeconds'], 300),
      maxConcurrency: _intFrom(json['maxConcurrency'], 1),
      completionSoundEnabled: _boolFrom(json['completionSoundEnabled'], true),
      completionHapticsEnabled:
          _boolFrom(json['completionHapticsEnabled'], true),
    );
  }

  final int requestTimeoutSeconds;
  final int retryCount;
  final String activeChatModelId;
  final String activeImageModelId;
  final int asyncPollIntervalSeconds;
  final int asyncTimeoutSeconds;
  final int maxConcurrency;

  /// Play a sound when a workflow run finishes.
  final bool completionSoundEnabled;

  /// Vibrate (haptic feedback) when a workflow run finishes.
  final bool completionHapticsEnabled;

  RuntimeSettings copyWith({
    int? requestTimeoutSeconds,
    int? retryCount,
    String? activeChatModelId,
    String? activeImageModelId,
    int? asyncPollIntervalSeconds,
    int? asyncTimeoutSeconds,
    int? maxConcurrency,
    bool? completionSoundEnabled,
    bool? completionHapticsEnabled,
  }) {
    return RuntimeSettings(
      requestTimeoutSeconds:
          requestTimeoutSeconds ?? this.requestTimeoutSeconds,
      retryCount: retryCount ?? this.retryCount,
      activeChatModelId: activeChatModelId ?? this.activeChatModelId,
      activeImageModelId: activeImageModelId ?? this.activeImageModelId,
      asyncPollIntervalSeconds:
          asyncPollIntervalSeconds ?? this.asyncPollIntervalSeconds,
      asyncTimeoutSeconds: asyncTimeoutSeconds ?? this.asyncTimeoutSeconds,
      maxConcurrency: maxConcurrency ?? this.maxConcurrency,
      completionSoundEnabled:
          completionSoundEnabled ?? this.completionSoundEnabled,
      completionHapticsEnabled:
          completionHapticsEnabled ?? this.completionHapticsEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'requestTimeoutSeconds': requestTimeoutSeconds,
      'retryCount': retryCount,
      'activeChatModelId': activeChatModelId,
      'activeImageModelId': activeImageModelId,
      'asyncPollIntervalSeconds': asyncPollIntervalSeconds,
      'asyncTimeoutSeconds': asyncTimeoutSeconds,
      'maxConcurrency': maxConcurrency,
      'completionSoundEnabled': completionSoundEnabled,
      'completionHapticsEnabled': completionHapticsEnabled,
    };
  }
}

class ProviderSettings {
  const ProviderSettings({
    required this.providers,
    required this.models,
    this.runtime = const RuntimeSettings(),
  });

  factory ProviderSettings.empty() {
    return const ProviderSettings(providers: [], models: []);
  }

  factory ProviderSettings.fromJson(Map<String, dynamic> json) {
    final runtimeJson = json['runtime'];
    return ProviderSettings(
      providers: _listOfMaps(json['providers'])
          .map(ProviderConfig.fromJson)
          .where((provider) => provider.id.isNotEmpty)
          .toList(),
      models: _listOfMaps(json['models'])
          .map(ModelConfig.fromJson)
          .where((model) => model.id.isNotEmpty)
          .toList(),
      runtime: runtimeJson is Map
          ? RuntimeSettings.fromJson(Map<String, dynamic>.from(runtimeJson))
          : RuntimeSettings.defaults(),
    );
  }

  final List<ProviderConfig> providers;
  final List<ModelConfig> models;
  final RuntimeSettings runtime;

  ProviderSettings copyWith({
    List<ProviderConfig>? providers,
    List<ModelConfig>? models,
    RuntimeSettings? runtime,
  }) {
    return ProviderSettings(
      providers: providers ?? this.providers,
      models: models ?? this.models,
      runtime: runtime ?? this.runtime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'providers': providers.map((provider) => provider.toJson()).toList(),
      'models': models.map((model) => model.toJson()).toList(),
      'runtime': runtime.toJson(),
    };
  }
}

class ProviderSettingsRepository {
  const ProviderSettingsRepository({required this.store});

  final LocalKvStore store;

  ProviderSettings load() {
    final raw = store.getString(StorageKeys.providerSettings);
    if (raw == null || raw.isEmpty) return ProviderSettings.empty();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return ProviderSettings.empty();
      return ProviderSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return ProviderSettings.empty();
    }
  }

  bool save(ProviderSettings settings) {
    return store.setString(
      StorageKeys.providerSettings,
      jsonEncode(settings.toJson()),
    );
  }
}

String maskSecret(String value) {
  final secret = value.trim();
  if (secret.isEmpty) return '';
  if (secret.length <= 8) return '***';
  final prefixLength = secret.startsWith('sk-') ? 3 : 4;
  return '${secret.substring(0, prefixLength)}...'
      '${secret.substring(secret.length - 4)}';
}

int _intFrom(Object? value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

bool _boolFrom(Object? value, bool fallback) {
  if (value is bool) return value;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v == 'true') return true;
    if (v == 'false') return false;
  }
  return fallback;
}

ModelProtocol _protocolFrom(Object? value) {
  return switch (value?.toString()) {
    'google' => ModelProtocol.google,
    'newApiImageAsync' => ModelProtocol.newApiImageAsync,
    _ => ModelProtocol.openai,
  };
}

ModelTaskType _taskTypeFrom(Object? value) {
  return switch (value?.toString()) {
    'image' => ModelTaskType.image,
    'video' => ModelTaskType.video,
    _ => ModelTaskType.chat,
  };
}

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
