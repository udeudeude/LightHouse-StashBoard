from pathlib import Path

path = Path('lib/ui/board_screen_next.dart')
text = path.read_text()

old = """    if (!faceDown) {
      _faceDownTimer?.cancel();
      _faceDownTimer = null;
      // Keep credits visible after the device comes face-up so the easter egg
      // can actually be seen. Once dismissed while face-up, arm it again.
      if (!_creditsVisible) _faceDownLatched = false;
      return;
    }
"""
new = """    if (!faceDown) {
      _faceDownTimer?.cancel();
      _faceDownTimer = null;
      _faceDownLatched = false;
      if (_creditsVisible && mounted) {
        setState(() => _creditsVisible = false);
      }
      return;
    }
"""
if old not in text:
    raise SystemExit('face-up credits block not found')
text = text.replace(old, new, 1)

old = """            if (kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
              MenuItemButton(
                onPressed: () => _ensureMotionPermission(force: true),
                child: const Text('Enable Face-down Credits'),
              ),
"""
if old not in text:
    raise SystemExit('explicit credits menu item not found')
text = text.replace(old, '', 1)

old = """            if (isIos && kIsWeb)
              (
                'Face-down credits',
                'Tap the menu once, allow Motion & Orientation access, then turn the device screen-down',
              ),
"""
if old not in text:
    raise SystemExit('credits instruction item not found')
text = text.replace(old, '', 1)

old = """  Widget _credits() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _creditsVisible = false),
"""
new = """  Widget _credits() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: null,
"""
if old not in text:
    raise SystemExit('credits tap handler not found')
text = text.replace(old, new, 1)

old = """                SizedBox(height: 28),
                Text(
                  'Triggered by turning the device face-down.\\nTap anywhere to return.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
"""
if old not in text:
    raise SystemExit('credits explanatory footer not found')
text = text.replace(old, '', 1)

path.write_text(text)

readme = Path('README.md')
r = readme.read_text()
r = r.replace(
    '- Display: size/calibration, brightness, orientation information, and face-down-credits permission where required\n',
    '- Display: size/calibration, brightness, and orientation information\n',
)
r = r.replace(
    '- face-down credits on supported motion-enabled devices, including iOS web permission handling\n',
    '- hidden face-down-only credits on supported motion-enabled devices; they vanish the instant the device is face-up\n',
)
readme.write_text(r)

changelog = Path('CHANGELOG.md')
c = changelog.read_text()
marker = '## Unreleased\n\n'
note = '- Restored the intentionally awkward face-down-only credits: no menu item, no instruction entry, no tap dismissal, and the credits vanish immediately when the device turns face-up.\n'
if note not in c:
    c = c.replace(marker, marker + note, 1)
changelog.write_text(c)
