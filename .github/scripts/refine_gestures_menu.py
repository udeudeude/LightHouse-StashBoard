from pathlib import Path

path = Path('lib/ui/board_screen_next.dart')
text = path.read_text()

old = "title: const Text('Verify physical size'),"
if old not in text:
    raise SystemExit('size dialog title not found')
text = text.replace(old, "title: const Text('Size'),", 1)

old = """            MenuItemButton(
              onPressed: _showCalibrationCheck,
              child: const Text('Verify physical size'),
            ),
            MenuItemButton(
              onPressed: widget.onRecalibrate,
              child: const Text('Recalibrate'),
            ),
"""
new = """            MenuItemButton(
              onPressed: _showCalibrationCheck,
              child: const Text('Size'),
            ),
"""
if old not in text:
    raise SystemExit('display size/recalibrate menu block not found')
text = text.replace(old, new, 1)

old = "title: Text('Install LightHouse'),"
if old not in text:
    raise SystemExit('web full-screen dialog title not found')
text = text.replace(old, "title: Text('Full-screen'),", 1)

old = "child: const Text('Install / full-screen help'),"
if old not in text:
    raise SystemExit('full-screen menu label not found')
text = text.replace(old, "child: const Text('Full-screen'),", 1)

path.write_text(text)
