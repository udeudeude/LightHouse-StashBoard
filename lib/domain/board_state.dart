import 'light_element.dart';

class BoardState {
  BoardState({List<LightElement> elements = const []})
    : elements = List.unmodifiable(elements);

  static BoardState empty() => BoardState();

  final List<LightElement> elements;

  LightElement? elementById(String id) {
    for (final element in elements) {
      if (element.id == id) return element;
    }
    return null;
  }

  BoardState add(LightElement element) =>
      BoardState(elements: [...elements, element]);

  BoardState remove(String id) => BoardState(
    elements: elements.where((element) => element.id != id).toList(),
  );

  BoardState replace(LightElement replacement) => BoardState(
    elements: [
      for (final element in elements)
        if (element.id == replacement.id) replacement else element,
    ],
  );

  Map<String, Object> toJson() => {
    'format': 'lighthouse-board',
    'version': 1,
    'elements': elements.map((element) => element.toJson()).toList(),
  };

  factory BoardState.fromJson(Map<String, Object?> json) {
    if (json['format'] != 'lighthouse-board' || json['version'] != 1) {
      throw const FormatException('Unsupported LightHouse board document.');
    }
    final rawElements = json['elements']! as List;
    return BoardState(
      elements: rawElements
          .map(
            (entry) =>
                LightElement.fromJson((entry as Map).cast<String, Object?>()),
          )
          .toList(),
    );
  }
}
