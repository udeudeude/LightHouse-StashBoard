import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../application/board_controller.dart';
import '../application/board_store.dart';
import '../domain/board_state.dart';
import '../domain/board_underlay.dart';
import '../domain/convex_geometry.dart';
import '../domain/geometry.dart';
import '../domain/light_element.dart';
import '../domain/physical_point.dart';
import '../platform/motion_permission.dart';
import '../platform/web_orientation.dart';
import 'board_painter.dart';
import 'toy_overlay.dart';

enum _ToyKind {
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

class BoardScreenNext extends StatefulWidget {
  const BoardScreenNext({
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
  State<BoardScreenNext> createState() => _BoardScreenNextState();
}

class _BoardScreenNextState extends State<BoardScreenNext>
    with WidgetsBindingObserver {
  static const double _interactionHaloMm = 7;
  static const double _tapTravelMm = 2;
  static const double _minimumLineGestureMm = 1.5;

  late final BoardController _controller;
  final BoardStore _store = BoardStore();

  LightElement? _transformTarget;
  LightElement? _preciseTarget;
  PhysicalPoint? _oneFingerStart;
  PhysicalPoint? _oneFingerLast;
  final List<PhysicalPoint> _oneFingerPath = [];
  double _lastRotation = 0;
  bool _transformStarted = false;

  String? _selectedId;
  String? _activeSavedId;

  bool _mouseTransform = false;
  PhysicalPoint? _mouseLast;

  bool _trackpadTransform = false;
  double _trackpadLastRotation = 0;
  bool _desktopScrollTransform = false;
  LightElement? _desktopScrollTarget;
  Timer? _desktopScrollEndTimer;

  double _brightness = 1.0;
  bool _orientationLocked = false;
  Size? _webBoardSize;
  EdgeInsets? _webBoardPadding;
  EdgeInsets? _webBoardViewPadding;
  double? _webReferenceOrientationAngle;
  double? _webObservedOrientationAngle;
  Timer? _webOrientationPollTimer;
  double? _rotationSnapDegrees;
  bool _gridSnapEnabled = false;
  bool _transformTranslated = false;

  final math.Random _random = math.Random();
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
  bool _ghostTrailActive = false;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _webMotionTimer;
  Timer? _faceDownTimer;
  bool _faceDownLatched = false;
  bool _creditsVisible = false;
  bool _instructionsVisible = false;
  bool _motionPermissionAttempted = false;
  double? _faceUpZSign;
  double? _faceUpCandidateSign;
  int _faceUpStableSamples = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = BoardController(initialState: widget.initialState)
      ..addListener(_refresh);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyBrightness();
      _loadInteractionPreferences();
      if (!kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
        _startFaceDownMonitoring();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final media = MediaQuery.of(context);
      _webBoardSize ??= media.size;
      _webBoardPadding ??= media.padding;
      _webBoardViewPadding ??= media.viewPadding;
      final angle = currentWebOrientationAngle();
      _webReferenceOrientationAngle ??= angle;
      _webObservedOrientationAngle ??= angle;
      _webOrientationPollTimer ??= Timer.periodic(
        const Duration(milliseconds: 120),
        (_) => _pollWebOrientation(),
      );
    }
    if (_orientationLocked || kIsWeb) return;
    _orientationLocked = true;
    final orientation = MediaQuery.orientationOf(context);
    SystemChrome.setPreferredOrientations([
      orientation == Orientation.portrait
          ? DeviceOrientation.portraitUp
          : DeviceOrientation.landscapeLeft,
    ]);
  }

  void _pollWebOrientation() {
    if (!mounted || !kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final angle = currentWebOrientationAngle();
    if (angle == _webObservedOrientationAngle) return;
    setState(() => _webObservedOrientationAngle = angle);
  }

  @override
  void didChangeMetrics() {
    if (!kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _webObservedOrientationAngle = currentWebOrientationAngle();
        setState(() {});
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _pollWebOrientation();
    });
    Future<void>.delayed(const Duration(milliseconds: 340), () {
      if (mounted) _pollWebOrientation();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.resumed) {
      _applyBrightness();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ScreenBrightness.instance.resetApplicationScreenBrightness();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _faceDownTimer?.cancel();
    _webMotionTimer?.cancel();
    _webOrientationPollTimer?.cancel();
    _desktopScrollEndTimer?.cancel();
    _entropyTimer?.cancel();
    _toyTicker?.cancel();
    _effectGeneration += 1;
    _entropyGeneration += 1;
    _accelerometerSubscription?.cancel();
    _controller.removeListener(_refresh);
    _controller.dispose();
    WakelockPlus.disable();
    if (!kIsWeb) {
      ScreenBrightness.instance.resetApplicationScreenBrightness();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  Future<void> _applyBrightness() async {
    if (kIsWeb) return;
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(
        _brightness,
      );
    } on Object {
      // Brightness control is optional.
    }
  }

  void _startFaceDownMonitoring() {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _startWebMotionMonitoring();
      return;
    }
    if (_accelerometerSubscription != null) return;
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 140),
    ).listen(_handleAccelerometer, onError: (_) {});
  }

  void _startWebMotionMonitoring() {
    if (!kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _webMotionTimer?.cancel();
    _webMotionTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final sample = currentWebMotionSample();
      if (sample != null) {
        _handleAcceleration(sample.x, sample.y, sample.z);
      }
    });
  }

  Future<void> _ensureMotionPermission({bool force = false}) async {
    if (!kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      _startFaceDownMonitoring();
      return;
    }
    if (_motionPermissionAttempted && !force) return;
    _motionPermissionAttempted = true;
    final granted = await requestWebMotionPermission();
    if (!mounted) return;
    if (granted) {
      _faceUpZSign = null;
      _faceUpCandidateSign = null;
      _faceUpStableSamples = 0;
      _startWebMotionMonitoring();
    } else {
      _motionPermissionAttempted = false;
      if (!force) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Motion access was not granted.')),
      );
    }
  }

  void _handleAccelerometer(AccelerometerEvent event) {
    _handleAcceleration(event.x, event.y, event.z);
  }

  void _handleAcceleration(double x, double y, double z) {
    final zDominant =
        z.abs() > 6.0 && z.abs() > x.abs() * 1.05 && z.abs() > y.abs() * 1.05;
    if (!zDominant) {
      _faceDownTimer?.cancel();
      _faceDownTimer = null;
      return;
    }

    final sign = z.sign;
    if (_faceUpZSign == null) {
      if (_faceUpCandidateSign == sign) {
        _faceUpStableSamples += 1;
      } else {
        _faceUpCandidateSign = sign;
        _faceUpStableSamples = 1;
      }
      if (_faceUpStableSamples >= 3) {
        _faceUpZSign = sign;
      }
      return;
    }

    final faceDown = sign != _faceUpZSign;
    if (!faceDown) {
      _faceDownTimer?.cancel();
      _faceDownTimer = null;
      _faceDownLatched = false;
      if (_creditsVisible && mounted) {
        setState(() => _creditsVisible = false);
      }
      return;
    }
    if (_faceDownLatched || _faceDownTimer != null) return;

    _faceDownTimer = Timer(const Duration(milliseconds: 360), () {
      _faceDownTimer = null;
      if (!mounted) return;
      _faceDownLatched = true;
      setState(() => _creditsVisible = true);
    });
  }

  Future<void> _loadInteractionPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    final snap = preferences.getDouble('lighthouse.rotationSnapDegrees.v1');
    setState(() {
      _rotationSnapDegrees = snap != null && snap > 0 ? snap : null;
      _gridSnapEnabled =
          preferences.getBool('lighthouse.gridSnapEnabled.v1') ?? false;
      for (final toy in _ToyKind.values) {
        _toyVisible[toy] =
            preferences.getBool(toy.preferenceKey) ?? toy.defaultVisible;
      }
    });
  }

  Future<void> _setRotationSnap(double? degrees) async {
    setState(() => _rotationSnapDegrees = degrees);
    final preferences = await SharedPreferences.getInstance();
    if (degrees == null) {
      await preferences.remove('lighthouse.rotationSnapDegrees.v1');
    } else {
      await preferences.setDouble('lighthouse.rotationSnapDegrees.v1', degrees);
    }
  }

  Future<void> _toggleGridSnap() async {
    setState(() => _gridSnapEnabled = !_gridSnapEnabled);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      'lighthouse.gridSnapEnabled.v1',
      _gridSnapEnabled,
    );
  }

  Future<void> _toggleToyVisibility(_ToyKind toy) async {
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
        _eventZoneProgress = (remaining / 12).clamp(0, 1).toDouble();
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
        _turnTimerProgress = (remaining / 30000).clamp(0, 1).toDouble();
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
      _effectOpacities = {for (final e in elements) e.id: _breathOpacity(e)};
      return;
    }

    if (_activeToys.contains(_ToyKind.nestCycle)) {
      final phase = ((_toyClock / 0.58).floor()) % 3;
      final wanted = [
        PyramidSize.large,
        PyramidSize.medium,
        PyramidSize.small,
      ][phase];
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
          e.id: nestedIds.contains(e.id)
              ? (e.size == wanted ? 1.0 : 0.025)
              : 1.0,
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

  double _radarOpacity(
    PhysicalPoint point,
    PhysicalPoint center,
    double angle,
  ) {
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
      var position =
          projectile.position +
          PhysicalPoint(
            projectile.velocity.xMm * dt,
            projectile.velocity.yMm * dt,
          );
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
          if (!escaping &&
              (position.yMm <= 0 || position.yMm >= board.height)) {
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
            final hit = _controller.hitTest(
              position,
              haloMm: projectile.radiusMm,
            );
            if (hit != null) {
              final normal = position - hit.position;
              final length = math.max(
                0.001,
                normal.distanceTo(PhysicalPoint.zero),
              );
              final nx = normal.xMm / length;
              final ny = normal.yMm / length;
              final dot = velocity.xMm * nx + velocity.yMm * ny;
              velocity = PhysicalPoint(
                velocity.xMm - 2 * dot * nx,
                velocity.yMm - 2 * dot * ny,
              );
              position =
                  position +
                  PhysicalPoint(velocity.xMm * 0.035, velocity.yMm * 0.035);
            }
          }
        }
        final outside =
            position.xMm < -6 ||
            position.xMm > board.width + 6 ||
            position.yMm < -6 ||
            position.yMm > board.height + 6;
        if (!outside) {
          next.add(
            projectile.copyWith(
              position: position,
              velocity: velocity,
              edgeHits: edgeHits,
              escaping: escaping,
            ),
          );
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
      final outside =
          position.xMm < -2 ||
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
      remaining.sort(
        (a, b) => last.position
            .distanceTo(a.position)
            .compareTo(last.position.distanceTo(b.position)),
      );
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
    final first = _controller
        .state
        .elements[_random.nextInt(_controller.state.elements.length)];
    infected.add(first.id);
    while (mounted && generation == _effectGeneration) {
      final elements = _controller.state.elements;
      if (infected.length >= elements.length) break;
      LightElement? best;
      var bestDistance = double.infinity;
      for (final source in elements.where((e) => infected.contains(e.id))) {
        for (final candidate in elements.where(
          (e) => !infected.contains(e.id),
        )) {
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
    final target = _controller
        .state
        .elements[_random.nextInt(_controller.state.elements.length)];
    final targetAngle = normalizeDegrees(
      math.atan2(
            target.position.yMm - center.yMm,
            target.position.xMm - center.xMm,
          ) *
          180 /
          math.pi,
    );
    const frames = 72;
    for (var i = 0; i <= frames; i++) {
      if (!mounted || generation != _effectGeneration) return;
      final t = i / frames;
      final eased = 1 - math.pow(1 - t, 3).toDouble();
      setState(
        () => _rouletteAngleDegrees = normalizeDegrees(
          (1080 + targetAngle) * eased,
        ),
      );
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
      setState(
        () => _effectOpacities = {
          for (final e in _controller.state.elements)
            e.id: e.id == id ? 1.0 : 0.025,
        },
      );
      await Future<void>.delayed(Duration(milliseconds: 80 + i * 13));
    }
    if (!mounted || generation != _effectGeneration) return;
    final first = elements[_random.nextInt(elements.length)];
    setState(
      () => _effectOpacities = {
        for (final e in elements) e.id: e.id == first.id ? 1 : 0.02,
      },
    );
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

  PhysicalPoint? _nearestUnderlaySnapPoint() {
    if (!_gridSnapEnabled || !_transformTranslated) return null;
    final targetId = _transformTarget?.id ?? _desktopScrollTarget?.id;
    if (targetId == null) return null;
    final target = _controller.state.elementById(targetId);
    if (target == null || !_controller.state.underlay.isVisible) return null;
    final mediaSize = _webBoardSize ?? MediaQuery.sizeOf(context);
    final padding = _webBoardViewPadding ?? MediaQuery.viewPaddingOf(context);
    final widthPx = mediaSize.width - padding.horizontal;
    final heightPx = mediaSize.height - padding.vertical;
    return _controller.state.underlay.nearestSnapPoint(
      target.position,
      boardWidthMm: widthPx / widget.logicalPixelsPerMm,
      boardHeightMm: heightPx / widget.logicalPixelsPerMm,
    );
  }

  void _endTransformWithSnaps({bool includeGrid = true}) {
    _controller.endTransform(
      snapDegrees: _rotationSnapDegrees,
      snapPosition: includeGrid ? _nearestUnderlaySnapPoint() : null,
    );
    _transformTranslated = false;
  }

  Future<void> _runLightRandomizer() async {
    if (_randomizerRunning || _controller.state.elements.isEmpty) return;
    final generation = ++_effectGeneration;
    setState(() {
      _randomizerRunning = true;
      _effectOpacities = {
        for (final element in _controller.state.elements) element.id: 0.0,
      };
      _burstCenter = null;
      _burstProgress = null;
    });

    Future<bool> wait(Duration duration) async {
      await Future<void>.delayed(duration);
      return mounted && generation == _effectGeneration;
    }

    const beat = Duration(milliseconds: 120);
    if (!await wait(beat)) return;
    final milliseconds = 3000 + _random.nextInt(7001);
    final endAt = DateTime.now().add(Duration(milliseconds: milliseconds));
    String? previousId;
    while (DateTime.now().isBefore(endAt)) {
      final elements = _controller.state.elements;
      if (elements.isEmpty) break;
      final candidates = previousId == null || elements.length == 1
          ? elements
          : elements.where((element) => element.id != previousId).toList();
      final element = candidates[_random.nextInt(candidates.length)];
      if (!mounted || generation != _effectGeneration) return;
      setState(() {
        _effectOpacities = {
          for (final current in elements)
            current.id: current.id == element.id ? 1.0 : 0.0,
        };
      });
      previousId = element.id;
      if (!await wait(beat)) return;
    }
    final elements = _controller.state.elements;
    if (elements.isEmpty || !mounted || generation != _effectGeneration) {
      if (mounted) {
        setState(() {
          _randomizerRunning = false;
          _effectOpacities = const {};
        });
      }
      return;
    }

    setState(() {
      _effectOpacities = {for (final element in elements) element.id: 0};
    });
    if (!await wait(const Duration(milliseconds: 240))) return;

    final winner = elements[_random.nextInt(elements.length)];
    setState(() {
      _effectOpacities = {
        for (final element in elements)
          element.id: element.id == winner.id ? 1.0 : 0.0,
      };
      _burstCenter = winner.position;
      _burstProgress = 0.0;
    });

    for (var frame = 0; frame <= 42; frame += 1) {
      if (!mounted || generation != _effectGeneration) return;
      setState(() => _burstProgress = frame / 42);
      if (!await wait(const Duration(milliseconds: 20))) return;
    }
    setState(() => _burstProgress = null);

    for (var frame = 0; frame <= 36; frame += 1) {
      if (!mounted || generation != _effectGeneration) return;
      final opacity = frame / 36;
      final currentIds = _controller.state.elements.map((e) => e.id).toSet();
      setState(() {
        _effectOpacities = {
          for (final id in currentIds) id: id == winner.id ? 1 : opacity,
        };
      });
      if (!await wait(const Duration(milliseconds: 36))) return;
    }

    if (!mounted || generation != _effectGeneration) return;
    setState(() {
      _randomizerRunning = false;
      _effectOpacities = const {};
      _burstCenter = null;
      _burstProgress = null;
    });
  }

  void _toggleEntropy() {
    _entropyGeneration += 1;
    _entropyTimer?.cancel();
    setState(() => _entropyEnabled = !_entropyEnabled);
    if (!_entropyEnabled) return;
    _entropyTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fadeAndDeleteRandomElement(),
    );
  }

  Future<void> _fadeAndDeleteRandomElement() async {
    if (!_entropyEnabled || _randomizerRunning) return;
    final elements = _controller.state.elements;
    if (elements.isEmpty) return;
    final generation = _entropyGeneration;
    final victim = elements[_random.nextInt(elements.length)];
    for (var frame = 0; frame <= 24; frame += 1) {
      if (!mounted ||
          generation != _entropyGeneration ||
          !_entropyEnabled ||
          _randomizerRunning) {
        return;
      }
      final opacity = 1 - frame / 24;
      setState(() {
        _effectOpacities = {..._effectOpacities, victim.id: opacity};
      });
      await Future<void>.delayed(const Duration(milliseconds: 45));
    }
    if (!mounted || generation != _entropyGeneration || !_entropyEnabled)
      return;
    final current = _controller.state.elementById(victim.id);
    if (current != null) _controller.deleteElement(current);
    if (mounted) {
      setState(() {
        final next = Map<String, double>.from(_effectOpacities)
          ..remove(victim.id);
        _effectOpacities = next;
      });
    }
  }

  void _refresh() {
    if (!mounted) return;
    if (_ghostTrailActive) {
      final liveIds = _controller.state.elements
          .map((element) => element.id)
          .toSet();
      _ghostTrails.removeWhere((id, _) => !liveIds.contains(id));
      for (final element in _controller.state.elements) {
        final trail = _ghostTrails.putIfAbsent(
          element.id,
          () => <PhysicalPoint>[],
        );
        if (trail.isEmpty || trail.last.distanceTo(element.position) >= 2.4) {
          trail.add(element.position);
          if (trail.length > 84) trail.removeAt(0);
        }
      }
    }
    setState(() {
      if (_selectedId != null &&
          _controller.state.elementById(_selectedId!) == null) {
        _selectedId = null;
      }
    });
    _store.save(_controller.state);
  }

  PhysicalPoint _toPhysical(Offset point) => PhysicalPoint(
    point.dx / widget.logicalPixelsPerMm,
    point.dy / widget.logicalPixelsPerMm,
  );

  LightElement? get _selected =>
      _selectedId == null ? null : _controller.state.elementById(_selectedId!);

  bool _containsPoint(LightElement element, PhysicalPoint point) {
    final polygon = polygonForElement(element, _controller.geometry);
    double? sign;
    for (var i = 0; i < polygon.length; i += 1) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final cross =
          (b.xMm - a.xMm) * (point.yMm - a.yMm) -
          (b.yMm - a.yMm) * (point.xMm - a.xMm);
      if (cross.abs() < 0.0001) continue;
      final currentSign = cross.sign;
      sign ??= currentSign;
      if (currentSign != sign) return false;
    }
    return true;
  }

  LightElement? _exactHit(PhysicalPoint point) {
    for (final element in _controller.state.elements.reversed) {
      if (_containsPoint(element, point)) return element;
    }
    return null;
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    if (_creditsVisible) return;
    final point = _toPhysical(details.localPosition);
    final target = _controller.hitTest(point, haloMm: _interactionHaloMm);
    if (target == null) {
      _controller.createAt(point);
    } else {
      _controller.cycleSizeOrDelete(target);
    }
    HapticFeedback.selectionClick();
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_mouseTransform || _creditsVisible) return;
    final point = _toPhysical(details.localFocalPoint);
    _preciseTarget = _exactHit(point);
    _transformTarget = _controller.hitTest(point, haloMm: _interactionHaloMm);
    _oneFingerStart = point;
    _oneFingerLast = point;
    _oneFingerPath
      ..clear()
      ..add(point);
    _lastRotation = 0;
    _transformStarted = false;
    _transformTranslated = false;
    if (_transformTarget != null) {
      setState(() => _selectedId = _transformTarget!.id);
    }

    if (details.pointerCount >= 2 && _transformTarget != null) {
      _controller.beginTransform(_transformTarget!);
      _transformStarted = true;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_mouseTransform || _creditsVisible) return;
    final current = _toPhysical(details.localFocalPoint);

    if (details.pointerCount >= 2) {
      _transformTarget ??= _controller.hitTest(
        current,
        haloMm: _interactionHaloMm,
      );
      final target = _transformTarget;
      if (target == null) return;
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
      if (delta.distanceTo(PhysicalPoint.zero) > 0.35) {
        _transformTranslated = true;
      }
      _controller.transformBy(delta, rotationDelta);
      return;
    }

    if (_transformStarted) return;
    _oneFingerLast = current;
    if (_oneFingerPath.isEmpty ||
        _oneFingerPath.last.distanceTo(current) >= 0.7) {
      _oneFingerPath.add(current);
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_mouseTransform || _creditsVisible) return;
    if (_transformStarted) {
      _endTransformWithSnaps();
      HapticFeedback.lightImpact();
      _clearGesture();
      return;
    }

    final start = _oneFingerStart;
    final end = _oneFingerLast;
    if (start == null || end == null) {
      _clearGesture();
      return;
    }

    final encircled = _recognizeEncirclement();
    if (encircled != null) {
      _controller.toggleIllumination(encircled);
      HapticFeedback.selectionClick();
      _clearGesture();
      return;
    }

    final drag = end - start;
    final displacement = start.distanceTo(end);
    final exact = _preciseTarget;

    if (exact != null &&
        exact.pose == PyramidPose.upright &&
        displacement >= _minimumLineGestureMm &&
        !_containsPoint(exact, end)) {
      // Tip: begin inside the actual square and cross its real edge. No halo.
      _controller.tipOrStand(exact, drag);
      HapticFeedback.mediumImpact();
      _clearGesture();
      return;
    }

    if (exact != null &&
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

    if (displacement <= _tapTravelMm) {
      final tapped = _controller.hitTest(start, haloMm: _interactionHaloMm);
      setState(() => _selectedId = tapped?.id);
    }
    _clearGesture();
  }

  bool _crossesFlatBaseEdge(
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
    final xAtBase = localStart.xMm + (localEnd.xMm - localStart.xMm) * crossing;
    return xAtBase.abs() <= halfBase;
  }

  LightElement? _recognizeEncirclement() {
    if (_oneFingerPath.length < 7) return null;

    LightElement? best;
    var bestScore = double.negativeInfinity;

    for (final element in _controller.state.elements.reversed) {
      if (element.pose != PyramidPose.upright) continue;
      final base = _controller.geometry.baseMm(element.size);
      var winding = 0.0;
      var pathLength = 0.0;
      var radiusTotal = 0.0;
      var minimumRadius = double.infinity;

      for (var i = 1; i < _oneFingerPath.length; i += 1) {
        final previous = _oneFingerPath[i - 1];
        final current = _oneFingerPath[i];
        pathLength += previous.distanceTo(current);

        final a = previous - element.position;
        final b = current - element.position;
        final radiusA = math.sqrt(a.xMm * a.xMm + a.yMm * a.yMm);
        final radiusB = math.sqrt(b.xMm * b.xMm + b.yMm * b.yMm);
        minimumRadius = math.min(minimumRadius, math.min(radiusA, radiusB));
        radiusTotal += radiusB;

        if (radiusA < 0.5 || radiusB < 0.5) continue;
        final angleA = math.atan2(a.yMm, a.xMm);
        final angleB = math.atan2(b.yMm, b.xMm);
        winding += normalizeRadians(angleB - angleA);
      }

      final closure = _oneFingerPath.first.distanceTo(_oneFingerPath.last);
      final averageRadius = radiusTotal / (_oneFingerPath.length - 1);
      final enoughTurn = winding.abs() >= math.pi * 1.55;
      final enoughPath = pathLength >= base * 2.4;
      final reasonablyClosed = closure <= math.max(14, base * 1.2);
      final staysAroundCenter = minimumRadius >= base * 0.28;
      final notRemote = averageRadius <= base * 1.8 + 18;

      if (!enoughTurn ||
          !enoughPath ||
          !reasonablyClosed ||
          !staysAroundCenter ||
          !notRemote) {
        continue;
      }

      // Winding angle is the important signal. Radius only breaks ties when a
      // loop happens to surround more than one footprint.
      final score = winding.abs() * 10 - averageRadius;
      if (score > bestScore) {
        best = element;
        bestScore = score;
      }
    }
    return best;
  }

  void _onPointerDown(PointerDownEvent event) {
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
    final point = _toPhysical(event.localPosition);
    _mouseTransform = true;
    _mouseLast = point;
    _preciseTarget = _exactHit(point);
    _transformTarget = _controller.hitTest(point, haloMm: _interactionHaloMm);
    _oneFingerStart = point;
    _oneFingerLast = point;
    _oneFingerPath
      ..clear()
      ..add(point);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_mouseTransform || event.kind != PointerDeviceKind.mouse) return;
    final current = _toPhysical(event.localPosition);
    final last = _mouseLast;
    if (last == null) return;
    _mouseLast = current;
    _oneFingerLast = current;
    if (_oneFingerPath.isEmpty ||
        _oneFingerPath.last.distanceTo(current) >= 0.7) {
      _oneFingerPath.add(current);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_mouseTransform || event.kind != PointerDeviceKind.mouse) return;
    final start = _oneFingerStart;
    final end = _oneFingerLast;
    final exact = _preciseTarget;

    if (start != null && end != null) {
      final encircled = _recognizeEncirclement();
      if (encircled != null) {
        _controller.toggleIllumination(encircled);
      } else {
        final drag = end - start;
        final displacement = start.distanceTo(end);
        if (exact != null &&
            exact.pose == PyramidPose.upright &&
            displacement >= _minimumLineGestureMm &&
            !_containsPoint(exact, end)) {
          _controller.tipOrStand(exact, drag);
        } else if (exact != null &&
            exact.pose == PyramidPose.flat &&
            displacement >= _minimumLineGestureMm &&
            _crossesFlatBaseEdge(exact, start, end)) {
          _controller.tipOrStand(exact, drag);
        } else if (displacement <= _tapTravelMm) {
          final tapped = _controller.hitTest(start, haloMm: _interactionHaloMm);
          setState(() => _selectedId = tapped?.id);
        }
      }
    }

    _mouseTransform = false;
    _mouseLast = null;
    _clearGesture();
  }

  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    if (!kIsWeb || _creditsVisible) return;
    final point = _toPhysical(event.localPosition);
    final target =
        _controller.hitTest(point, haloMm: _interactionHaloMm) ?? _selected;
    if (target == null) return;
    _finishDesktopScrollTransform();
    _trackpadTransform = true;
    _trackpadLastRotation = 0;
    _transformTarget = target;
    setState(() => _selectedId = target.id);
    _controller.beginTransform(target);
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!_trackpadTransform || !kIsWeb) return;
    final delta = PhysicalPoint(
      event.panDelta.dx / widget.logicalPixelsPerMm,
      event.panDelta.dy / widget.logicalPixelsPerMm,
    );
    final rotationDelta = event.rotation - _trackpadLastRotation;
    _trackpadLastRotation = event.rotation;
    if (delta.distanceTo(PhysicalPoint.zero) > 0.35) {
      _transformTranslated = true;
    }
    _controller.transformBy(delta, rotationDelta);
  }

  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    if (!_trackpadTransform || !kIsWeb) return;
    _endTransformWithSnaps();
    _trackpadTransform = false;
    _trackpadLastRotation = 0;
    _transformTarget = null;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!kIsWeb ||
        _creditsVisible ||
        _trackpadTransform ||
        event is! PointerScrollEvent) {
      return;
    }
    final point = _toPhysical(event.localPosition);
    final target =
        _controller.hitTest(point, haloMm: _interactionHaloMm) ?? _selected;
    if (target == null) return;

    if (!_desktopScrollTransform || _desktopScrollTarget?.id != target.id) {
      _finishDesktopScrollTransform();
      _desktopScrollTransform = true;
      _desktopScrollTarget = target;
      setState(() => _selectedId = target.id);
      _controller.beginTransform(target);
    }

    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final rotate =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    if (rotate) {
      final scroll = event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
          ? event.scrollDelta.dy
          : event.scrollDelta.dx;
      _controller.transformBy(const PhysicalPoint(0, 0), -scroll * 0.008);
    } else {
      final delta = PhysicalPoint(
        -event.scrollDelta.dx / widget.logicalPixelsPerMm,
        -event.scrollDelta.dy / widget.logicalPixelsPerMm,
      );
      if (delta.distanceTo(PhysicalPoint.zero) > 0.35) {
        _transformTranslated = true;
      }
      _controller.transformBy(delta, 0);
    }
    _desktopScrollEndTimer?.cancel();
    _desktopScrollEndTimer = Timer(
      const Duration(milliseconds: 180),
      _finishDesktopScrollTransform,
    );
  }

  void _rotateSelected(double degrees) {
    final target = _selected;
    if (target == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tap a footprint first.')));
      return;
    }
    _finishDesktopScrollTransform();
    _controller.beginTransform(target);
    _controller.transformBy(PhysicalPoint.zero, degrees * math.pi / 180);
    _controller.endTransform(snapDegrees: _rotationSnapDegrees);
  }

  void _finishDesktopScrollTransform() {
    _desktopScrollEndTimer?.cancel();
    _desktopScrollEndTimer = null;
    if (!_desktopScrollTransform) return;
    _endTransformWithSnaps();
    _desktopScrollTransform = false;
    _desktopScrollTarget = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _controller.cancelTransform();
    _mouseTransform = false;
    _mouseLast = null;
    _clearGesture();
  }

  void _clearGesture() {
    _transformTarget = null;
    _preciseTarget = null;
    _oneFingerStart = null;
    _oneFingerLast = null;
    _oneFingerPath.clear();
    _lastRotation = 0;
    _transformStarted = false;
    _transformTranslated = false;
  }

  Future<String?> _askForTitle(String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Board name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          selectAllOnFocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _saveBoard({bool asCopy = false}) async {
    final title = await _askForTitle(_controller.state.title);
    if (title == null || title.trim().isEmpty) return;
    _controller.renameBoard(title);
    final id = await _store.saveNamed(
      _controller.state,
      id: asCopy ? null : _activeSavedId,
    );
    if (!mounted) return;
    setState(() => _activeSavedId = id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(asCopy ? 'Saved a copy.' : 'Board saved.')),
    );
  }

  Future<void> _manageSavedBoards() async {
    final summaries = await _store.listSavedBoards();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: math.min(MediaQuery.sizeOf(context).height * 0.7, 520),
            child: summaries.isEmpty
                ? const Center(child: Text('No saved boards yet.'))
                : ListView.builder(
                    itemCount: summaries.length,
                    itemBuilder: (context, index) {
                      final item = summaries[index];
                      return ListTile(
                        title: Text(item.title),
                        subtitle: Text(item.updatedAt.toLocal().toString()),
                        onTap: () async {
                          final board = await _store.loadNamed(item.id);
                          if (board == null || !mounted) return;
                          _controller.replaceState(board);
                          setState(() => _activeSavedId = item.id);
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                        trailing: IconButton(
                          tooltip: 'Delete saved board',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await _store.deleteNamed(item.id);
                            summaries.removeAt(index);
                            setSheetState(() {});
                          },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportBoard() async {
    await Clipboard.setData(
      ClipboardData(text: _store.exportJson(_controller.state)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Board JSON copied to clipboard.')),
    );
  }

  Future<void> _importBoard() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = clipboard?.text;
    if (raw == null) return;
    final board = _store.importJson(raw);
    if (!mounted) return;
    if (board == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is not a LightHouse board.')),
      );
      return;
    }
    _controller.replaceState(board);
    setState(() => _activeSavedId = null);
  }

  Future<void> _renameBoard() async {
    final title = await _askForTitle(_controller.state.title);
    if (title == null) return;
    _controller.renameBoard(title);
  }

  void _setHeading(double angle) {
    final selected = _selected;
    if (selected == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tap a footprint first.')));
      return;
    }
    _controller.setHeading(selected, angle);
  }

  void _selectUnderlay(BoardUnderlay underlay) {
    _controller.setUnderlay(underlay);
  }

  Future<void> _showOrientationLockInfo() async {
    final nativeMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Orientation lock'),
        content: Text(
          nativeMobile
              ? 'LightHouse locks the board to one device orientation while it is open.'
              : defaultTargetPlatform == TargetPlatform.iOS
              ? 'Safari may rotate its viewport, but LightHouse freezes the board in the orientation where it opened and compensates for later turns so the play surface stays fixed to the glass.'
              : 'Orientation locking depends on browser and platform support. The native mobile app locks the board while it is open.',
        ),
      ),
    );
  }

  Future<void> _showBrightnessDialog() async {
    if (kIsWeb) {
      await showDialog<void>(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text('Brightness'),
          content: Text(
            'Browsers do not let LightHouse control screen brightness. Use the device brightness control.',
          ),
        ),
      );
      return;
    }

    var value = _brightness;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Board brightness'),
          content: Slider(
            min: 0.25,
            max: 1,
            value: value,
            onChanged: (next) {
              value = next;
              setDialogState(() {});
              setState(() => _brightness = next);
              _applyBrightness();
            },
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await ScreenBrightness.instance
                    .resetApplicationScreenBrightness();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Use system'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCalibrationCheck() async {
    final pixelsPerMm = widget.logicalPixelsPerMm;
    final largeBase = _controller.geometry.baseMm(PyramidSize.large);
    final recalibrate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Size'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This bar should measure exactly 25 mm:'),
            const SizedBox(height: 12),
            Container(width: 25 * pixelsPerMm, height: 6, color: Colors.white),
            const SizedBox(height: 24),
            const Text('A Large upright pyramid should fit this square:'),
            const SizedBox(height: 12),
            Container(
              width: largeBase * pixelsPerMm,
              height: largeBase * pixelsPerMm,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            const SizedBox(height: 12),
            Text(widget.calibrationLabel),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Recalibrate'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Looks right'),
          ),
        ],
      ),
    );
    if (recalibrate == true) widget.onRecalibrate();
  }

  Future<void> _showWebInstallHelp() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Full-screen'),
        content: Text(
          'On iPhone or iPad, open this site in Safari, tap Share, then Add to Home Screen. On desktop browsers, use the browser install-app command when offered.',
        ),
      ),
    );
  }

  void _newBoard() {
    _controller.newBoard();
    setState(() {
      _activeSavedId = null;
      _selectedId = null;
    });
  }

  Widget _menu() => IconButton(
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
                  ListTile(
                    leading: const Icon(Icons.note_add_outlined),
                    title: const Text('New'),
                    onTap: _newBoard,
                  ),
                  ListTile(
                    leading: const Icon(Icons.folder_open),
                    title: const Text('Open…'),
                    onTap: _manageSavedBoards,
                  ),
                  ListTile(
                    leading: const Icon(Icons.save_outlined),
                    title: const Text('Save'),
                    onTap: () => _saveBoard(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.copy),
                    title: const Text('Save a Copy…'),
                    onTap: () => _saveBoard(asCopy: true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.drive_file_rename_outline),
                    title: const Text('Rename…'),
                    onTap: _renameBoard,
                  ),
                  ListTile(
                    leading: const Icon(Icons.input),
                    title: const Text('Import Board JSON…'),
                    onTap: _importBoard,
                  ),
                  ListTile(
                    leading: const Icon(Icons.content_copy),
                    title: const Text('Copy Board JSON'),
                    onTap: _exportBoard,
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.grid_on),
                    title: const Text('Underlays'),
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.grid_4x4),
                        title: const Text('Snap pieces to underlay'),
                        value: _gridSnapEnabled,
                        onChanged: (_) async {
                          await _toggleGridSnap();
                          setSheetState(() {});
                        },
                      ),
                      for (final underlay in BoardUnderlay.values)
                        ListTile(
                          leading: Icon(
                            _controller.state.underlay == underlay
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
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
                  ListTile(
                    leading: const Icon(Icons.undo),
                    title: const Text('Undo'),
                    enabled: _controller.canUndo,
                    onTap: _controller.canUndo ? _controller.undo : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.redo),
                    title: const Text('Redo'),
                    enabled: _controller.canRedo,
                    onTap: _controller.canRedo ? _controller.redo : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.rotate_left),
                    title: const Text('Rotate Left 15°'),
                    onTap: () => _rotateSelected(-15),
                  ),
                  ListTile(
                    leading: const Icon(Icons.rotate_right),
                    title: const Text('Rotate Right 15°'),
                    onTap: () => _rotateSelected(15),
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.explore_outlined),
                    title: const Text('Set Orientation'),
                    children: [
                      for (final angle in angles)
                        ListTile(
                          title: Text('${angle.toInt()}°'),
                          onTap: () => _setHeading(angle),
                        ),
                    ],
                  ),
                  ExpansionTile(
                    leading: const Icon(Icons.rotate_90_degrees_ccw),
                    title: Text(
                      _rotationSnapDegrees == null
                          ? 'Always Snap Rotation · Off'
                          : 'Always Snap Rotation · ${_rotationSnapDegrees!.toInt()}°',
                    ),
                    children: [
                      ListTile(
                        leading: Icon(
                          _rotationSnapDegrees == null
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: const Text('Off'),
                        onTap: () async {
                          await _setRotationSnap(null);
                          setSheetState(() {});
                        },
                      ),
                      for (final degrees in snapOptions)
                        ListTile(
                          leading: Icon(
                            _rotationSnapDegrees == degrees
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text('${degrees.toInt()}° increments'),
                          onTap: () async {
                            await _setRotationSnap(degrees);
                            setSheetState(() {});
                          },
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
                      trailing: Icon(
                        (_toyVisible[toy] ?? toy.defaultVisible)
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                      ),
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
                  ListTile(
                    leading: const Icon(Icons.straighten),
                    title: const Text('Size'),
                    onTap: _showCalibrationCheck,
                  ),
                  ListTile(
                    leading: const Icon(Icons.brightness_6_outlined),
                    title: const Text('Brightness'),
                    onTap: _showBrightnessDialog,
                  ),
                  ListTile(
                    leading: const Icon(Icons.screen_lock_rotation),
                    title: const Text('Orientation Lock'),
                    onTap: _showOrientationLockInfo,
                  ),
                  if (kIsWeb)
                    ListTile(
                      leading: const Icon(Icons.fullscreen),
                      title: const Text('Full-screen'),
                      onTap: _showWebInstallHelp,
                    ),
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

  Widget _instructionsPane() {
    final size = _webBoardSize ?? MediaQuery.sizeOf(context);
    final isDesktop =
        kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final isTablet = size.shortestSide >= 600;
    final deviceName = isDesktop
        ? 'Desktop / trackpad'
        : isIos
        ? (isTablet ? 'iPad' : 'iPhone')
        : defaultTargetPlatform == TargetPlatform.android
        ? (isTablet ? 'Android tablet' : 'Android phone')
        : 'Touch device';

    final instructions = isDesktop
        ? <(String, String)>[
            ('Create / resize / delete', 'Double-click'),
            ('Select', 'Click'),
            ('Tip / stand', 'Click-drag across the actual footprint edge'),
            ('Light full / walls', 'Draw a loop around an upright footprint'),
            ('Move', 'Two-finger scroll over a footprint'),
            ('Rotate', 'Hold Shift while two-finger scrolling'),
            ('Exact rotation', 'Menu > Edit > Rotation'),
            ('Grid snap', 'Menu > Board > Underlays > Snap pieces to underlay'),
            (
              'Light lottery',
              'Enable in Menu > Toys, then tap the starburst button',
            ),
            (
              'Entropy',
              'Enable in Menu > Toys, then toggle the deletion control',
            ),
            ('More toys', 'Menu > Toys controls which toy icons appear'),
          ]
        : <(String, String)>[
            ('Create / resize / delete', 'Double-tap'),
            ('Select', 'Tap'),
            (
              'Tip / stand',
              'Drag from inside across the actual footprint edge',
            ),
            ('Light full / walls', 'Draw a loop around an upright footprint'),
            ('Move + rotate', 'Two fingers: drag and twist'),
            ('Exact rotation', 'Menu > Edit > Rotation'),
            ('Grid snap', 'Menu > Board > Underlays > Snap pieces to underlay'),
            (
              'Light lottery',
              'Enable in Menu > Toys, then tap the starburst button',
            ),
            (
              'Entropy',
              'Enable in Menu > Toys, then toggle the deletion control',
            ),
            ('More toys', 'Menu > Toys controls which toy icons appear'),
          ];

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 62),
          child: Material(
            color: const Color(0xEE171717),
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 350),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Instructions · $deviceName',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close instructions',
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setState(() => _instructionsVisible = false),
                          icon: const Icon(Icons.close, color: Colors.white70),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final item in instructions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.25,
                            ),
                            children: [
                              TextSpan(
                                text: '${item.$1}: ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: item.$2),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toyControl(_ToyKind toy) {
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
      onPressed:
          _randomizerRunning &&
              {
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
          ? Text(
              '✦',
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontSize: 23,
                fontWeight: FontWeight.w300,
              ),
            )
          : Icon(
              toy.icon,
              size: 21,
              color: active ? Colors.white : Colors.white70,
            ),
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
  Widget _credits() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: null,
    child: ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'LightHouse',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'An illuminated physical play surface for Looney Pyramids',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                SizedBox(height: 28),
                Text(
                  'Project: udeudeude\nSoftware: Flutter + ChatGPT\nLooney Pyramids: Looney Labs\nOpen source under the MIT License',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildBoardSurface(BuildContext surfaceContext) {
    final safePadding = MediaQuery.viewPaddingOf(surfaceContext);

    return Stack(
      fit: StackFit.expand,
      children: [
        Padding(
          padding: safePadding,
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            onPointerSignal: _onPointerSignal,
            onPointerPanZoomStart: _onPointerPanZoomStart,
            onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
            onPointerPanZoomEnd: _onPointerPanZoomEnd,
            child: GestureDetector(
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
                  selectedId: _selectedId,
                  elementOpacities: _effectOpacities,
                  burstCenter: _burstCenter,
                  burstProgress: _burstProgress,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        Padding(
          padding: safePadding,
          child: IgnorePointer(
            child: CustomPaint(
              painter: ToyOverlayPainter(
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
                radarAngleDegrees: _activeToys.contains(_ToyKind.radar)
                    ? _radarAngleDegrees
                    : null,
                redSweepY: _activeToys.contains(_ToyKind.redSweep)
                    ? _redSweepY
                    : null,
                dieValue: _activeToys.contains(_ToyKind.wireDie)
                    ? _dieValue
                    : null,
                dieRollPhase: _dieRollPhase,
                projectiles: _projectiles,
                impacts: _impacts,
                sideGunsVisible: _activeToys.contains(_ToyKind.sideGuns),
                cornerGunsVisible:
                    _activeToys.contains(_ToyKind.cornerRicochet) ||
                    _projectiles.any((p) => p.ricochet),
                constellation: _constellation,
                rouletteAngleDegrees: _rouletteAngleDegrees,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(padding: const EdgeInsets.all(8), child: _menu()),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _toyControls(),
            ),
          ),
        ),
        if (_instructionsVisible) _instructionsPane(),
        if (_creditsVisible) Positioned.fill(child: _credits()),
      ],
    );
  }

  double _webBoardRotationRadians() {
    final reference = _webReferenceOrientationAngle;
    final current = _webObservedOrientationAngle;
    if (reference == null || current == null) return 0;
    final raw = current - reference;
    final signed = ((raw + 540) % 360) - 180;
    final quarterTurns = (signed / 90).round();
    return -quarterTurns * math.pi / 2;
  }

  @override
  Widget build(BuildContext context) {
    final compensateForSafari =
        kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        _webBoardSize != null;

    if (!compensateForSafari) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildBoardSurface(context),
      );
    }

    final frozenSize = _webBoardSize!;
    final currentMedia = MediaQuery.of(context);
    final frozenMedia = currentMedia.copyWith(
      size: frozenSize,
      padding: _webBoardPadding ?? currentMedia.padding,
      viewPadding: _webBoardViewPadding ?? currentMedia.viewPadding,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: Transform.rotate(
            angle: _webBoardRotationRadians(),
            transformHitTests: true,
            child: SizedBox(
              width: frozenSize.width,
              height: frozenSize.height,
              child: MediaQuery(
                data: frozenMedia,
                child: Builder(builder: _buildBoardSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuCirclePainter extends CustomPainter {
  const _MenuCirclePainter({required this.snapDegrees});

  final double? snapDegrees;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 1;
    final paint = Paint()
      ..color = Colors.white70
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    canvas.drawCircle(center, radius, paint);

    final degrees = snapDegrees;
    if (degrees == null || degrees <= 0) return;
    final tickCount = (360 / degrees).round().clamp(4, 24);
    for (var i = 0; i < tickCount; i += 1) {
      final angle = -math.pi / 2 + 2 * math.pi * i / tickCount;
      final outer = radius - 0.35;
      final inner = radius - (i % 2 == 0 ? 4.5 : 3.5);
      canvas.drawLine(
        Offset(
          center.dx + inner * math.cos(angle),
          center.dy + inner * math.sin(angle),
        ),
        Offset(
          center.dx + outer * math.cos(angle),
          center.dy + outer * math.sin(angle),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MenuCirclePainter oldDelegate) =>
      oldDelegate.snapDegrees != snapDegrees;
}

class _EntropyControlPainter extends CustomPainter {
  const _EntropyControlPainter({required this.enabled});

  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = enabled ? Colors.white : Colors.white54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, 11, paint);
    canvas.drawLine(
      Offset(center.dx - 4.5, center.dy),
      Offset(center.dx + 4.5, center.dy),
      paint,
    );
    if (enabled) {
      canvas.drawCircle(center, 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_EntropyControlPainter oldDelegate) =>
      oldDelegate.enabled != enabled;
}
