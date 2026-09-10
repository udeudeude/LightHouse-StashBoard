from pathlib import Path
import re

path = Path('lib/ui/board_screen_next.dart')
text = path.read_text()

old = """    if (exact != null &&
        exact.pose == PyramidPose.flat &&
        _isPointToBaseGesture(exact, start, end)) {
      // Stand: sweep from the triangle's point toward its base, within the
      // actual triangle. No interaction halo participates in recognition.
      _controller.tipOrStand(exact, drag);
      HapticFeedback.mediumImpact();
      _clearGesture();
      return;
    }
"""
new = """    if (exact != null &&
        exact.pose == PyramidPose.flat &&
        displacement >= _minimumLineGestureMm &&
        _crossesFlatBaseEdge(exact, start, end)) {
      // Stand: begin inside the actual triangle and cross its short base
      // edge. This mirrors tipping: inside-to-outside, with no halo.
      _controller.tipOrStand(exact, drag);
      HapticFeedback.mediumImpact();
      _clearGesture();
      return;
    }
"""
if old not in text:
    raise SystemExit('standing gesture block not found')
text = text.replace(old, new, 1)

old = """  bool _isPointToBaseGesture(
    LightElement triangle,
    PhysicalPoint start,
    PhysicalPoint end,
  ) {
    if (!_containsPoint(triangle, start) || !_containsPoint(triangle, end)) {
      return false;
    }
    final localStart = rotateVector(
      start - triangle.position,
      -triangle.headingDegrees,
    );
    final localEnd = rotateVector(
      end - triangle.position,
      -triangle.headingDegrees,
    );
    final length = _controller.geometry.flatLengthMm(triangle.size);
    final travel = localEnd.yMm - localStart.yMm;
    return localStart.yMm < -length * 0.08 &&
        localEnd.yMm > length * 0.08 &&
        travel >= math.max(4, length * 0.28) &&
        localEnd.xMm.abs() <= travel;
  }
"""
new = """  bool _crossesFlatBaseEdge(
    LightElement triangle,
    PhysicalPoint start,
    PhysicalPoint end,
  ) {
    if (!_containsPoint(triangle, start) || _containsPoint(triangle, end)) {
      return false;
    }
    final localStart = rotateVector(
      start - triangle.position,
      -triangle.headingDegrees,
    );
    final localEnd = rotateVector(
      end - triangle.position,
      -triangle.headingDegrees,
    );
    final halfLength = _controller.geometry.flatLengthMm(triangle.size) / 2;
    final halfBase = _controller.geometry.baseMm(triangle.size) / 2;
    final deltaY = localEnd.yMm - localStart.yMm;
    if (deltaY <= 0 || localEnd.yMm <= halfLength) return false;

    final crossing = (halfLength - localStart.yMm) / deltaY;
    if (crossing <= 0 || crossing >= 1) return false;
    final xAtBase =
        localStart.xMm + (localEnd.xMm - localStart.xMm) * crossing;
    return xAtBase.abs() <= halfBase;
  }
"""
if old not in text:
    raise SystemExit('standing helper not found')
text = text.replace(old, new, 1)

old = "child: Text('Current: ${_controller.state.title}')"
if old not in text:
    raise SystemExit('current label not found')
text = text.replace(old, "child: Text(_controller.state.title)", 1)

undo = "onPressed: _controller.canUndo ? _controller.undo : null,"
redo = "onPressed: _controller.canRedo ? _controller.redo : null,"
if undo not in text or redo not in text:
    raise SystemExit('undo/redo actions not found')
text = text.replace(undo, "closeOnActivate: false,\n              " + undo, 1)
text = text.replace(redo, "closeOnActivate: false,\n              " + redo, 1)

submenu = "        SubmenuButton(\n          menuChildren:"
count = text.count(submenu)
if count < 5:
    raise SystemExit(f'expected at least five top-level submenus, found {count}')
text = text.replace(
    submenu,
    """        SubmenuButton(
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          menuChildren:""",
)

old = """          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 1.1),
          ),
"""
new = """          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 0.55),
          ),
"""
if old not in text:
    raise SystemExit('menu circle not found')
text = text.replace(old, new, 1)

path.write_text(text)
