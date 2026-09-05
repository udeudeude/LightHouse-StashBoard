import 'package:flutter/material.dart';

import '../application/board_controller.dart';
import '../domain/physical_point.dart';
import 'board_painter.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.logicalPixelsPerMm,
    required this.onRecalibrate,
  });

  final double logicalPixelsPerMm;
  final VoidCallback onRecalibrate;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  late final BoardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BoardController()..addListener(_refresh);
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

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

  void _handleLongPress(LongPressStartDetails details) {
    final point = _toPhysical(details.localPosition);
    final target = _controller.hitTest(point, haloMm: 7);
    if (target != null) _controller.toggleIllumination(target);
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
            onLongPressStart: _handleLongPress,
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
                        onPressed: _controller.canUndo ? _controller.undo : null,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: 'Redo',
                        onPressed: _controller.canRedo ? _controller.redo : null,
                        icon: const Icon(Icons.redo),
                      ),
                      IconButton(
                        tooltip: 'Recalibrate',
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
