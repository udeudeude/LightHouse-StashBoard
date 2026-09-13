from pathlib import Path

path = Path('scripts/apply_toy_suite_v2.py')
text = path.read_text()

replacements = {
    "_eventZoneProgress = (remaining / 12).clamp(0, 1);": "_eventZoneProgress = (remaining / 12).clamp(0, 1).toDouble();",
    "_turnTimerProgress = (remaining / 30000).clamp(0, 1);": "_turnTimerProgress = (remaining / 30000).clamp(0, 1).toDouble();",
    "var position = projectile.position + projectile.velocity * dt;": "var position = projectile.position + PhysicalPoint(projectile.velocity.xMm * dt, projectile.velocity.yMm * dt);",
    "final dismiss = eventZoneDismiss.clamp(0, 1);": "final dismiss = eventZoneDismiss.clamp(0, 1).toDouble();",
    "final elapsed = 1 - progress.clamp(0, 1);": "final elapsed = 1 - progress.clamp(0, 1).toDouble();",
    "final length = metric.length * progress.clamp(0, 1);": "final length = metric.length * progress.clamp(0, 1).toDouble();",
    "final t = (impact.lifeSeconds / 0.8).clamp(0, 1);": "final t = (impact.lifeSeconds / 0.8).clamp(0, 1).toDouble();",
    "                projectiles: _projectiles,\n                impacts: _impacts,": "                projectiles: _projectiles,\n                impacts: _impacts,\n                sideGunsVisible: _activeToys.contains(_ToyKind.sideGuns),\n                cornerGunsVisible: _activeToys.contains(_ToyKind.cornerRicochet) || _projectiles.any((p) => p.ricochet),",
    "    required this.projectiles,\n    required this.impacts,": "    required this.projectiles,\n    required this.impacts,\n    required this.sideGunsVisible,\n    required this.cornerGunsVisible,",
    "  final List<ToyProjectile> projectiles;\n  final List<ToyImpact> impacts;": "  final List<ToyProjectile> projectiles;\n  final List<ToyImpact> impacts;\n  final bool sideGunsVisible;\n  final bool cornerGunsVisible;",
    "board_path.write_text(text)": "text = text.replace('    _eventZoneTimer?.cancel();\\n', '')\ntext = text.replace('    _turnTimer?.cancel();\\n', '')\nboard_path.write_text(text)",
}

for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f'missing expected staged fragment: {old[:80]!r}')
    text = text.replace(old, new)

old_guns = '''  void _paintGuns(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.34);
    const d = 7.0;
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, 3), width: 10, height: 5), paint);
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, size.height - 3), width: 10, height: 5), paint);
    canvas.drawRect(Rect.fromCenter(center: Offset(3, size.height / 2), width: 5, height: 10), paint);
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width - 3, size.height / 2), width: 5, height: 10), paint);
    for (final p in [const Offset(d, d), Offset(size.width - d, d), Offset(d, size.height - d), Offset(size.width - d, size.height - d)]) {
      canvas.drawCircle(p, 3.2, Paint()..color = Colors.white.withValues(alpha: 0.22));
    }
  }
'''
new_guns = '''  void _paintGuns(Canvas canvas, Size size) {
    if (sideGunsVisible) {
      final paint = Paint()..color = Colors.white.withValues(alpha: 0.34);
      canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, 3), width: 10, height: 5), paint);
      canvas.drawRect(Rect.fromCenter(center: Offset(size.width / 2, size.height - 3), width: 10, height: 5), paint);
      canvas.drawRect(Rect.fromCenter(center: Offset(3, size.height / 2), width: 5, height: 10), paint);
      canvas.drawRect(Rect.fromCenter(center: Offset(size.width - 3, size.height / 2), width: 5, height: 10), paint);
    }
    if (cornerGunsVisible) {
      const d = 7.0;
      final paint = Paint()..color = Colors.white.withValues(alpha: 0.22);
      for (final p in [const Offset(d, d), Offset(size.width - d, d), Offset(d, size.height - d), Offset(size.width - d, size.height - d)]) {
        canvas.drawCircle(p, 3.2, paint);
      }
    }
  }
'''
if old_guns not in text:
    raise SystemExit('staged gun painter block not found')
text = text.replace(old_guns, new_guns, 1)

path.write_text(text)
