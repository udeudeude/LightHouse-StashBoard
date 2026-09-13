from pathlib import Path
import re

board_path = Path('lib/ui/board_screen_next.dart')
text = board_path.read_text()


def sub_once(pattern: str, replacement: str, label: str, flags=re.S):
    global text
    text, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 replacement, got {count}')


enum_code = '''enum _ToyKind {
  lightLottery('Light Lottery', Icons.auto_awesome, true),
  entropy('Entropy Delete', Icons.hourglass_empty, true),
  ghostPaths('Ghost Paths', Icons.timeline, false),
  eventZone('Random Event Zone', Icons.adjust, false),
  turnTimer('Turn Timer', Icons.timer_outlined, false),
  breathing('Breathing', Icons.opacity, false),
  nestCycle('Nest Cycle', Icons.layers, false),
  radar('Radar', Icons.track_changes, false),
  redSweep('Red Sweep', Icons.swap_vert, false),
  wireDie('Wireframe d6', Icons.casino, false),
  sideGuns('Side Guns', Icons.gps_fixed, false),
  cornerRicochet('Corner Ricochet', Icons.radio_button_checked, false),
  hotPotato('Hot Potato', Icons.local_fire_department, false),
  comet('Comet', Icons.flare, false),
  infection('Infection', Icons.device_hub, false),
  blackoutWave('Blackout Wave', Icons.invert_colors_off, false),
  constellationDraw('Constellation Draw', Icons.share, false),
  rouletteField('Roulette Field', Icons.explore, false),
  heartbeat('Heartbeat', Icons.favorite_border, false),
  falseEndings('False Endings', Icons.replay, false);

  const _ToyKind(this.label, this.icon, this.defaultVisible);

  final String label;
  final IconData icon;
  final bool defaultVisible;

  String get preferenceKey => 'lighthouse.toy.$name.visible.v2';
}

class BoardScreenNext'''
sub_once(r'enum _ToyKind \{.*?\n\}\n\nclass BoardScreenNext', enum_code, 'toy enum')

fields = '''  final math.Random _random = math.Random();
  Map<String, double> _effectOpacities = const {};
  PhysicalPoint? _burstCenter;
  double? _burstProgress;
  bool _randomizerRunning = false;
  bool _entropyEnabled = false;
  final Map<_ToyKind, bool> _toyVisible = {
    for (final toy in _ToyKind.values) toy: toy.defaultVisible,
  };
  final Set<_ToyKind> _activeToys = {};
  Timer? _entropyTimer;
  Timer? _toyTicker;
  int _effectGeneration = 0;
  int _entropyGeneration = 0;
  double _toyClock = 0;
  double _radarAngleDegrees = 0;
  double _redSweepY = 0;
  int _redSweepDirection = 1;
  DateTime? _eventZoneEndsAt;
  PhysicalPoint? _eventZoneCenter;
  double? _eventZoneRadiusMm;
  double? _eventZoneProgress;
  double _eventZoneDismiss = 0;
  DateTime? _turnTimerEndsAt;
  double? _turnTimerProgress;
  int _dieValue = 1;
  double _dieRollPhase = 0;
  DateTime? _dieRollEndsAt;
  List<ToyProjectile> _projectiles = const [];
  List<ToyImpact> _impacts = const [];
  double _lastGunShotClock = -10;
  List<PhysicalPoint> _constellation = const [];
  double? _rouletteAngleDegrees;
  String? _heartbeatOddId;
  double _heartbeatStartedAt = 0;
  final Map<String, List<PhysicalPoint>> _ghostTrails = {};
  bool _ghostTrailActive = false;'''
sub_once(
    r'  final math\.Random _random = math\.Random\(\);.*?  String\? _scenarioLabel;',
    fields,
    'toy fields',
)

# New subsystem. Keep the existing Light Lottery and Entropy implementations below.
subsystem = r'''  Future<void> _toggleToyVisibility(_ToyKind toy) async {
    final next = !(_toyVisible[toy] ?? toy.defaultVisible);
    if (!next) _deactivateToy(toy);
    setState(() => _toyVisible[toy] = next);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(toy.preferenceKey, next);
  }

  static const Set<_ToyKind> _continuousLightToys = {
    _ToyKind.breathing,
    _ToyKind.nestCycle,
    _ToyKind.radar,
    _ToyKind.redSweep,
    _ToyKind.blackoutWave,
    _ToyKind.heartbeat,
  };

  void _deactivateToy(_ToyKind toy) {
    _activeToys.remove(toy);
    switch (toy) {
      case _ToyKind.lightLottery:
      case _ToyKind.hotPotato:
      case _ToyKind.comet:
      case _ToyKind.infection:
      case _ToyKind.rouletteField:
      case _ToyKind.falseEndings:
        _effectGeneration += 1;
        _randomizerRunning = false;
        _effectOpacities = const {};
        _burstCenter = null;
        _burstProgress = null;
        _rouletteAngleDegrees = null;
      case _ToyKind.entropy:
        if (_entropyEnabled) _toggleEntropy();
      case _ToyKind.ghostPaths:
        _ghostTrailActive = false;
        _ghostTrails.clear();
      case _ToyKind.eventZone:
        _eventZoneEndsAt = null;
        _eventZoneCenter = null;
        _eventZoneRadiusMm = null;
        _eventZoneProgress = null;
        _eventZoneDismiss = 0;
      case _ToyKind.turnTimer:
        _turnTimerEndsAt = null;
        _turnTimerProgress = null;
      case _ToyKind.wireDie:
        _dieRollEndsAt = null;
        _dieRollPhase = 0;
      case _ToyKind.sideGuns:
        _projectiles = _projectiles.where((p) => p.ricochet).toList();
      case _ToyKind.cornerRicochet:
        _projectiles = _projectiles.where((p) => !p.ricochet).toList();
      case _ToyKind.constellationDraw:
        _constellation = const [];
      case _ToyKind.breathing:
      case _ToyKind.nestCycle:
      case _ToyKind.radar:
      case _ToyKind.redSweep:
      case _ToyKind.blackoutWave:
      case _ToyKind.heartbeat:
        _effectOpacities = const {};
    }
    _maybeStopToyTicker();
    if (mounted) setState(() {});
  }

  void _activateToy(_ToyKind toy) {
    switch (toy) {
      case _ToyKind.lightLottery:
        _stopContinuousLightToys();
        _runLightRandomizer();
      case _ToyKind.entropy:
        _toggleEntropy();
      case _ToyKind.ghostPaths:
        _toggleGhostPaths();
      case _ToyKind.eventZone:
        _placeRandomEventZone();
      case _ToyKind.turnTimer:
        _startTurnTimer();
      case _ToyKind.breathing:
      case _ToyKind.nestCycle:
      case _ToyKind.radar:
      case _ToyKind.redSweep:
      case _ToyKind.blackoutWave:
      case _ToyKind.heartbeat:
        _toggleContinuousLightToy(toy);
      case _ToyKind.wireDie:
        _rollWireDie();
      case _ToyKind.sideGuns:
        _toggleSideGuns();
      case _ToyKind.cornerRicochet:
        _launchCornerRicochets();
      case _ToyKind.hotPotato:
        _stopContinuousLightToys();
        _runHotPotato();
      case _ToyKind.comet:
        _stopContinuousLightToys();
        _runComet();
      case _ToyKind.infection:
        _stopContinuousLightToys();
        _runInfection();
      case _ToyKind.constellationDraw:
        _drawConstellation();
      case _ToyKind.rouletteField:
        _stopContinuousLightToys();
        _runRoulette();
      case _ToyKind.falseEndings:
        _stopContinuousLightToys();
        _runFalseEnding();
    }
  }

  bool _toyIsActive(_ToyKind toy) {
    if (_activeToys.contains(toy)) return true;
    return switch (toy) {
      _ToyKind.lightLottery ||
      _ToyKind.hotPotato ||
      _ToyKind.comet ||
      _ToyKind.infection ||
      _ToyKind.rouletteField ||
      _ToyKind.falseEndings => _randomizerRunning,
      _ToyKind.entropy => _entropyEnabled,
      _ToyKind.ghostPaths => _ghostTrailActive,
      _ToyKind.eventZone => _eventZoneCenter != null,
      _ToyKind.turnTimer => _turnTimerProgress != null,
      _ToyKind.wireDie => _dieRollEndsAt != null,
      _ToyKind.sideGuns => _activeToys.contains(_ToyKind.sideGuns),
      _ToyKind.cornerRicochet => _projectiles.any((p) => p.ricochet),
      _ToyKind.constellationDraw => _constellation.isNotEmpty,
      _ToyKind.breathing ||
      _ToyKind.nestCycle ||
      _ToyKind.radar ||
      _ToyKind.redSweep ||
      _ToyKind.blackoutWave ||
      _ToyKind.heartbeat => _activeToys.contains(toy),
    };
  }

  ({double width, double height}) _physicalBoardSize() {
    final size = _webBoardSize ?? MediaQuery.sizeOf(context);
    final padding = _webBoardViewPadding ?? MediaQuery.viewPaddingOf(context);
    return (
      width: math.max(
        1.0,
        (size.width - padding.horizontal) / widget.logicalPixelsPerMm,
      ),
      height: math.max(
        1.0,
        (size.height - padding.vertical) / widget.logicalPixelsPerMm,
      ),
    );
  }

  void _stopContinuousLightToys() {
    _activeToys.removeAll(_continuousLightToys);
    _effectOpacities = const {};
  }

  void _toggleContinuousLightToy(_ToyKind toy) {
    if (_activeToys.contains(toy)) {
      _activeToys.remove(toy);
      setState(() => _effectOpacities = const {});
      _maybeStopToyTicker();
      return;
    }
    _effectGeneration += 1;
    _randomizerRunning = false;
    _stopContinuousLightToys();
    _activeToys.add(toy);
    if (toy == _ToyKind.heartbeat) {
      final elements = _controller.state.elements;
      _heartbeatOddId = elements.isEmpty
          ? null
          : elements[_random.nextInt(elements.length)].id;
      _heartbeatStartedAt = _toyClock;
    }
    _ensureToyTicker();
    setState(() {});
  }

  void _toggleGhostPaths() {
    setState(() {
      _ghostTrailActive = !_ghostTrailActive;
      _ghostTrails.clear();
      if (_ghostTrailActive) {
        for (final element in _controller.state.elements) {
          _ghostTrails[element.id] = [element.position];
        }
      }
    });
  }

  void _placeRandomEventZone() {
    final board = _physicalBoardSize();
    final maximumRadius = math.max(
      6.0,
      math.min(board.width, board.height) * 0.24,
    );
    final radius = math.min(maximumRadius, 12 + _random.nextDouble() * 18);
    final xSpan = math.max(0.0, board.width - radius * 2);
    final ySpan = math.max(0.0, board.height - radius * 2);
    setState(() {
      _eventZoneCenter = PhysicalPoint(
        radius + _random.nextDouble() * xSpan,
        radius + _random.nextDouble() * ySpan,
      );
      _eventZoneRadiusMm = radius;
      _eventZoneProgress = 1;
      _eventZoneDismiss = 0;
      _eventZoneEndsAt = DateTime.now().add(const Duration(seconds: 12));
    });
    _ensureToyTicker();
  }

  void _startTurnTimer() {
    setState(() {
      _turnTimerEndsAt = DateTime.now().add(const Duration(seconds: 30));
      _turnTimerProgress = 1;
    });
    _ensureToyTicker();
  }

  void _rollWireDie() {
    _activeToys.add(_ToyKind.wireDie);
    _dieRollEndsAt = DateTime.now().add(const Duration(milliseconds: 900));
    _dieValue = 1 + _random.nextInt(6);
    _dieRollPhase = 0;
    _ensureToyTicker();
    setState(() {});
  }

  void _toggleSideGuns() {
    if (_activeToys.remove(_ToyKind.sideGuns)) {
      _maybeStopToyTicker();
      setState(() {});
      return;
    }
    _activeToys.add(_ToyKind.sideGuns);
    _spawnSideVolley();
    _lastGunShotClock = _toyClock;
    _ensureToyTicker();
    setState(() {});
  }

  void _spawnSideVolley() {
    final board = _physicalBoardSize();
    const speed = 85.0;
    final centerX = board.width / 2;
    final centerY = board.height / 2;
    _projectiles = [
      ..._projectiles,
      ToyProjectile(
        position: PhysicalPoint(0, centerY),
        velocity: const PhysicalPoint(speed, 0),
        radiusMm: 0.8,
      ),
      ToyProjectile(
        position: PhysicalPoint(board.width, centerY),
        velocity: const PhysicalPoint(-speed, 0),
        radiusMm: 0.8,
      ),
      ToyProjectile(
        position: PhysicalPoint(centerX, 0),
        velocity: const PhysicalPoint(0, speed),
        radiusMm: 0.8,
      ),
      ToyProjectile(
        position: PhysicalPoint(centerX, board.height),
        velocity: const PhysicalPoint(0, -speed),
        radiusMm: 0.8,
      ),
    ];
  }

  void _launchCornerRicochets() {
    final board = _physicalBoardSize();
    const speed = 42.0;
    _projectiles = [
      ..._projectiles,
      ToyProjectile(
        position: const PhysicalPoint(1, 1),
        velocity: const PhysicalPoint(speed, speed * 0.73),
        radiusMm: 2.1,
        ricochet: true,
      ),
      ToyProjectile(
        position: PhysicalPoint(board.width - 1, 1),
        velocity: const PhysicalPoint(-speed * 0.81, speed),
        radiusMm: 2.1,
        ricochet: true,
      ),
      ToyProjectile(
        position: PhysicalPoint(1, board.height - 1),
        velocity: const PhysicalPoint(speed, -speed * 0.86),
        radiusMm: 2.1,
        ricochet: true,
      ),
      ToyProjectile(
        position: PhysicalPoint(board.width - 1, board.height - 1),
        velocity: const PhysicalPoint(-speed, -speed * 0.69),
        radiusMm: 2.1,
        ricochet: true,
      ),
    ];
    _ensureToyTicker();
    setState(() {});
  }

  void _ensureToyTicker() {
    _toyTicker ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      _tickToys(0.033);
    });
  }

  bool get _needsToyTicker =>
      _activeToys.any(_continuousLightToys.contains) ||
      _activeToys.contains(_ToyKind.sideGuns) ||
      _eventZoneCenter != null ||
      _turnTimerProgress != null ||
      _dieRollEndsAt != null ||
      _projectiles.isNotEmpty ||
      _impacts.isNotEmpty;

  void _maybeStopToyTicker() {
    if (_needsToyTicker) return;
    _toyTicker?.cancel();
    _toyTicker = null;
  }

  void _tickToys(double dt) {
    if (!mounted) return;
    _toyClock += dt;
    final now = DateTime.now();

    if (_activeToys.contains(_ToyKind.sideGuns) &&
        _toyClock - _lastGunShotClock >= 0.85) {
      _spawnSideVolley();
      _lastGunShotClock = _toyClock;
    }

    final eventEnds = _eventZoneEndsAt;
    if (eventEnds != null) {
      final remaining = eventEnds.difference(now).inMilliseconds / 1000;
      if (remaining <= 0) {
        _eventZoneProgress = 0;
        _eventZoneDismiss += dt / 0.65;
        if (_eventZoneDismiss >= 1) {
          _eventZoneEndsAt = null;
          _eventZoneCenter = null;
          _eventZoneRadiusMm = null;
          _eventZoneProgress = null;
          _eventZoneDismiss = 0;
        }
      } else {
        _eventZoneProgress = (remaining / 12).clamp(0, 1);
      }
    }

    final turnEnds = _turnTimerEndsAt;
    if (turnEnds != null) {
      final remaining = turnEnds.difference(now).inMilliseconds;
      if (remaining <= 0) {
        _turnTimerEndsAt = null;
        _turnTimerProgress = null;
        HapticFeedback.mediumImpact();
      } else {
        _turnTimerProgress = (remaining / 30000).clamp(0, 1);
      }
    }

    final dieEnds = _dieRollEndsAt;
    if (dieEnds != null) {
      if (now.isAfter(dieEnds)) {
        _dieRollEndsAt = null;
        _dieRollPhase = 0;
      } else {
        _dieRollPhase += dt * 9;
        if ((_toyClock * 16).floor().isEven) {
          _dieValue = 1 + _random.nextInt(6);
        }
      }
    }

    _tickProjectiles(dt);
    _updateContinuousLighting();
    setState(() {});
    _maybeStopToyTicker();
  }

  void _updateContinuousLighting() {
    final elements = _controller.state.elements;
    if (elements.isEmpty) {
      _effectOpacities = const {};
      return;
    }

    if (_activeToys.contains(_ToyKind.radar)) {
      _radarAngleDegrees = normalizeDegrees(_radarAngleDegrees + 1.8);
      final board = _physicalBoardSize();
      final center = PhysicalPoint(board.width / 2, board.height / 2);
      _effectOpacities = {
        for (final e in elements)
          e.id: _radarOpacity(e.position, center, _radarAngleDegrees),
      };
      return;
    }

    if (_activeToys.contains(_ToyKind.redSweep)) {
      final phase = (_toyClock * 0.30) % 2;
      _redSweepDirection = phase <= 1 ? 1 : -1;
      _redSweepY = phase <= 1 ? phase : 2 - phase;
      final board = _physicalBoardSize();
      final lineY = board.height * _redSweepY;
      _effectOpacities = {
        for (final e in elements)
          e.id: _sweepOpacity(e.position.yMm, lineY, _redSweepDirection),
      };
      return;
    }

    if (_activeToys.contains(_ToyKind.breathing)) {
      _effectOpacities = {
        for (final e in elements) e.id: _breathOpacity(e),
      };
      return;
    }

    if (_activeToys.contains(_ToyKind.nestCycle)) {
      final phase = ((_toyClock / 0.58).floor()) % 3;
      final wanted = [PyramidSize.large, PyramidSize.medium, PyramidSize.small][phase];
      final nestedIds = <String>{};
      for (var i = 0; i < elements.length; i++) {
        for (var j = i + 1; j < elements.length; j++) {
          if (elements[i].position.distanceTo(elements[j].position) <= 2.2) {
            nestedIds.add(elements[i].id);
            nestedIds.add(elements[j].id);
          }
        }
      }
      _effectOpacities = {
        for (final e in elements)
          e.id: nestedIds.contains(e.id) ? (e.size == wanted ? 1.0 : 0.025) : 1.0,
      };
      return;
    }

    if (_activeToys.contains(_ToyKind.blackoutWave)) {
      final phase = (_toyClock * 0.18) % 2;
      final down = phase <= 1;
      final front = down ? phase : 2 - phase;
      final board = _physicalBoardSize();
      _effectOpacities = {
        for (final e in elements)
          e.id: down
              ? (e.position.yMm / board.height <= front ? 0.025 : 1.0)
              : (e.position.yMm / board.height <= front ? 0.025 : 1.0),
      };
      return;
    }

    if (_activeToys.contains(_ToyKind.heartbeat)) {
      final elapsed = _toyClock - _heartbeatStartedAt;
      _effectOpacities = {
        for (final e in elements)
          e.id: _heartbeatOpacity(e.id == _heartbeatOddId, elapsed),
      };
      return;
    }

    if (!_randomizerRunning) _effectOpacities = const {};
  }

  double _breathOpacity(LightElement element) {
    final period = switch (element.size) {
      PyramidSize.small => 2.5,
      PyramidSize.medium => 3.6,
      PyramidSize.large => 5.0,
    };
    final phase = (element.id.hashCode.abs() % 1000) / 1000 * math.pi * 2;
    final wave = 0.5 + 0.5 * math.sin(_toyClock * math.pi * 2 / period + phase);
    return 0.035 + 0.965 * wave;
  }

  double _radarOpacity(PhysicalPoint point, PhysicalPoint center, double angle) {
    final dx = point.xMm - center.xMm;
    final dy = point.yMm - center.yMm;
    final elementAngle = normalizeDegrees(math.atan2(dy, dx) * 180 / math.pi);
    final behind = normalizeDegrees(angle - elementAngle);
    if (behind <= 10) return 1;
    if (behind <= 30) return 1 - (behind - 10) / 20 * 0.965;
    return 0.035;
  }

  double _sweepOpacity(double y, double lineY, int direction) {
    final behind = direction > 0 ? lineY - y : y - lineY;
    if (behind >= 0 && behind <= 5) return 1;
    if (behind > 5 && behind <= 25) return 1 - (behind - 5) / 20 * 0.965;
    return 0.035;
  }

  double _heartbeatOpacity(bool odd, double elapsed) {
    final drift = odd ? math.min(math.pi, elapsed * 0.23) : 0.0;
    final pulse = 0.5 + 0.5 * math.sin(_toyClock * math.pi * 1.7 + drift);
    return 0.04 + pulse * 0.96;
  }

  void _tickProjectiles(double dt) {
    if (_projectiles.isEmpty && _impacts.isEmpty) return;
    final board = _physicalBoardSize();
    final next = <ToyProjectile>[];
    final hitIds = <String>{};
    final impacts = <ToyImpact>[
      for (final impact in _impacts)
        if (impact.lifeSeconds - dt > 0)
          impact.copyWith(lifeSeconds: impact.lifeSeconds - dt),
    ];

    for (var projectile in _projectiles) {
      var position = projectile.position + projectile.velocity * dt;
      var velocity = projectile.velocity;
      var edgeHits = projectile.edgeHits;
      var escaping = projectile.escaping;

      if (projectile.ricochet) {
        if (!escaping) {
          var bounced = false;
          if (position.xMm <= 0 || position.xMm >= board.width) {
            edgeHits += 1;
            if (edgeHits >= 4) {
              escaping = true;
            } else {
              velocity = PhysicalPoint(-velocity.xMm, velocity.yMm);
              position = PhysicalPoint(
                position.xMm.clamp(0.2, board.width - 0.2),
                position.yMm,
              );
              bounced = true;
            }
          }
          if (!escaping && (position.yMm <= 0 || position.yMm >= board.height)) {
            edgeHits += 1;
            if (edgeHits >= 4) {
              escaping = true;
            } else {
              velocity = PhysicalPoint(velocity.xMm, -velocity.yMm);
              position = PhysicalPoint(
                position.xMm,
                position.yMm.clamp(0.2, board.height - 0.2),
              );
              bounced = true;
            }
          }
          if (!bounced && !escaping) {
            final hit = _controller.hitTest(position, haloMm: projectile.radiusMm);
            if (hit != null) {
              final normal = position - hit.position;
              final length = math.max(0.001, normal.distanceTo(PhysicalPoint.zero));
              final nx = normal.xMm / length;
              final ny = normal.yMm / length;
              final dot = velocity.xMm * nx + velocity.yMm * ny;
              velocity = PhysicalPoint(
                velocity.xMm - 2 * dot * nx,
                velocity.yMm - 2 * dot * ny,
              );
              position = position + velocity * 0.035;
            }
          }
        }
        final outside = position.xMm < -6 ||
            position.xMm > board.width + 6 ||
            position.yMm < -6 ||
            position.yMm > board.height + 6;
        if (!outside) {
          next.add(projectile.copyWith(
            position: position,
            velocity: velocity,
            edgeHits: edgeHits,
            escaping: escaping,
          ));
        }
        continue;
      }

      LightElement? hit;
      for (final element in _controller.state.elements) {
        if (_containsPoint(element, position)) {
          hit = element;
          break;
        }
      }
      if (hit != null) {
        hitIds.add(hit.id);
        impacts.add(ToyImpact(position: position, lifeSeconds: 0.8));
        continue;
      }
      final outside = position.xMm < -2 ||
          position.xMm > board.width + 2 ||
          position.yMm < -2 ||
          position.yMm > board.height + 2;
      if (!outside) next.add(projectile.copyWith(position: position));
    }

    _projectiles = next;
    _impacts = impacts;
    for (final id in hitIds) {
      final element = _controller.state.elementById(id);
      if (element != null) _controller.deleteElement(element);
    }
  }

  Future<void> _runHotPotato() async {
    if (_randomizerRunning || _controller.state.elements.isEmpty) return;
    final generation = ++_effectGeneration;
    _randomizerRunning = true;
    var delay = 420;
    String? chosen;
    for (var i = 0; i < 28; i++) {
      if (!mounted || generation != _effectGeneration) return;
      final elements = _controller.state.elements;
      if (elements.isEmpty) break;
      chosen = elements[_random.nextInt(elements.length)].id;
      setState(() {
        _effectOpacities = {
          for (final e in elements) e.id: e.id == chosen ? 1.0 : 0.035,
        };
      });
      await Future<void>.delayed(Duration(milliseconds: delay));
      delay = math.max(65, (delay * 0.88).round());
    }
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted || generation != _effectGeneration) return;
    setState(() {
      _randomizerRunning = false;
      _effectOpacities = const {};
    });
  }

  Future<void> _runComet() async {
    if (_randomizerRunning || _controller.state.elements.isEmpty) return;
    final generation = ++_effectGeneration;
    _randomizerRunning = true;
    final remaining = [..._controller.state.elements];
    final ordered = <LightElement>[];
    ordered.add(remaining.removeAt(_random.nextInt(remaining.length)));
    while (remaining.isNotEmpty) {
      final last = ordered.last;
      remaining.sort((a, b) => last.position
          .distanceTo(a.position)
          .compareTo(last.position.distanceTo(b.position)));
      ordered.add(remaining.removeAt(0));
    }
    for (var i = 0; i < ordered.length + 4; i++) {
      if (!mounted || generation != _effectGeneration) return;
      final opacities = <String, double>{};
      for (var j = 0; j < ordered.length; j++) {
        final behind = i - j;
        opacities[ordered[j].id] = switch (behind) {
          0 => 1.0,
          1 => 0.62,
          2 => 0.30,
          3 => 0.12,
          _ => 0.025,
        };
      }
      setState(() => _effectOpacities = opacities);
      await Future<void>.delayed(const Duration(milliseconds: 145));
    }
    if (!mounted || generation != _effectGeneration) return;
    setState(() {
      _randomizerRunning = false;
      _effectOpacities = const {};
    });
  }

  Future<void> _runInfection() async {
    if (_randomizerRunning || _controller.state.elements.isEmpty) return;
    final generation = ++_effectGeneration;
    _randomizerRunning = true;
    final infected = <String>{};
    final first = _controller.state.elements[_random.nextInt(_controller.state.elements.length)];
    infected.add(first.id);
    while (mounted && generation == _effectGeneration) {
      final elements = _controller.state.elements;
      if (infected.length >= elements.length) break;
      LightElement? best;
      var bestDistance = double.infinity;
      for (final source in elements.where((e) => infected.contains(e.id))) {
        for (final candidate in elements.where((e) => !infected.contains(e.id))) {
          final d = source.position.distanceTo(candidate.position);
          if (d < bestDistance) {
            bestDistance = d;
            best = candidate;
          }
        }
      }
      if (best == null) break;
      infected.add(best.id);
      setState(() {
        _effectOpacities = {
          for (final e in elements) e.id: infected.contains(e.id) ? 1.0 : 0.035,
        };
      });
      await Future<void>.delayed(const Duration(milliseconds: 430));
    }
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted || generation != _effectGeneration) return;
    setState(() {
      _randomizerRunning = false;
      _effectOpacities = const {};
    });
  }

  void _drawConstellation() {
    final elements = [..._controller.state.elements]..shuffle(_random);
    if (elements.length < 2) return;
    final count = math.min(elements.length, 2 + _random.nextInt(4));
    setState(() {
      _constellation = [for (final e in elements.take(count)) e.position];
    });
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _constellation = const []);
    });
  }

  Future<void> _runRoulette() async {
    if (_randomizerRunning || _controller.state.elements.isEmpty) return;
    final generation = ++_effectGeneration;
    _randomizerRunning = true;
    final board = _physicalBoardSize();
    final center = PhysicalPoint(board.width / 2, board.height / 2);
    final target = _controller.state.elements[_random.nextInt(_controller.state.elements.length)];
    final targetAngle = normalizeDegrees(math.atan2(
          target.position.yMm - center.yMm,
          target.position.xMm - center.xMm,
        ) *
        180 /
        math.pi);
    const frames = 72;
    for (var i = 0; i <= frames; i++) {
      if (!mounted || generation != _effectGeneration) return;
      final t = i / frames;
      final eased = 1 - math.pow(1 - t, 3).toDouble();
      setState(() => _rouletteAngleDegrees = normalizeDegrees((1080 + targetAngle) * eased));
      await Future<void>.delayed(const Duration(milliseconds: 28));
    }
    setState(() {
      _effectOpacities = {
        for (final e in _controller.state.elements)
          e.id: e.id == target.id ? 1.0 : 0.035,
      };
    });
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted || generation != _effectGeneration) return;
    setState(() {
      _randomizerRunning = false;
      _rouletteAngleDegrees = null;
      _effectOpacities = const {};
    });
  }

  Future<void> _runFalseEnding() async {
    if (_randomizerRunning || _controller.state.elements.isEmpty) return;
    final generation = ++_effectGeneration;
    _randomizerRunning = true;
    final elements = _controller.state.elements;
    for (var i = 0; i < 18; i++) {
      if (!mounted || generation != _effectGeneration) return;
      final id = elements[_random.nextInt(elements.length)].id;
      setState(() => _effectOpacities = {
            for (final e in _controller.state.elements)
              e.id: e.id == id ? 1.0 : 0.025,
          });
      await Future<void>.delayed(Duration(milliseconds: 80 + i * 13));
    }
    if (!mounted || generation != _effectGeneration) return;
    final first = elements[_random.nextInt(elements.length)];
    setState(() => _effectOpacities = {
          for (final e in elements) e.id: e.id == first.id ? 1 : 0.02,
        });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || generation != _effectGeneration) return;
    setState(() => _effectOpacities = {for (final e in elements) e.id: 0.0});
    await Future<void>.delayed(const Duration(milliseconds: 360));
    if (!mounted || generation != _effectGeneration) return;
    final alternatives = elements.where((e) => e.id != first.id).toList();
    final finalPick = alternatives.isEmpty
        ? first
        : alternatives[_random.nextInt(alternatives.length)];
    setState(() {
      _effectOpacities = {
        for (final e in elements) e.id: e.id == finalPick.id ? 1.0 : 0.025,
      };
      _burstCenter = finalPick.position;
      _burstProgress = 0.35;
    });
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted || generation != _effectGeneration) return;
    setState(() {
      _randomizerRunning = false;
      _effectOpacities = const {};
      _burstCenter = null;
      _burstProgress = null;
    });
  }

  PhysicalPoint? _nearestUnderlaySnapPoint()'''
sub_once(
    r'  Future<void> _toggleToyVisibility\(_ToyKind toy\) async \{.*?  PhysicalPoint\? _nearestUnderlaySnapPoint\(\)',
    subsystem,
    'toy subsystem',
)

# Ghost paths: longer straight sections, and twice the retained history.
text = text.replace(
    'trail.last.distanceTo(element.position) >= 1.2',
    'trail.last.distanceTo(element.position) >= 2.4',
)
text = text.replace('if (trail.length > 42) trail.removeAt(0);', 'if (trail.length > 84) trail.removeAt(0);')

# Dispose the shared animation ticker.
text = text.replace(
    '    _entropyTimer?.cancel();\n',
    '    _entropyTimer?.cancel();\n    _toyTicker?.cancel();\n',
    1,
)

menu = r'''  Widget _menu() => IconButton(
    tooltip: 'Menu',
    onPressed: _showMainMenu,
    icon: SizedBox(
      width: 36,
      height: 36,
      child: CustomPaint(
        painter: _MenuCirclePainter(snapDegrees: _rotationSnapDegrees),
      ),
    ),
  );

  Future<void> _showMainMenu() async {
    await _ensureMotionPermission();
    if (!mounted) return;
    const angles = <double>[0, 45, 90, 135, 180, 225, 270, 315];
    const snapOptions = <double>[15, 30, 45, 90];
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171717),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.34,
        maxChildSize: 0.94,
        builder: (context, scrollController) => StatefulBuilder(
          builder: (context, setSheetState) => ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
            children: [
              ExpansionTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('Board'),
                children: [
                  ListTile(leading: const Icon(Icons.note_add_outlined), title: const Text('New'), onTap: _newBoard),
                  ListTile(leading: const Icon(Icons.folder_open), title: const Text('Open…'), onTap: _manageSavedBoards),
                  ListTile(leading: const Icon(Icons.save_outlined), title: const Text('Save'), onTap: () => _saveBoard()),
                  ListTile(leading: const Icon(Icons.copy), title: const Text('Save a Copy…'), onTap: () => _saveBoard(asCopy: true)),
                  ListTile(leading: const Icon(Icons.drive_file_rename_outline), title: const Text('Rename…'), onTap: _renameBoard),
                  ListTile(leading: const Icon(Icons.input), title: const Text('Import Board JSON…'), onTap: _importBoard),
                  ListTile(leading: const Icon(Icons.content_copy), title: const Text('Copy Board JSON'), onTap: _exportBoard),
                  ExpansionTile(
                    leading: const Icon(Icons.grid_on),
                    title: const Text('Underlays'),
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.snap_to_grid),
                        title: const Text('Snap pieces to underlay'),
                        value: _gridSnapEnabled,
                        onChanged: (_) async {
                          await _toggleGridSnap();
                          setSheetState(() {});
                        },
                      ),
                      for (final underlay in BoardUnderlay.values)
                        ListTile(
                          leading: Icon(_controller.state.underlay == underlay ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                          title: Text(underlay.menuLabel),
                          onTap: () {
                            _selectUnderlay(underlay);
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ),
                ],
              ),
              ExpansionTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                children: [
                  ListTile(leading: const Icon(Icons.undo), title: const Text('Undo'), enabled: _controller.canUndo, onTap: _controller.canUndo ? _controller.undo : null),
                  ListTile(leading: const Icon(Icons.redo), title: const Text('Redo'), enabled: _controller.canRedo, onTap: _controller.canRedo ? _controller.redo : null),
                  ListTile(leading: const Icon(Icons.rotate_left), title: const Text('Rotate Left 15°'), onTap: () => _rotateSelected(-15)),
                  ListTile(leading: const Icon(Icons.rotate_right), title: const Text('Rotate Right 15°'), onTap: () => _rotateSelected(15)),
                  ExpansionTile(
                    leading: const Icon(Icons.explore_outlined),
                    title: const Text('Set Orientation'),
                    children: [
                      for (final angle in angles)
                        ListTile(title: Text('${angle.toInt()}°'), onTap: () => _setHeading(angle)),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.rotate_90_degrees_ccw),
                    title: Text(_rotationSnapDegrees == null ? 'Always Snap Rotation · Off' : 'Always Snap Rotation · ${_rotationSnapDegrees!.toInt()}°'),
                    children: [
                      ListTile(
                        leading: Icon(_rotationSnapDegrees == null ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                        title: const Text('Off'),
                        onTap: () async { await _setRotationSnap(null); setSheetState(() {}); },
                      ),
                      for (final degrees in snapOptions)
                        ListTile(
                          leading: Icon(_rotationSnapDegrees == degrees ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                          title: Text('${degrees.toInt()}° increments'),
                          onTap: () async { await _setRotationSnap(degrees); setSheetState(() {}); },
                        ),
                    ],
                  ),
                ],
              ),
              ExpansionTile(
                initiallyExpanded: true,
                leading: const Icon(Icons.toys_outlined),
                title: const Text('Toys'),
                children: [
                  for (final toy in _ToyKind.values)
                    ListTile(
                      leading: Icon(toy.icon),
                      title: Text(toy.label),
                      trailing: Icon((_toyVisible[toy] ?? toy.defaultVisible) ? Icons.check_box : Icons.check_box_outline_blank),
                      onTap: () async {
                        await _toggleToyVisibility(toy);
                        setSheetState(() {});
                      },
                    ),
                ],
              ),
              ExpansionTile(
                leading: const Icon(Icons.display_settings),
                title: const Text('Display'),
                children: [
                  ListTile(leading: const Icon(Icons.straighten), title: const Text('Size'), onTap: _showCalibrationCheck),
                  ListTile(leading: const Icon(Icons.brightness_6_outlined), title: const Text('Brightness'), onTap: _showBrightnessDialog),
                  ListTile(leading: const Icon(Icons.screen_lock_rotation), title: const Text('Orientation Lock'), onTap: _showOrientationLockInfo),
                  if (kIsWeb) ListTile(leading: const Icon(Icons.fullscreen), title: const Text('Full-screen'), onTap: _showWebInstallHelp),
                ],
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Instructions'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  setState(() => _instructionsVisible = true);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instructionsPane()'''
sub_once(r'  Widget _menu\(\) \{.*?  Widget _instructionsPane\(\)', menu, 'bottom sheet menu')

controls = r'''  Widget _toyControl(_ToyKind toy) {
    final active = _toyIsActive(toy);
    if (toy == _ToyKind.entropy) {
      return Semantics(
        button: true,
        toggled: _entropyEnabled,
        label: 'Delete one random footprint every 30 seconds',
        child: Tooltip(
          message: 'Entropy · delete one random footprint every 30 seconds',
          child: GestureDetector(
            onTap: _toggleEntropy,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 40,
              height: 40,
              child: CustomPaint(
                painter: _EntropyControlPainter(enabled: _entropyEnabled),
              ),
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: toy.label,
      visualDensity: VisualDensity.compact,
      onPressed: _randomizerRunning && {
        _ToyKind.lightLottery,
        _ToyKind.hotPotato,
        _ToyKind.comet,
        _ToyKind.infection,
        _ToyKind.rouletteField,
        _ToyKind.falseEndings,
      }.contains(toy)
          ? null
          : () => _activateToy(toy),
      icon: toy == _ToyKind.lightLottery
          ? Text('✦', style: TextStyle(color: active ? Colors.white : Colors.white70, fontSize: 23, fontWeight: FontWeight.w300))
          : Icon(toy.icon, size: 21, color: active ? Colors.white : Colors.white70),
    );
  }

  Widget _toyControls() => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260),
    child: Wrap(
      alignment: WrapAlignment.end,
      runAlignment: WrapAlignment.end,
      spacing: 0,
      runSpacing: 0,
      children: [
        for (final toy in _ToyKind.values)
          if (_toyVisible[toy] ?? toy.defaultVisible) _toyControl(toy),
      ],
    ),
  );
  Widget _credits()'''
sub_once(r'  Widget _toyControl\(_ToyKind toy\) \{.*?  Widget _credits\(\)', controls, 'toy controls')

new_overlay_call = '''painter: ToyOverlayPainter(
                logicalPixelsPerMm: widget.logicalPixelsPerMm,
                geometry: _controller.geometry,
                elements: _controller.state.elements,
                ghostTrails: _ghostTrails,
                ghostTrailsVisible: _ghostTrailActive,
                eventZoneCenter: _eventZoneCenter,
                eventZoneRadiusMm: _eventZoneRadiusMm,
                eventZoneProgress: _eventZoneProgress,
                eventZoneDismiss: _eventZoneDismiss,
                turnTimerProgress: _turnTimerProgress,
                radarAngleDegrees: _activeToys.contains(_ToyKind.radar) ? _radarAngleDegrees : null,
                redSweepY: _activeToys.contains(_ToyKind.redSweep) ? _redSweepY : null,
                dieValue: _activeToys.contains(_ToyKind.wireDie) ? _dieValue : null,
                dieRollPhase: _dieRollPhase,
                projectiles: _projectiles,
                impacts: _impacts,
                constellation: _constellation,
                rouletteAngleDegrees: _rouletteAngleDegrees,
              ),'''
sub_once(r'painter: ToyOverlayPainter\(.*?\n              \),', new_overlay_call, 'overlay painter invocation')

board_path.write_text(text)

overlay = r'''import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/light_element.dart';
import '../domain/physical_point.dart';
import '../domain/pyramid_geometry.dart';

class ToyProjectile {
  const ToyProjectile({
    required this.position,
    required this.velocity,
    required this.radiusMm,
    this.ricochet = false,
    this.edgeHits = 0,
    this.escaping = false,
  });

  final PhysicalPoint position;
  final PhysicalPoint velocity;
  final double radiusMm;
  final bool ricochet;
  final int edgeHits;
  final bool escaping;

  ToyProjectile copyWith({
    PhysicalPoint? position,
    PhysicalPoint? velocity,
    int? edgeHits,
    bool? escaping,
  }) => ToyProjectile(
    position: position ?? this.position,
    velocity: velocity ?? this.velocity,
    radiusMm: radiusMm,
    ricochet: ricochet,
    edgeHits: edgeHits ?? this.edgeHits,
    escaping: escaping ?? this.escaping,
  );
}

class ToyImpact {
  const ToyImpact({required this.position, required this.lifeSeconds});
  final PhysicalPoint position;
  final double lifeSeconds;

  ToyImpact copyWith({double? lifeSeconds}) => ToyImpact(
    position: position,
    lifeSeconds: lifeSeconds ?? this.lifeSeconds,
  );
}

class ToyOverlayPainter extends CustomPainter {
  const ToyOverlayPainter({
    required this.logicalPixelsPerMm,
    required this.geometry,
    required this.elements,
    required this.ghostTrails,
    required this.ghostTrailsVisible,
    required this.eventZoneCenter,
    required this.eventZoneRadiusMm,
    required this.eventZoneProgress,
    required this.eventZoneDismiss,
    required this.turnTimerProgress,
    required this.radarAngleDegrees,
    required this.redSweepY,
    required this.dieValue,
    required this.dieRollPhase,
    required this.projectiles,
    required this.impacts,
    required this.constellation,
    required this.rouletteAngleDegrees,
  });

  final double logicalPixelsPerMm;
  final PyramidGeometryProfile geometry;
  final List<LightElement> elements;
  final Map<String, List<PhysicalPoint>> ghostTrails;
  final bool ghostTrailsVisible;
  final PhysicalPoint? eventZoneCenter;
  final double? eventZoneRadiusMm;
  final double? eventZoneProgress;
  final double eventZoneDismiss;
  final double? turnTimerProgress;
  final double? radarAngleDegrees;
  final double? redSweepY;
  final int? dieValue;
  final double dieRollPhase;
  final List<ToyProjectile> projectiles;
  final List<ToyImpact> impacts;
  final List<PhysicalPoint> constellation;
  final double? rouletteAngleDegrees;

  Offset _px(PhysicalPoint point) => Offset(
    point.xMm * logicalPixelsPerMm,
    point.yMm * logicalPixelsPerMm,
  );

  @override
  void paint(Canvas canvas, Size size) {
    _paintGhostTrails(canvas);
    _paintEventZone(canvas);
    _paintTurnTimer(canvas, size);
    _paintRadar(canvas, size);
    _paintRedSweep(canvas, size);
    _paintWireDie(canvas, size);
    _paintGuns(canvas, size);
    _paintProjectiles(canvas);
    _paintImpacts(canvas);
    _paintConstellation(canvas);
    _paintRoulette(canvas, size);
  }

  void _paintGhostTrails(Canvas canvas) {
    if (!ghostTrailsVisible) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.26)
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final points in ghostTrails.values) {
      if (points.length < 2) continue;
      final path = Path()..moveTo(_px(points.first).dx, _px(points.first).dy);
      for (final point in points.skip(1)) {
        final o = _px(point);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint);
      for (var i = 0; i < points.length; i += 5) {
        canvas.drawCircle(_px(points[i]), 1.6, paint);
      }
    }
  }

  void _paintEventZone(Canvas canvas) {
    final center = eventZoneCenter;
    final radiusMm = eventZoneRadiusMm;
    final progress = eventZoneProgress;
    if (center == null || radiusMm == null || progress == null) return;
    final c = _px(center);
    final dismiss = eventZoneDismiss.clamp(0, 1);
    final radius = radiusMm * logicalPixelsPerMm * (1 - dismiss * 0.18);
    final alpha = 1 - dismiss;
    final fill = Paint()
      ..color = Colors.white.withValues(alpha: 0.08 * alpha)
      ..style = PaintingStyle.fill;
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.70 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(c, radius, fill);
    canvas.drawCircle(c, radius, ring);

    final elapsed = 1 - progress.clamp(0, 1);
    final timer = Paint()
      ..color = Colors.black.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius - 1.5),
      -math.pi / 2,
      math.pi * 2 * elapsed,
      false,
      timer,
    );

    if (dismiss > 0) {
      final shard = Paint()
        ..color = Colors.white.withValues(alpha: (1 - dismiss) * 0.65)
        ..strokeWidth = 1.5;
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2 + dismiss * 0.45;
        final inner = radius * (0.65 + dismiss * 0.15);
        final outer = radius * (0.90 + dismiss * 0.35);
        canvas.drawLine(
          Offset(c.dx + math.cos(a) * inner, c.dy + math.sin(a) * inner),
          Offset(c.dx + math.cos(a) * outer, c.dy + math.sin(a) * outer),
          shard,
        );
      }
    }
  }

  void _paintTurnTimer(Canvas canvas, Size size) {
    final progress = turnTimerProgress;
    if (progress == null) return;
    final rect = Rect.fromLTWH(11, 11, size.width - 22, size.height - 22);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    final metric = path.computeMetrics().first;
    final length = metric.length * progress.clamp(0, 1);
    final background = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final foreground = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, background);
    canvas.drawPath(metric.extractPath(0, length), foreground);
  }

  void _paintRadar(Canvas canvas, Size size) {
    final degrees = radarAngleDegrees;
    if (degrees == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radians = degrees * math.pi / 180;
    final radius = math.sqrt(size.width * size.width + size.height * size.height);
    final end = Offset(
      center.dx + math.cos(radians) * radius,
      center.dy + math.sin(radians) * radius,
    );
    final paint = Paint()
      ..color = const Color(0xFF35FF67).withValues(alpha: 0.80)
      ..strokeWidth = 1.4;
    canvas.drawLine(center, end, paint);
  }

  void _paintRedSweep(Canvas canvas, Size size) {
    final y = redSweepY;
    if (y == null) return;
    final paint = Paint()
      ..color = const Color(0xFFFF3030).withValues(alpha: 0.82)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, size.height * y), Offset(size.width, size.height * y), paint);
  }

  void _paintWireDie(Canvas canvas, Size size) {
    final value = dieValue;
    if (value == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    final s = math.min(size.width, size.height) * 0.085;
    final phase = dieRollPhase;
    final skew = math.sin(phase) * s * 0.22;
    final front = Rect.fromCenter(center: center, width: s, height: s);
    final back = front.shift(Offset(s * 0.34 + skew, -s * 0.28 + math.cos(phase) * s * 0.08));
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(front, paint);
    canvas.drawRect(back, paint);
    for (final pair in [
      (front.topLeft, back.topLeft),
      (front.topRight, back.topRight),
      (front.bottomLeft, back.bottomLeft),
      (front.bottomRight, back.bottomRight),
    ]) {
      canvas.drawLine(pair.$1, pair.$2, paint);
    }
    final tp = TextPainter(
      text: TextSpan(
        text: '$value',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: s * 0.45, fontWeight: FontWeight.w300),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintGuns(Canvas canvas, Size size) {
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

  void _paintProjectiles(Canvas canvas) {
    for (final p in projectiles) {
      canvas.drawCircle(
        _px(p.position),
        math.max(1.4, p.radiusMm * logicalPixelsPerMm),
        Paint()..color = p.ricochet ? Colors.white.withValues(alpha: 0.72) : Colors.white.withValues(alpha: 0.88),
      );
    }
  }

  void _paintImpacts(Canvas canvas) {
    for (final impact in impacts) {
      final t = (impact.lifeSeconds / 0.8).clamp(0, 1);
      final c = _px(impact.position);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: t * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      canvas.drawCircle(c, 3 + (1 - t) * 9, paint);
      canvas.drawLine(c + const Offset(-4, -4), c + const Offset(4, 4), paint);
      canvas.drawLine(c + const Offset(-4, 4), c + const Offset(4, -4), paint);
    }
  }

  void _paintConstellation(Canvas canvas) {
    if (constellation.length < 2) return;
    final path = Path();
    final first = _px(constellation.first);
    path.moveTo(first.dx, first.dy);
    for (final point in constellation.skip(1)) {
      final o = _px(point);
      path.lineTo(o.dx, o.dy);
    }
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, paint);
    for (final point in constellation) {
      canvas.drawCircle(_px(point), 3.1, paint);
    }
  }

  void _paintRoulette(Canvas canvas, Size size) {
    final degrees = rouletteAngleDegrees;
    if (degrees == null) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radians = degrees * math.pi / 180;
    final radius = math.sqrt(size.width * size.width + size.height * size.height);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.68)
      ..strokeWidth = 1.3;
    canvas.drawLine(
      center,
      Offset(center.dx + math.cos(radians) * radius, center.dy + math.sin(radians) * radius),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant ToyOverlayPainter oldDelegate) => true;
}
'''
Path('lib/ui/toy_overlay.dart').write_text(overlay)
