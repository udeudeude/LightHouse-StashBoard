from pathlib import Path

path = Path('lib/ui/board_screen_next.dart')
text = path.read_text()

old = '''    if (!faceDown) {
      _faceDownTimer?.cancel();
      _faceDownTimer = null;
      _faceDownLatched = false;
      if (_creditsVisible && mounted) {
        setState(() => _creditsVisible = false);
      }
      return;
    }
'''
new = '''    if (!faceDown) {
      _faceDownTimer?.cancel();
      _faceDownTimer = null;
      // Keep credits visible after the device comes face-up so the easter egg
      // can actually be seen. Once dismissed while face-up, arm it again.
      if (!_creditsVisible) _faceDownLatched = false;
      return;
    }
'''
if old not in text:
    raise SystemExit('face-up block not found')
text = text.replace(old, new, 1)

old = '''  Widget _credits() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: null,
'''
new = '''  Widget _credits() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _creditsVisible = false),
'''
if old not in text:
    raise SystemExit('credits gesture block not found')
text = text.replace(old, new, 1)

text = text.replace(
    "'Keep the device face-down to view this screen.\\nTurn it face-up to return.'",
    "'Triggered by turning the device face-down.\\nTap anywhere to return.'",
    1,
)

path.write_text(text)
