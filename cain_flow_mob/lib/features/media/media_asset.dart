class MediaAsset {
  const MediaAsset({
    required this.id,
    required this.workflowId,
    required this.fileName,
    required this.relativePath,
    required this.mimeType,
    required this.byteLength,
    required this.createdAt,
    this.thumbnailRelativePath = '',
    this.width,
    this.height,
    this.extra = const {},
  });

  factory MediaAsset.fromJson(Map<String, dynamic> json) {
    final extra = Map<String, dynamic>.from(json)
      ..remove('id')
      ..remove('workflowId')
      ..remove('fileName')
      ..remove('relativePath')
      ..remove('mimeType')
      ..remove('byteLength')
      ..remove('createdAt')
      ..remove('thumbnailRelativePath')
      ..remove('width')
      ..remove('height');
    return MediaAsset(
      id: json['id']?.toString() ?? '',
      workflowId: json['workflowId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      relativePath: json['relativePath']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      byteLength: _intFrom(json['byteLength']),
      createdAt: _dateFrom(json['createdAt']),
      thumbnailRelativePath: json['thumbnailRelativePath']?.toString() ?? '',
      width: _nullableIntFrom(json['width']),
      height: _nullableIntFrom(json['height']),
      extra: extra,
    );
  }

  final String id;
  final String workflowId;
  final String fileName;
  final String relativePath;
  final String mimeType;
  final int byteLength;
  final DateTime createdAt;
  final String thumbnailRelativePath;
  final int? width;
  final int? height;
  final Map<String, dynamic> extra;

  MediaAsset copyWith({
    String? thumbnailRelativePath,
    int? width,
    int? height,
  }) {
    return MediaAsset(
      id: id,
      workflowId: workflowId,
      fileName: fileName,
      relativePath: relativePath,
      mimeType: mimeType,
      byteLength: byteLength,
      createdAt: createdAt,
      thumbnailRelativePath:
          thumbnailRelativePath ?? this.thumbnailRelativePath,
      width: width ?? this.width,
      height: height ?? this.height,
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...extra,
      'id': id,
      'workflowId': workflowId,
      'fileName': fileName,
      'relativePath': relativePath,
      'mimeType': mimeType,
      'byteLength': byteLength,
      'createdAt': createdAt.toIso8601String(),
      if (thumbnailRelativePath.isNotEmpty)
        'thumbnailRelativePath': thumbnailRelativePath,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    };
  }
}

int _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _nullableIntFrom(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime _dateFrom(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
