import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../domain/board_command.dart';
import '../domain/board_state.dart';
import '../domain/geometry.dart';
import '../domain/light_element.dart';
import '../domain/physical_point.dart';
import '../domain/pyramid_geometry.dart';

class BoardController extends ChangeNotifier {
  BoardController({
    BoardState? initialState,
    this.geometry = PyramidGeometryProfile.prototype2025,
  }) : _state = initialState ?? BoardState.empty();

  final PyramidGeometryProfile geometry;
  BoardState _state;
  BoardState get state => _state;

  final List<BoardCommand> _undoStack = [];
  final List<BoardCommand> _redoStack = [];
  String? _transformingId;
  LightElement? _transformBefore;
  static int _idCounter = 0;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  LightElement? hitTest(PhysicalPoint point, {double haloMm = 6}) {
    for (final element in _state.elements.reversed) {
      if (hitTestLightElement(element, point, geometry, haloMm: haloMm)) {
        return element;
      }
    }
    return null;
  }

  void createAt(PhysicalPoint position) {
    final element = LightElement(
      id: _newId(),
      size: PyramidSize.small,
      pose: PyramidPose.upright,
      position: position,
      headingDegrees: 0,
      illumination: IlluminationPattern.full,
    );
    _execute(AddElementCommand(element));
  }

  void cycleSizeOrDelete(LightElement element) {
    switch (element.size) {
      case PyramidSize.small:
        _replace(element, element.copyWith(size: PyramidSize.medium));
      case PyramidSize.medium:
        _replace(element, element.copyWith(size: PyramidSize.large));
      case PyramidSize.large:
        _execute(RemoveElementCommand(element));
    }
  }

  void toggleIllumination(LightElement element) {
    final current = _state.elementById(element.id);
    if (current == null || current.pose != PyramidPose.upright) return;
    final next = current.illumination == IlluminationPattern.full
        ? IlluminationPattern.wall
        : IlluminationPattern.full;
    _replace(current, current.copyWith(illumination: next));
  }

  void tipOrStand(LightElement element, PhysicalPoint drag) {
    final current = _state.elementById(element.id);
    if (current == null) return;
    final distance = math.sqrt(drag.xMm * drag.xMm + drag.yMm * drag.yMm);
    if (distance < 4) return;

    final base = geometry.baseMm(current.size);
    final length = geometry.flatLengthMm(current.size);
    final hingeTravel = (base + length) / 2;

    if (current.pose == PyramidPose.upright) {
      final ux = drag.xMm / distance;
      final uy = drag.yMm / distance;
      final dragAngle = math.atan2(uy, ux) * 180 / math.pi;
      _replace(
        current,
        current.copyWith(
          pose: PyramidPose.flat,
          position: PhysicalPoint(
            current.position.xMm + ux * hingeTravel,
            current.position.yMm + uy * hingeTravel,
          ),
          headingDegrees: normalizeDegrees(dragAngle + 90),
          illumination: IlluminationPattern.full,
        ),
      );
      return;
    }

    final rotation = -current.headingDegrees * math.pi / 180;
    final localX = drag.xMm * math.cos(rotation) - drag.yMm * math.sin(rotation);
    final localY = drag.xMm * math.sin(rotation) + drag.yMm * math.cos(rotation);
    if (localY <= 0 || localY <= localX.abs()) return;

    final heading = current.headingDegrees * math.pi / 180;
    final shiftX = -hingeTravel * math.sin(heading);
    final shiftY = hingeTravel * math.cos(heading);
    _replace(
      current,
      current.copyWith(
        pose: PyramidPose.upright,
        position: PhysicalPoint(
          current.position.xMm + shiftX,
          current.position.yMm + shiftY,
        ),
      ),
    );
  }

  void beginTransform(LightElement element) {
    final current = _state.elementById(element.id);
    if (current == null) return;
    _transformingId = current.id;
    _transformBefore = current;
  }

  void transformBy(PhysicalPoint delta, double rotationDeltaRadians) {
    final id = _transformingId;
    if (id == null) return;
    final current = _state.elementById(id);
    if (current == null) return;
    _state = _state.replace(
      current.copyWith(
        position: current.position + delta,
        headingDegrees: normalizeDegrees(
          current.headingDegrees + radiansToDegrees(rotationDeltaRadians),
        ),
      ),
    );
    notifyListeners();
  }

  void endTransform() {
    final before = _transformBefore;
    final id = _transformingId;
    _transformBefore = null;
    _transformingId = null;
    if (before == null || id == null) return;
    final after = _state.elementById(id);
    if (after == null || after == before) return;
    _undoStack.add(ReplaceElementCommand(before: before, after: after));
    _redoStack.clear();
    notifyListeners();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    final command = _undoStack.removeLast();
    _state = command.revert(_state);
    _redoStack.add(command);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final command = _redoStack.removeLast();
    _state = command.apply(_state);
    _undoStack.add(command);
    notifyListeners();
  }

  void _replace(LightElement before, LightElement after) {
    _execute(ReplaceElementCommand(before: before, after: after));
  }

  void _execute(BoardCommand command) {
    _state = command.apply(_state);
    _undoStack.add(command);
    _redoStack.clear();
    notifyListeners();
  }

  String _newId() {
    _idCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }
}
