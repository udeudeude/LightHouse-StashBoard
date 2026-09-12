from pathlib import Path

path = Path('lib/ui/board_screen_next.dart')
text = path.read_text()
old = """  void _onPointerDown(PointerDownEvent event) {
    if (_creditsVisible ||
        event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
"""
new = """  void _onPointerDown(PointerDownEvent event) {
    // Safari will not expose motion data until permission is requested from a
    // real user gesture. Piggyback that handshake on the first ordinary board
    // touch so the face-down behavior stays undisclosed in the interface.
    if (kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        !_motionPermissionAttempted) {
      unawaited(_ensureMotionPermission());
    }

    if (_creditsVisible ||
        event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
"""
if old not in text:
    raise SystemExit('pointer-down block not found')
text = text.replace(old, new, 1)
path.write_text(text)

changelog = Path('CHANGELOG.md')
c = changelog.read_text()
marker = '## Unreleased\n\n'
note = '- On iPhone web, motion permission is now requested from the first ordinary board touch rather than requiring the hidden credits behavior to depend on opening a menu first.\n'
if note not in c:
    c = c.replace(marker, marker + note, 1)
changelog.write_text(c)
