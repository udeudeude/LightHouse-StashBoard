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
  bool _lightLotteryToyVisible = true;
  bool _entropyToyVisible = true;
  Timer? _entropyTimer;
  int _effectGeneration = 0;
  int _entropyGeneration = 0;

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
      _startWebMotionMonitoring();
    } else if (force) {
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
      _lightLotteryToyVisible =
          preferences.getBool('lighthouse.toy.lightLottery.visible.v1') ?? true;
      _entropyToyVisible =
          preferences.getBool('lighthouse.toy.entropy.visible.v1') ?? true;
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

  Future<void> _toggleLightLotteryToyVisibility() async {
    setState(() => _lightLotteryToyVisible = !_lightLotteryToyVisible);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      'lighthouse.toy.lightLottery.visible.v1',
      _lightLotteryToyVisible,
    );
  }

  Future<void> _toggleEntropyToyVisibility() async {
    if (_entropyToyVisible && _entropyEnabled) {
      _toggleEntropy();
    }
    setState(() => _entropyToyVisible = !_entropyToyVisible);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(
      'lighthouse.toy.entropy.visible.v1',
      _entropyToyVisible,
    );
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

  Widget _checkmark(bool checked) => SizedBox(
    width: 18,
    child: checked ? const Icon(Icons.check, size: 16) : null,
  );

  Widget _menu() {
    const angles = <double>[0, 45, 90, 135, 180, 225, 270, 315];
    const snapOptions = <double>[15, 30, 45, 90];

    final fileItems = <Widget>[
      MenuItemButton(onPressed: _newBoard, child: const Text('New')),
      MenuItemButton(onPressed: _manageSavedBoards, child: const Text('Open…')),
      MenuItemButton(onPressed: () => _saveBoard(), child: const Text('Save')),
      MenuItemButton(
        onPressed: () => _saveBoard(asCopy: true),
        child: const Text('Save a Copy…'),
      ),
      MenuItemButton(onPressed: _renameBoard, child: const Text('Rename…')),
      MenuItemButton(
        onPressed: _importBoard,
        child: const Text('Import Board JSON…'),
      ),
      MenuItemButton(
        onPressed: _exportBoard,
        child: const Text('Copy Board JSON'),
      ),
    ];

    final underlayItems = <Widget>[
      MenuItemButton(
        closeOnActivate: false,
        leadingIcon: _checkmark(_gridSnapEnabled),
        onPressed: _toggleGridSnap,
        child: const Text('Snap pieces to underlay'),
      ),
      for (final underlay in BoardUnderlay.values)
        MenuItemButton(
          closeOnActivate: false,
          leadingIcon: _checkmark(_controller.state.underlay == underlay),
          onPressed: () => _selectUnderlay(underlay),
          child: Text(underlay.menuLabel),
        ),
    ];

    final toyItems = <Widget>[
      MenuItemButton(
        closeOnActivate: false,
        leadingIcon: _checkmark(_lightLotteryToyVisible),
        onPressed: _toggleLightLotteryToyVisibility,
        child: const Text('Light Lottery'),
      ),
      MenuItemButton(
        closeOnActivate: false,
        leadingIcon: _checkmark(_entropyToyVisible),
        onPressed: _toggleEntropyToyVisibility,
        child: const Text('Entropy Delete'),
      ),
    ];
    final rotationItems = <Widget>[
      MenuItemButton(
        onPressed: () => _rotateSelected(-15),
        child: const Text('Rotate Left 15°'),
      ),
      MenuItemButton(
        onPressed: () => _rotateSelected(15),
        child: const Text('Rotate Right 15°'),
      ),
      SubmenuButton(
        submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
        menuChildren: [
          for (final angle in angles)
            MenuItemButton(
              onPressed: () => _setHeading(angle),
              child: Text('${angle.toInt()}°'),
            ),
        ],
        child: const Text('Set Orientation'),
      ),
      SubmenuButton(
        submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
        menuChildren: [
          MenuItemButton(
            closeOnActivate: false,
            leadingIcon: _checkmark(_rotationSnapDegrees == null),
            onPressed: () => _setRotationSnap(null),
            child: const Text('Off'),
          ),
          for (final degrees in snapOptions)
            MenuItemButton(
              closeOnActivate: false,
              leadingIcon: _checkmark(_rotationSnapDegrees == degrees),
              onPressed: () => _setRotationSnap(degrees),
              child: Text('${degrees.toInt()}° increments'),
            ),
        ],
        child: Text(
          _rotationSnapDegrees == null
              ? 'Always Snap Rotation · Off'
              : 'Always Snap Rotation · ${_rotationSnapDegrees!.toInt()}°',
        ),
      ),
    ];

    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          menuChildren: [
            SubmenuButton(
              submenuIcon: const WidgetStatePropertyAll<Widget?>(
                SizedBox.shrink(),
              ),
              menuChildren: fileItems,
              child: const Text('File'),
            ),
            SubmenuButton(
              submenuIcon: const WidgetStatePropertyAll<Widget?>(
                SizedBox.shrink(),
              ),
              menuChildren: underlayItems,
              child: const Text('Underlays'),
            ),
          ],
          child: const Text('Board'),
        ),
        SubmenuButton(
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          menuChildren: [
            MenuItemButton(
              closeOnActivate: false,
              onPressed: _controller.canUndo ? _controller.undo : null,
              child: const Text('Undo'),
            ),
            MenuItemButton(
              closeOnActivate: false,
              onPressed: _controller.canRedo ? _controller.redo : null,
              child: const Text('Redo'),
            ),
            SubmenuButton(
              submenuIcon: const WidgetStatePropertyAll<Widget?>(
                SizedBox.shrink(),
              ),
              menuChildren: rotationItems,
              child: const Text('Rotation'),
            ),
          ],
          child: const Text('Edit'),
        ),
        SubmenuButton(
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          menuChildren: toyItems,
          child: const Text('Toys'),
        ),
        SubmenuButton(
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          menuChildren: [
            MenuItemButton(
              onPressed: _showCalibrationCheck,
              child: const Text('Size'),
            ),
            MenuItemButton(
              onPressed: _showBrightnessDialog,
              child: const Text('Brightness'),
            ),
            MenuItemButton(
              onPressed: _showOrientationLockInfo,
              child: const Text('Orientation Lock'),
            ),
            if (kIsWeb)
              MenuItemButton(
                onPressed: _showWebInstallHelp,
                child: const Text('Full-screen'),
              ),
          ],
          child: const Text('Display'),
        ),
        MenuItemButton(
          onPressed: () => setState(() => _instructionsVisible = true),
          child: const Text('Instructions'),
        ),
      ],
      builder: (context, menuController, child) => IconButton(
        tooltip: 'Menu',
        onPressed: () async {
          if (menuController.isOpen) {
            menuController.close();
            return;
          }
          await _ensureMotionPermission();
          if (mounted) menuController.open();
        },
        icon: SizedBox(
          width: 36,
          height: 36,
          child: CustomPaint(
            painter: _MenuCirclePainter(snapDegrees: _rotationSnapDegrees),
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

  Widget _toyControls() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_lightLotteryToyVisible)
        IconButton(
          tooltip: 'Light lottery',
          onPressed: _randomizerRunning ? null : _runLightRandomizer,
          icon: Text(
            '✦',
            style: TextStyle(
              color: _randomizerRunning ? Colors.white30 : Colors.white70,
              fontSize: 23,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      if (_entropyToyVisible)
        Semantics(
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
        ),
    ],
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
