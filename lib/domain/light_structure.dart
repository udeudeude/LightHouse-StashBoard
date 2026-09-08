enum StructureKind { stack, nest }

class LightStructure {
  const LightStructure({
    required this.id,
    required this.kind,
    required this.memberIds,
  });

  final String id;
  final StructureKind kind;
  final List<String> memberIds;

  LightStructure copyWith({StructureKind? kind, List<String>? memberIds}) {
    return LightStructure(
      id: id,
      kind: kind ?? this.kind,
      memberIds: List.unmodifiable(memberIds ?? this.memberIds),
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'kind': kind.name,
    'memberIds': memberIds,
  };

  factory LightStructure.fromJson(Map<String, Object?> json) => LightStructure(
    id: json['id']! as String,
    kind: StructureKind.values.byName(json['kind']! as String),
    memberIds: (json['memberIds']! as List).cast<String>(),
  );

  @override
  bool operator ==(Object other) =>
      other is LightStructure &&
      other.id == id &&
      other.kind == kind &&
      _sameMembers(other.memberIds, memberIds);

  @override
  int get hashCode => Object.hash(id, kind, Object.hashAll(memberIds));

  static bool _sameMembers(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i += 1) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
