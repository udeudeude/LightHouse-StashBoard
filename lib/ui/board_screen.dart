import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../application/board_controller.dart';
import '../application/board_store.dart';
import '../domain/board_state.dart';
import '../domain/light_element.dart';
import '../domain/physical_point.dart';
import 'board_painter.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.logicalPixelsPerMm,
    required this.initialState,
    required this.calibrationLabel,
    required this.onRecalibrate,
  });

  final double logicalPixelsPerMm;
  final BoardState initialState;
  final String calibrationLabel;
  final VoidCallback onRecalibrate;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late final BoardController _controller;
  final BoardStore _store = BoardStore();

  LightElement? _gestureTarget;
  PhysicalPoint? _oneFingerStart;
  PhysicalPoint? _oneFingerLast;
  double _oneFingerPathMm = 0;
  double _lastRotation = 0;
  bool _transformStarted = false;

  @override
  void initState() {
    super.initState();
    _controller = BoardController(initialState: widget.initialState)
      ..addListener(_refresh);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _refresh() {
    setState(() {});
    _store.save(_controller.state);
  }

  PhysicalPoint _toPhysical(Offset point) => PhysicalPoint(
    point.dx / widget.logicalPixelsPerMm,
    point.dy / widget.logicalPixelsPerMm,
  );

  void _handleDoubleTapDown(TapDownDetails details) {
    final point = _toPhysical(details.localPosition);
    final target = _controller.hitTest(point, haloMm: 7);
    if (target == null) {
      _controller.createAt(point);
    } else {
      _controller.cycleSizeOrDelete(target);
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    final point = _toPhysical(details.localFocalPoint);
    _gestureTarget = _controller.hitTest(point, haloMm: 7);
    _oneFingerStart = point;
    _oneFingerLast = point;
    _oneFingerPathMm = 0;
    _lastRotation = 0;
    _transformStarted = false;

    if (details.pointerCount >= 2 && _gestureTarget != null) {
      _controller.beginTransform(_gestureTarget!);
      _transformStarted = true;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final target = _gestureTarget;
    if (target == null) return;

    if (details.pointerCount >= 2) {
      if (!_transformStarted) {
        _controller.beginTransform(target);
        _transformStarted = true;
        _lastRotation = details.rotation;
        return;
      }
      final delta = PhysicalPoint(
        details.focalPointDelta.dx / widget.logicalPixelsPerMm,
        details.focalPointDelta.dy / widget.logicalPixelsPerMm,
      );
      final rotationDelta = details.rotation - _lastRotation;
      _lastRotation = details.rotation;
      _controller.transformBy(delta, rotationDelta);
      return;
    }

    if (_transformStarted) return;
    final current = _toPhysical(details.localFocalPoint);
    final last = _oneFingerLast;
    if (last != null) {
      final dx = current.xMm - last.xMm;
      final dy = current.yMm - last.yMm;
      _oneFingerPathMm += math.sqrt(dx * dx + dy * dy);
    }
    _oneFingerLast = current;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final target = _gestureTarget;
    if (_transformStarted) {
      _controller.endTransform();
      _clearGesture();
      return;
    }

    final start = _oneFingerStart;
    final end = _oneFingerLast;
    if (target != null && start != null && end != null) {
      final drag = PhysicalPoint(end.xMm - start.xMm, end.yMm - start.yMm);
      final displacement = math.sqrt(drag.xMm * drag.xMm + drag.yMm * drag.yMm);
      if (target.pose == PyramidPose.upright &&
          _oneFingerPathMm >= 15 &&
          displacement <= 4) {
        _controller.toggleIllumination(target);
      } else if (displacement >= 4) {
        _controller.tipOrStand(target, drag);
      }
    }
    _clearGesture();
  }

  void _clearGesture() {
    _gestureTarget = null;
    _oneFingerStart = null;
    _oneFingerLast = null;
    _oneFingerPathMm = 0;
    _lastRotation = 0;
    _transformStarted = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: _handleDoubleTapDown,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: CustomPaint(
              painter: BoardPainter(
                state: _controller.state,
                logicalPixelsPerMm: widget.logicalPixelsPerMm,
                geometry: _controller.geometry,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: _controller.canUndo
                            ? _controller.undo
                            : null,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: 'Redo',
                        onPressed: _controller.canRedo
                            ? _controller.redo
                            : null,
                        icon: const Icon(Icons.redo),
                      ),
                      IconButton(
                        tooltip: widget.calibrationLabel,
                        onPressed: widget.onRecalibrate,
                        icon: const Icon(Icons.straighten),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
