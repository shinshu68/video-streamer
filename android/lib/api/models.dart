/// 一覧の要素の種類。docs/api.md の `type` に対応する。
enum EntryType { dir, video }

/// 一覧の1要素。[size] と [modified] は動画のときだけ持つ。
class Entry {
  const Entry({
    required this.type,
    required this.name,
    required this.path,
    this.size,
    this.modified,
  });

  factory Entry.fromJson(Map<String, dynamic> json) {
    final modified = json['modified'] as String?;
    return Entry(
      type: EntryType.values.byName(json['type'] as String),
      name: json['name'] as String,
      path: json['path'] as String,
      size: json['size'] as int?,
      modified: modified == null ? null : DateTime.parse(modified),
    );
  }

  final EntryType type;
  final String name;
  final String path;
  final int? size;
  final DateTime? modified;
}

/// `GET /api/list` のレスポンス。
class ListResult {
  const ListResult({required this.path, required this.entries});

  factory ListResult.fromJson(Map<String, dynamic> json) {
    return ListResult(
      path: json['path'] as String,
      entries: [
        for (final e in json['entries'] as List<dynamic>)
          Entry.fromJson(e as Map<String, dynamic>),
      ],
    );
  }

  final String path;
  final List<Entry> entries;
}
