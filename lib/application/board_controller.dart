import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../domain/board_command.dart';
import '../domain/board_state.dart';
import '../domain/convex_geometry.dart';
import '../domain/geometry.dart';
import '../domain/light_element.dart';
import '../domain/light_structure.dart';
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
  Set<String> _transformingIds = const {};
  BoardState? _transformBeforeState;
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

  LightStructure? structureFor(LightElement element) =>
      _state.structureForElement(element.id);

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
    final current = _state.elementById(element.id);
    if (current == null) return;
    switch (current.size) {
      case PyramidSize.small:
        _replace(current, current.copyWith(size: PyramidSize.medium));
      case PyramidSize.medium:
        _replace(current, current.copyWith(size: PyramidSize.large));
      case PyramidSize.large:
        _execute(RemoveElementCommand(current));
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
        ),
      );
      return;
    }

    final rotation = -current.headingDegrees * math.pi / 180;
    final localX =
        drag.xMm * math.cos(rotation) - drag.yMm * math.sin(rotation);
    final localY =
        drag.xMm * math.sin(rotation) + drag.yMm * math.cos(rotation);
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
    final structure = _state.structureForElement(current.id);
    _transformingIds = structure == null
        ? {current.id}
        : structure.memberIds.toSet();
    _transformBeforeState = _state;
  }

  void transformBy(PhysicalPoint delta, double rotationDeltaRadians) {
    if (_transformingIds.isEmpty) return;
    final rotationDelta = radiansToDegrees(rotationDeltaRadians);
    final replacements = <LightElement>[];
    for (final id in _transformingIds) {
      final current = _state.elementById(id);
      if (current == null) continue;
      replacements.add(
        current.copyWith(
          position: current.position + delta,
          headingDegrees: normalizeDegrees(
            current.headingDegrees + rotationDelta,
          ),
        ),
      );
    }
    if (replacements.isEmpty) return;
    _state = _state.replaceMany(replacements);
    // Resolve contact continuously so pushing is visible while dragging rather
    // than appearing only after the fingers leave the glass.
    _state = _resolvePushes(_state, _transformingIds);
    notifyListeners();
  }

  void endTransform() {
    final before = _transformBeforeState;
    var movingIds = _transformingIds;
    _transformBeforeState = null;
    _transformingIds = const {};
    if (before == null || movingIds.isEmpty) return;

    _state = _resolvePushes(_state, movingIds);
    _state = _snapWallOverlaps(_state, movingIds);

    // If an automatic nest absorbed the moved element, the completed command
    // includes the whole resulting structure.
    final expanded = <String>{...movingIds};
    for (final id in movingIds) {
      final element = _state.elementById(id);
      if (element == null) continue;
      final structure = _state.structureForElement(element.id);
      if (structure != null) expanded.addAll(structure.memberIds);
    }
    movingIds = expanded;

    if (before == _state) return;
    _undoStack.add(ReplaceBoardStateCommand(before: before, after: _state));
    _redoStack.clear();
    notifyListeners();
  }

  void cancelTransform() {
    final before = _transformBeforeState;
    _transformBeforeState = null;
    _transformingIds = const {};
    if (before == null) return;
    _state = before;
    notifyListeners();
  }

  bool snapIntoNearestStructure(
    LightElement element,
    StructureKind kind, {
    double snapDistanceMm = 12,
  }) {
    final current = _state.elementById(element.id);
    if (current == null || current.pose != PyramidPose.upright) return false;

    final currentStructure = _state.structureForElement(current.id);
    final currentIds = currentStructure?.memberIds.toSet() ?? {current.id};
    LightElement? nearest;
    var nearestDistance = double.infinity;

    for (final candidate in _state.elements) {
      if (currentIds.contains(candidate.id) ||
          candidate.pose != PyramidPose.upright) {
        continue;
      }
      final distance = current.position.distanceTo(candidate.position);
      if (distance <= snapDistanceMm && distance < nearestDistance) {
        nearest = candidate;
        nearestDistance = distance;
      }
    }

    final target = nearest;
    if (target == null) return false;

    final targetStructure = _state.structureForElement(target.id);
    final targetIds = targetStructure?.memberIds.toSet() ?? {target.id};
    final combinedIds = {...currentIds, ...targetIds};
    final combined = combinedIds
        .map(_state.elementById)
        .whereType<LightElement>()
        .toList();

    final sizes = combined.map((member) => member.size).toSet();
    if (sizes.length != combined.length) return false;

    final anchor = targetStructure == null
        ? target
        : _state.elementById(targetStructure.memberIds.first) ?? target;
    combined.sort((a, b) => b.size.index.compareTo(a.size.index));

    var after = _state;
    if (currentStructure != null) {
      after = after.removeStructure(currentStructure.id);
    }
    if (targetStructure != null && targetStructure.id != currentStructure?.id) {
      after = after.removeStructure(targetStructure.id);
    }

    after = after.replaceMany([
      for (final member in combined)
        member.copyWith(
          position: anchor.position,
          headingDegrees: anchor.headingDegrees,
        ),
    ]);

    final structure = LightStructure(
      id:
          targetStructure?.id ??
          currentStructure?.id ??
          'structure-${_newId()}',
      kind: kind,
      memberIds: [for (final member in combined) member.id],
    );
    after = after.upsertStructure(structure);
    _execute(ReplaceBoardStateCommand(before: _state, after: after));
    return true;
  }

  bool detachFromStructure(LightElement element) {
    final structure = _state.structureForElement(element.id);
    if (structure == null) return false;
    final remaining = structure.memberIds
        .where((id) => id != element.id)
        .toList();
    final after = remaining.length < 2
        ? _state.removeStructure(structure.id)
        : _state.upsertStructure(structure.copyWith(memberIds: remaining));
    _execute(ReplaceBoardStateCommand(before: _state, after: after));
    return true;
  }

  bool toggleStructureKind(LightElement element) {
    final structure = _state.structureForElement(element.id);
    if (structure == null) return false;
    final next = structure.kind == StructureKind.stack
        ? StructureKind.nest
        : StructureKind.stack;
    final after = _state.upsertStructure(structure.copyWith(kind: next));
    _execute(ReplaceBoardStateCommand(before: _state, after: after));
    return true;
  }

  void renameBoard(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed == _state.title) return;
    final after = _state.copyWith(title: trimmed);
    _execute(ReplaceBoardStateCommand(before: _state, after: after));
  }

  void replaceState(BoardState state, {bool clearHistory = true}) {
    _state = state;
    if (clearHistory) {
      _undoStack.clear();
      _redoStack.clear();
    }
    notifyListeners();
  }

  void newBoard() => replaceState(BoardState.empty());

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

  bool _isAutomaticNestPair(LightElement a, LightElement b) {
    if (a.id == b.id ||
        a.pose != PyramidPose.upright ||
        b.pose != PyramidPose.upright ||
        a.illumination != IlluminationPattern.wall ||
        b.illumination != IlluminationPattern.wall ||
        a.size == b.size) {
      return false;
    }
    final aStructure = _state.structureForElement(a.id);
    final bStructure = _state.structureForElement(b.id);
    return aStructure == null ||
        bStructure == null ||
        aStructure.id != bStructure.id;
  }

  BoardState _resolvePushes(BoardState initial, Set<String> movingIds) {
    var result = initial;
    final activeIds = <String>{...movingIds};

    // Treat a pushed object as another moving object so contact can propagate
    // through a row of pieces. The pass limit is a guard against degenerate
    // arrangements, not a physical approximation.
    for (var pass = 0; pass < 48; pass += 1) {
      var changed = false;

      outer:
      for (final movingId in activeIds.toList()) {
        final moving = result.elementById(movingId);
        if (moving == null) continue;

        for (final stationary in result.elements.toList()) {
          if (activeIds.contains(stationary.id)) continue;

          // Two different-size wall-only upright footprints are allowed to
          // overlap during the drag because release will turn the overlap into
          // a perfectly aligned nest.
          if (_isAutomaticNestPair(moving, stationary)) continue;

          final separation = minimumSeparationVector(
            polygonForElement(moving, geometry),
            polygonForElement(stationary, geometry),
          );
          if (separation == null) continue;

          final stationaryStructure = result.structureForElement(stationary.id);
          final pushedIds = stationaryStructure?.memberIds ?? [stationary.id];
          final replacements = <LightElement>[];
          for (final id in pushedIds) {
            final member = result.elementById(id);
            if (member == null) continue;
            replacements.add(
              member.copyWith(position: member.position + separation),
            );
          }
          if (replacements.isEmpty) continue;
          result = result.replaceMany(replacements);
          activeIds.addAll(pushedIds);
          changed = true;
          break outer;
        }
      }

      if (!changed) break;
    }
    return result;
  }

  BoardState _snapWallOverlaps(BoardState initial, Set<String> movingIds) {
    var result = initial;
    final moved = <String>{...movingIds};

    for (var pass = 0; pass < 8; pass += 1) {
      var snapped = false;

      outer:
      for (final movingId in moved.toList()) {
        final moving = result.elementById(movingId);
        if (moving == null) continue;

        for (final candidate in result.elements.toList()) {
          if (moved.contains(candidate.id) ||
              !_isAutomaticNestPair(moving, candidate)) {
            continue;
          }
          final overlap = minimumSeparationVector(
            polygonForElement(moving, geometry),
            polygonForElement(candidate, geometry),
          );
          if (overlap == null) continue;

          final movingStructure = result.structureForElement(moving.id);
          final targetStructure = result.structureForElement(candidate.id);
          final movingMembers = movingStructure?.memberIds.toSet() ?? {moving.id};
          final targetMembers = targetStructure?.memberIds.toSet() ?? {
            candidate.id,
          };
          final combinedIds = {...movingMembers, ...targetMembers};
          final combined = combinedIds
              .map(result.elementById)
              .whereType<LightElement>()
              .toList();
          final sizes = combined.map((member) => member.size).toSet();
          if (sizes.length != combined.length) continue;

          combined.sort((a, b) => b.size.index.compareTo(a.size.index));
          final anchor = combined.first;

          if (movingStructure != null) {
            result = result.removeStructure(movingStructure.id);
          }
          if (targetStructure != null &&
              targetStructure.id != movingStructure?.id) {
            result = result.removeStructure(targetStructure.id);
          }

          result = result.replaceMany([
            for (final member in combined)
              member.copyWith(
                position: anchor.position,
                headingDegrees: anchor.headingDegrees,
              ),
          ]);
          final structure = LightStructure(
            id:
                targetStructure?.id ??
                movingStructure?.id ??
                'structure-${_newId()}',
            kind: StructureKind.nest,
            memberIds: [for (final member in combined) member.id],
          );
          result = result.upsertStructure(structure);
          moved.addAll(structure.memberIds);
          snapped = true;
          break outer;
        }
      }

      if (!snapped) break;
    }
    return result;
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
