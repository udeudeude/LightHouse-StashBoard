import 'light_element.dart';
import 'light_structure.dart';

class BoardState {
  BoardState({
    List<LightElement> elements = const [],
    List<LightStructure> structures = const [],
    this.title = 'Untitled Board',
  }) : elements = List.unmodifiable(elements),
       structures = List.unmodifiable(structures);

  static BoardState empty({String title = 'Untitled Board'}) =>
      BoardState(title: title);

  final List<LightElement> elements;
  final List<LightStructure> structures;
  final String title;

  LightElement? elementById(String id) {
    for (final element in elements) {
      if (element.id == id) return element;
    }
    return null;
  }

  LightStructure? structureForElement(String id) {
    for (final structure in structures) {
      if (structure.memberIds.contains(id)) return structure;
    }
    return null;
  }

  BoardState copyWith({
    List<LightElement>? elements,
    List<LightStructure>? structures,
    String? title,
  }) => BoardState(
    elements: elements ?? this.elements,
    structures: structures ?? this.structures,
    title: title ?? this.title,
  );

  BoardState add(LightElement element) =>
      copyWith(elements: [...elements, element]);

  BoardState remove(String id) {
    final nextStructures = <LightStructure>[];
    for (final structure in structures) {
      final members = structure.memberIds
          .where((member) => member != id)
          .toList();
      if (members.length >= 2) {
        nextStructures.add(structure.copyWith(memberIds: members));
      }
    }
    return copyWith(
      elements: elements.where((element) => element.id != id).toList(),
      structures: nextStructures,
    );
  }

  BoardState replace(LightElement replacement) => copyWith(
    elements: [
      for (final element in elements)
        if (element.id == replacement.id) replacement else element,
    ],
  );

  BoardState replaceMany(Iterable<LightElement> replacements) {
    final byId = {for (final element in replacements) element.id: element};
    return copyWith(
      elements: [for (final element in elements) byId[element.id] ?? element],
    );
  }

  BoardState upsertStructure(LightStructure replacement) => copyWith(
    structures: [
      for (final structure in structures)
        if (structure.id == replacement.id) replacement else structure,
      if (!structures.any((structure) => structure.id == replacement.id))
        replacement,
    ],
  );

  BoardState removeStructure(String id) => copyWith(
    structures: structures.where((structure) => structure.id != id).toList(),
  );

  Map<String, Object> toJson() => {
    'format': 'lighthouse-board',
    'version': 2,
    'title': title,
    'elements': elements.map((element) => element.toJson()).toList(),
    'structures': structures.map((structure) => structure.toJson()).toList(),
  };

  factory BoardState.fromJson(Map<String, Object?> json) {
    if (json['format'] != 'lighthouse-board') {
      throw const FormatException('Unsupported LightHouse board document.');
    }

    final version = json['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('Unsupported LightHouse board version.');
    }

    final rawElements = json['elements']! as List;
    final elements = rawElements
        .map(
          (entry) =>
              LightElement.fromJson((entry as Map).cast<String, Object?>()),
        )
        .toList();

    if (version == 1) {
      return BoardState(elements: elements);
    }

    final rawStructures = (json['structures'] as List?) ?? const [];
    return BoardState(
      title: (json['title'] as String?) ?? 'Untitled Board',
      elements: elements,
      structures: rawStructures
          .map(
            (entry) =>
                LightStructure.fromJson((entry as Map).cast<String, Object?>()),
          )
          .where(
            (structure) => structure.memberIds.every(
              (id) => elements.any((element) => element.id == id),
            ),
          )
          .toList(),
    );
  }
}
