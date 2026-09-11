from pathlib import Path

Path('lib/domain/board_underlay.dart').write_text('''enum BoardUnderlay {
  none(0, 0),
  grid3x3(3, 3),
  grid3x4(3, 4),
  grid4x4(4, 4),
  grid5x5(5, 5),
  grid5x6(5, 6),
  martianChess2(4, 8),
  chess8x8(8, 8);

  const BoardUnderlay(this.columns, this.rows);

  final int columns;
  final int rows;

  bool get isVisible => columns > 0 && rows > 0;

  bool get isChessLike =>
      this == BoardUnderlay.martianChess2 ||
      this == BoardUnderlay.chess8x8;

  static BoardUnderlay fromName(Object? value) {
    if (value is! String) return BoardUnderlay.none;
    for (final underlay in BoardUnderlay.values) {
      if (underlay.name == value) return underlay;
    }
    return BoardUnderlay.none;
  }
}
''')

path = Path('lib/domain/board_state.dart')
text = path.read_text()
if "import 'board_underlay.dart';" not in text:
    text = text.replace("import 'light_element.dart';\n", "import 'board_underlay.dart';\nimport 'light_element.dart';\n", 1)
text = text.replace("    List<LightStructure> structures = const [],\n    this.title = 'Untitled Board',\n  }) : elements = List.unmodifiable(elements),", "    List<LightStructure> structures = const [],\n    this.title = 'Untitled Board',\n    this.underlay = BoardUnderlay.none,\n  }) : elements = List.unmodifiable(elements),", 1)
text = text.replace("  final List<LightStructure> structures;\n  final String title;\n", "  final List<LightStructure> structures;\n  final String title;\n  final BoardUnderlay underlay;\n", 1)
text = text.replace("    List<LightStructure>? structures,\n    String? title,\n  }) => BoardState(\n    elements: elements ?? this.elements,\n    structures: structures ?? this.structures,\n    title: title ?? this.title,\n  );", "    List<LightStructure>? structures,\n    String? title,\n    BoardUnderlay? underlay,\n  }) => BoardState(\n    elements: elements ?? this.elements,\n    structures: structures ?? this.structures,\n    title: title ?? this.title,\n    underlay: underlay ?? this.underlay,\n  );", 1)
text = text.replace("    'version': 2,\n    'title': title,\n    'elements': elements.map((element) => element.toJson()).toList(),", "    'version': 3,\n    'title': title,\n    'underlay': underlay.name,\n    'elements': elements.map((element) => element.toJson()).toList(),", 1)
text = text.replace("    if (version != 1 && version != 2) {", "    if (version != 1 && version != 2 && version != 3) {", 1)
text = text.replace("      title: (json['title'] as String?) ?? 'Untitled Board',\n      elements: elements,", "      title: (json['title'] as String?) ?? 'Untitled Board',\n      underlay: version == 3\n          ? BoardUnderlay.fromName(json['underlay'])\n          : BoardUnderlay.none,\n      elements: elements,", 1)
path.write_text(text)

path = Path('lib/application/board_controller.dart')
text = path.read_text()
if "import '../domain/board_underlay.dart';" not in text:
    text = text.replace("import '../domain/board_state.dart';\n", "import '../domain/board_state.dart';\nimport '../domain/board_underlay.dart';\n", 1)
text = text.replace("      _replace(\n        current,\n        current.copyWith(\n          pose: PyramidPose.flat,", "      _commitPoseChange(\n        current,\n        current.copyWith(\n          pose: PyramidPose.flat,", 1)
text = text.replace("    _replace(\n      current,\n      current.copyWith(\n        pose: PyramidPose.upright,", "    _commitPoseChange(\n      current,\n      current.copyWith(\n        pose: PyramidPose.upright,", 1)
old_begin = '''  void beginTransform(LightElement element) {
    final current = _state.elementById(element.id);
    if (current == null) return;
    final structure = _state.structureForElement(current.id);
    _transformingIds = structure == null
        ? {current.id}
        : structure.memberIds.toSet();
    _transformBeforeState = _state;
  }
'''
new_begin = '''  void beginTransform(LightElement element) {
    final current = _state.elementById(element.id);
    if (current == null) return;
    _transformBeforeState = _state;
    var structure = _state.structureForElement(current.id);
    if (structure != null && !_structureIsAligned(_state, structure)) {
      _state = _state.removeStructure(structure.id);
      structure = null;
    }
    _transformingIds = structure == null
        ? {current.id}
        : structure.memberIds.toSet();
  }
'''
if old_begin in text:
    text = text.replace(old_begin, new_begin, 1)
elif '_structureIsAligned(_state, structure)' not in text:
    raise SystemExit('beginTransform block not found')
marker = "  void renameBoard(String title) {\n"
if 'void setHeading(' not in text:
    insertion = '''  void setHeading(LightElement element, double degrees) {
    final current = _state.elementById(element.id);
    if (current == null) return;
    final heading = normalizeDegrees(degrees);
    final structure = _state.structureForElement(current.id);
    final ids = structure?.memberIds ?? [current.id];
    final replacements = <LightElement>[];
    for (final id in ids) {
      final member = _state.elementById(id);
      if (member == null) continue;
      replacements.add(member.copyWith(headingDegrees: heading));
    }
    if (replacements.isEmpty) return;
    final after = _state.replaceMany(replacements);
    if (after == _state) return;
    _execute(ReplaceBoardStateCommand(before: _state, after: after));
  }

  void setUnderlay(BoardUnderlay underlay) {
    if (_state.underlay == underlay) return;
    _execute(
      ReplaceBoardStateCommand(
        before: _state,
        after: _state.copyWith(underlay: underlay),
      ),
    );
  }

'''
    if marker not in text:
        raise SystemExit('renameBoard marker not found')
    text = text.replace(marker, insertion + marker, 1)
text = text.replace("  bool _isAutomaticNestPair(LightElement a, LightElement b) {", "  bool _isAutomaticNestPair(\n    BoardState state,\n    LightElement a,\n    LightElement b,\n  ) {", 1)
text = text.replace("    final aStructure = _state.structureForElement(a.id);\n    final bStructure = _state.structureForElement(b.id);", "    final aStructure = state.structureForElement(a.id);\n    final bStructure = state.structureForElement(b.id);", 1)
text = text.replace('_isAutomaticNestPair(moving, stationary)', '_isAutomaticNestPair(result, moving, stationary)')
text = text.replace('_isAutomaticNestPair(moving, candidate)', '_isAutomaticNestPair(result, moving, candidate)')
marker = "  void _replace(LightElement before, LightElement after) {\n"
if 'void _commitPoseChange(' not in text:
    helpers = '''  void _commitPoseChange(LightElement before, LightElement after) {
    var next = _state;
    final structure = next.structureForElement(before.id);
    if (structure != null) {
      final remaining = structure.memberIds
          .where((id) => id != before.id)
          .toList();
      next = remaining.length < 2
          ? next.removeStructure(structure.id)
          : next.upsertStructure(structure.copyWith(memberIds: remaining));
    }
    next = next.replace(after);

    // Pose changes never shove neighboring pieces. If standing creates an
    // unambiguous wall-only overlap, convert that overlap to a nest.
    if (after.pose == PyramidPose.upright &&
        after.illumination == IlluminationPattern.wall) {
      next = _snapWallOverlaps(next, {after.id});
    }

    _execute(ReplaceBoardStateCommand(before: _state, after: next));
  }

  bool _structureIsAligned(BoardState state, LightStructure structure) {
    if (structure.memberIds.length < 2) return false;
    LightElement? anchor;
    for (final id in structure.memberIds) {
      final member = state.elementById(id);
      if (member == null || member.pose != PyramidPose.upright) return false;
      anchor ??= member;
      if (member.position.distanceTo(anchor.position) > 0.05) return false;
      final headingDifference = normalizeDegrees(
        member.headingDegrees - anchor.headingDegrees,
      );
      final shortestHeadingDifference = math.min(
        headingDifference,
        360 - headingDifference,
      );
      if (shortestHeadingDifference > 0.1) return false;
    }
    return true;
  }

'''
    if marker not in text:
        raise SystemExit('_replace marker not found')
    text = text.replace(marker, helpers + marker, 1)
path.write_text(text)

path = Path('lib/ui/board_painter.dart')
text = path.read_text()
if "import '../domain/board_underlay.dart';" not in text:
    text = text.replace("import '../domain/board_state.dart';\n", "import '../domain/board_state.dart';\nimport '../domain/board_underlay.dart';\n", 1)
text = text.replace("    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);\n    for (final element in state.elements) {", "    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);\n    _paintUnderlay(canvas, size, state.underlay);\n    for (final element in state.elements) {", 1)
marker = "  void _paintElement(Canvas canvas, LightElement element) {\n"
if 'void _paintUnderlay(' not in text:
    method = '''  void _paintUnderlay(
    Canvas canvas,
    Size size,
    BoardUnderlay underlay,
  ) {
    if (!underlay.isVisible) return;

    final cell = 27.0 * logicalPixelsPerMm;
    final boardWidth = underlay.columns * cell;
    final boardHeight = underlay.rows * cell;
    final left = (size.width - boardWidth) / 2;
    final top = (size.height - boardHeight) / 2;
    final gridPaint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, logicalPixelsPerMm * 0.18);

    if (underlay.isChessLike) {
      final shade = Paint()..color = const Color(0x18FFFFFF);
      for (var row = 0; row < underlay.rows; row += 1) {
        for (var column = 0; column < underlay.columns; column += 1) {
          if ((row + column).isEven) continue;
          canvas.drawRect(
            Rect.fromLTWH(
              left + column * cell,
              top + row * cell,
              cell,
              cell,
            ),
            shade,
          );
        }
      }
    }

    for (var column = 0; column <= underlay.columns; column += 1) {
      final x = left + column * cell;
      canvas.drawLine(Offset(x, top), Offset(x, top + boardHeight), gridPaint);
    }
    for (var row = 0; row <= underlay.rows; row += 1) {
      final y = top + row * cell;
      canvas.drawLine(Offset(left, y), Offset(left + boardWidth, y), gridPaint);
    }
  }

'''
    if marker not in text:
        raise SystemExit('painter marker not found')
    text = text.replace(marker, method + marker, 1)
path.write_text(text)

path = Path('lib/ui/board_screen_next.dart')
text = path.read_text()
if "import '../domain/board_underlay.dart';" not in text:
    text = text.replace("import '../domain/board_state.dart';\n", "import '../domain/board_state.dart';\nimport '../domain/board_underlay.dart';\n", 1)
marker = "  Future<void> _showBrightnessDialog() async {\n"
if 'Future<void> _showOrientationDialog()' not in text:
    dialogs = '''  Future<void> _showOrientationDialog() async {
    final selected = _selected;
    if (selected == null) return;
    const angles = <double>[0, 45, 90, 135, 180, 225, 270, 315];
    final angle = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Orientation'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final angle in angles)
              OutlinedButton(
                onPressed: () => Navigator.pop(context, angle),
                child: Text('${angle.toInt()}°'),
              ),
          ],
        ),
      ),
    );
    if (angle != null) _controller.setHeading(selected, angle);
  }

  Future<void> _showUnderlayDialog() async {
    final underlay = await showDialog<BoardUnderlay>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Underlay · 27 mm cells'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, BoardUnderlay.none),
            child: const Text('None'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, BoardUnderlay.grid3x3),
            child: const Text('3×3 · Lava Flows / Launchpad 23'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, BoardUnderlay.grid3x4),
            child: const Text('3×4 · Homeworlds bank'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, BoardUnderlay.grid4x4),
            child: const Text('4×4 grid'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, BoardUnderlay.grid5x5),
            child: const Text('5×5 · Volcano / Pharaoh / Freeze Tag'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, BoardUnderlay.grid5x6),
            child: const Text('5×6 grid'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, BoardUnderlay.martianChess2),
            child: const Text('4×8 · Martian Chess · 2 players'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, BoardUnderlay.chess8x8),
            child: const Text('8×8 · Martian Chess · 4 players'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Text(
              'Underlays keep physical-size cells, so large boards may extend beyond a phone screen.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
    if (underlay != null) _controller.setUnderlay(underlay);
  }

'''
    if marker not in text:
        raise SystemExit('dialog insertion marker not found')
    text = text.replace(marker, dialogs + marker, 1)
board_anchor = "            MenuItemButton(\n              onPressed: _renameBoard,\n              child: const Text('Rename'),\n            ),\n"
if "child: const Text('Underlay')" not in text:
    if board_anchor not in text:
        raise SystemExit('board menu anchor not found')
    text = text.replace(board_anchor, board_anchor + "            MenuItemButton(\n              onPressed: _showUnderlayDialog,\n              child: const Text('Underlay'),\n            ),\n", 1)
edit_anchor = "            MenuItemButton(\n              closeOnActivate: false,\n              onPressed: _controller.canRedo ? _controller.redo : null,\n              child: const Text('Redo'),\n            ),\n"
if "child: const Text('Orientation')" not in text:
    if edit_anchor not in text:
        raise SystemExit('edit menu anchor not found')
    text = text.replace(edit_anchor, edit_anchor + "            MenuItemButton(\n              onPressed: selected == null ? null : _showOrientationDialog,\n              child: const Text('Orientation'),\n            ),\n", 1)
if "'Snap orientation'" not in text:
    desktop_anchor = "            ('Rotate', 'Hold Shift while two-finger scrolling'),\n"
    touch_anchor = "            ('Move + rotate', 'Two fingers: drag and twist'),\n"
    text = text.replace(desktop_anchor, desktop_anchor + "            ('Snap orientation', 'Select, then Menu > Edit > Orientation'),\n", 1)
    text = text.replace(touch_anchor, touch_anchor + "            ('Snap orientation', 'Select, then Menu > Edit > Orientation'),\n", 1)
path.write_text(text)

path = Path('test/domain/board_state_test.dart')
text = path.read_text()
if "import 'package:lighthouse/domain/board_underlay.dart';" not in text:
    text = text.replace("import 'package:lighthouse/domain/board_state.dart';\n", "import 'package:lighthouse/domain/board_state.dart';\nimport 'package:lighthouse/domain/board_underlay.dart';\n", 1)
text = text.replace("    final original = BoardState(\n      title: 'Example',\n", "    final original = BoardState(\n      title: 'Example',\n      underlay: BoardUnderlay.grid5x5,\n", 1)
if "expect(restored.underlay, BoardUnderlay.grid5x5);" not in text:
    text = text.replace("    expect(restored.structures, original.structures);\n", "    expect(restored.structures, original.structures);\n    expect(restored.underlay, BoardUnderlay.grid5x5);\n", 1)
if "expect(restored.underlay, BoardUnderlay.none);" not in text:
    text = text.replace("    expect(restored.title, 'Untitled Board');\n", "    expect(restored.title, 'Untitled Board');\n    expect(restored.underlay, BoardUnderlay.none);\n", 1)
path.write_text(text)

path = Path('test/application/physical_interactions_test.dart')
text = path.read_text()
if "pose change detaches a footprint" not in text:
    insertion = '''
  test('pose change detaches a footprint from its structure', () {
    final large = element(
      id: 'large',
      size: PyramidSize.large,
      position: const PhysicalPoint(50, 50),
    );
    final small = element(
      id: 'small',
      size: PyramidSize.small,
      position: const PhysicalPoint(50, 50),
    );
    final controller = BoardController(
      initialState: BoardState(
        elements: [large, small],
        structures: const [
          LightStructure(
            id: 'structure',
            kind: StructureKind.stack,
            memberIds: ['large', 'small'],
          ),
        ],
      ),
    );

    controller.tipOrStand(small, const PhysicalPoint(10, 0));

    expect(controller.state.structures, isEmpty);
    expect(controller.state.elementById('large')!.pose, PyramidPose.upright);
    expect(controller.state.elementById('small')!.pose, PyramidPose.flat);
  });

  test('old misaligned structures self-heal before a transform', () {
    final large = element(
      id: 'large',
      size: PyramidSize.large,
      position: const PhysicalPoint(50, 50),
    );
    final small = element(
      id: 'small',
      size: PyramidSize.small,
      position: const PhysicalPoint(60, 50),
    );
    final controller = BoardController(
      initialState: BoardState(
        elements: [large, small],
        structures: const [
          LightStructure(
            id: 'stale',
            kind: StructureKind.nest,
            memberIds: ['large', 'small'],
          ),
        ],
      ),
    );

    controller.beginTransform(small);
    controller.transformBy(const PhysicalPoint(10, 0), 0);
    controller.endTransform();

    expect(controller.state.structures, isEmpty);
    expect(controller.state.elementById('large')!.position, const PhysicalPoint(50, 50));
    expect(controller.state.elementById('small')!.position, const PhysicalPoint(70, 50));
  });

  test('standard orientation applies to an entire aligned structure', () {
    final large = element(
      id: 'large',
      size: PyramidSize.large,
      position: const PhysicalPoint(50, 50),
      headingDegrees: 12,
    );
    final small = element(
      id: 'small',
      size: PyramidSize.small,
      position: const PhysicalPoint(50, 50),
      headingDegrees: 12,
    );
    final controller = BoardController(
      initialState: BoardState(
        elements: [large, small],
        structures: const [
          LightStructure(
            id: 'structure',
            kind: StructureKind.stack,
            memberIds: ['large', 'small'],
          ),
        ],
      ),
    );

    controller.setHeading(small, 45);

    expect(controller.state.elementById('large')!.headingDegrees, 45);
    expect(controller.state.elementById('small')!.headingDegrees, 45);
  });

'''
    anchor = "  test('collision pushes another footprint during the drag', () {"
    if anchor not in text:
        raise SystemExit('physical interaction test anchor not found')
    text = text.replace(anchor, insertion + anchor, 1)
path.write_text(text)
