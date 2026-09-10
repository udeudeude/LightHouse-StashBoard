import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../application/board_controller.dart';
import '../application/board_store.dart';
import '../domain/board_state.dart';
import '../domain/convex_geometry.dart';
import '../domain/geometry.dart';
import '../domain/light_element.dart';
import '../domain/light_structure.dart';
import '../domain/physical_point.dart';
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
  double _mouseTravelMm = 0;

  double _brightness = 1.0;
  bool _orientationLocked = false;

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _faceDownTimer;
  bool _faceDownLatched = false;
  bool _creditsVisible = false;

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
      _startFaceDownMonitoring();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_orientationLocked) return;
    _orientationLocked = true;
    final orientation = MediaQuery.orientationOf(context);
    // A physical board must not rotate underneath pieces. Lock to one exact
    // interface orientation rather than allowing its 180-degree counterpart.
    SystemChrome.setPreferredOrientations([
      orientation == Orientation.portrait
          ? DeviceOrientation.portraitUp
          : DeviceOrientation.landscapeLeft,
    ]);
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
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return;
    }
    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 180),
    ).listen(_handleAccelerometer, onError: (_) {});
  }

  void _handleAccelerometer(AccelerometerEvent event) {
    final zDominant =
        event.z.abs() > 7.2 &&
        event.z.abs() > event.x.abs() * 1.25 &&
        event.z.abs() > event.y.abs() * 1.25;
    final faceDown =
        zDominant &&
        (defaultTargetPlatform == TargetPlatform.iOS
            ? event.z > 0
            : event.z < 0);

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

    _faceDownTimer = Timer(const Duration(milliseconds: 450), () {
      _faceDownTimer = null;
      if (!mounted) return;
      _faceDownLatched = true;
      setState(() => _creditsVisible = true);
    });
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
    if (_mouseTransform || _creditsVisible) return;
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
      _controller.endTransform();
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
    final xAtBase =
        localStart.xMm + (localEnd.xMm - localStart.xMm) * crossing;
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
    if (_creditsVisible ||
        event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    final point = _toPhysical(event.localPosition);
    final target = _controller.hitTest(point, haloMm: _interactionHaloMm);
    if (target == null) return;
    _transformTarget = target;
    _mouseTransform = true;
    _mouseLast = point;
    _mouseTravelMm = 0;
    _controller.beginTransform(target);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_mouseTransform || event.kind != PointerDeviceKind.mouse) return;
    final current = _toPhysical(event.localPosition);
    final last = _mouseLast;
    if (last == null) return;
    final delta = current - last;
    _mouseTravelMm += last.distanceTo(current);
    _mouseLast = current;

    final keyboard = HardwareKeyboard.instance;
    final shift =
        keyboard.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
        keyboard.isLogicalKeyPressed(LogicalKeyboardKey.shiftRight);
    if (shift) {
      _controller.transformBy(
        PhysicalPoint.zero,
        event.delta.dx * math.pi / 360,
      );
    } else {
      _controller.transformBy(delta, 0);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_mouseTransform || event.kind != PointerDeviceKind.mouse) return;
    final target = _transformTarget;
    _controller.endTransform();
    if (target != null && _mouseTravelMm <= _tapTravelMm) {
      setState(() => _selectedId = target.id);
    }
    _mouseTransform = false;
    _mouseLast = null;
    _mouseTravelMm = 0;
    _transformTarget = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _controller.cancelTransform();
    _mouseTransform = false;
    _mouseLast = null;
    _mouseTravelMm = 0;
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
  }

  Future<void> _structureAction(String action) async {
    final selected = _selected;
    if (selected == null) return;
    var succeeded = false;
    switch (action) {
      case 'stack':
        succeeded = _controller.snapIntoNearestStructure(
          selected,
          StructureKind.stack,
        );
      case 'nest':
        succeeded = _controller.snapIntoNearestStructure(
          selected,
          StructureKind.nest,
        );
      case 'detach':
        succeeded = _controller.detachFromStructure(selected);
      case 'toggle':
        succeeded = _controller.toggleStructureKind(selected);
    }
    if (succeeded) {
      await HapticFeedback.mediumImpact();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No compatible nearby footprint.')),
      );
    }
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
        title: const Text('Verify physical size'),
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
        title: Text('Install LightHouse'),
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

  Widget _menu() {
    final selected = _selected;
    final structure = selected == null
        ? null
        : _controller.structureFor(selected);

    final structureItems = <Widget>[
      if (selected != null)
        MenuItemButton(
          onPressed: () => _structureAction('stack'),
          child: const Text('Align nearby footprint as stack'),
        ),
      if (selected != null)
        MenuItemButton(
          onPressed: () => _structureAction('nest'),
          child: const Text('Align nearby footprint as nest'),
        ),
      if (structure != null)
        MenuItemButton(
          onPressed: () => _structureAction('toggle'),
          child: Text(
            structure.kind == StructureKind.stack
                ? 'Treat structure as nest'
                : 'Treat structure as stack',
          ),
        ),
      if (structure != null)
        MenuItemButton(
          onPressed: () => _structureAction('detach'),
          child: const Text('Detach selected footprint'),
        ),
      if (selected == null)
        const MenuItemButton(
          onPressed: null,
          child: Text('Tap a footprint first'),
        ),
    ];

    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          menuChildren: [
            MenuItemButton(
              onPressed: null,
              child: Text(_controller.state.title),
            ),
            MenuItemButton(onPressed: _newBoard, child: const Text('New')),
            MenuItemButton(
              onPressed: () => _saveBoard(),
              child: const Text('Save'),
            ),
            MenuItemButton(
              onPressed: () => _saveBoard(asCopy: true),
              child: const Text('Save a copy'),
            ),
            MenuItemButton(
              onPressed: _manageSavedBoards,
              child: const Text('Saved boards'),
            ),
            MenuItemButton(
              onPressed: _renameBoard,
              child: const Text('Rename'),
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
          ],
          child: const Text('Edit'),
        ),
        SubmenuButton(
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          menuChildren: structureItems,
          child: const Text('Structure'),
        ),
        SubmenuButton(
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          menuChildren: [
            MenuItemButton(
              onPressed: _showCalibrationCheck,
              child: const Text('Verify physical size'),
            ),
            MenuItemButton(
              onPressed: widget.onRecalibrate,
              child: const Text('Recalibrate'),
            ),
            MenuItemButton(
              onPressed: _showBrightnessDialog,
              child: const Text('Brightness'),
            ),
            if (kIsWeb)
              MenuItemButton(
                onPressed: _showWebInstallHelp,
                child: const Text('Install / full-screen help'),
              ),
          ],
          child: const Text('Display'),
        ),
        SubmenuButton(
          submenuIcon: const WidgetStatePropertyAll<Widget?>(SizedBox.shrink()),
          menuChildren: [
            MenuItemButton(
              onPressed: _exportBoard,
              child: const Text('Copy board JSON'),
            ),
            MenuItemButton(
              onPressed: _importBoard,
              child: const Text('Import JSON from clipboard'),
            ),
          ],
          child: const Text('Transfer'),
        ),
      ],
      builder: (context, menuController, child) => IconButton(
        tooltip: 'Menu',
        onPressed: () {
          if (menuController.isOpen) {
            menuController.close();
          } else {
            menuController.open();
          }
        },
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white70, width: 0.55),
          ),
        ),
      ),
    );
  }

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
                SizedBox(height: 28),
                Text(
                  'Keep the device face-down to view this screen.\nTurn it face-up to return.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.viewPaddingOf(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: safePadding,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
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
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(padding: const EdgeInsets.all(8), child: _menu()),
            ),
          ),
          if (_creditsVisible) Positioned.fill(child: _credits()),
        ],
      ),
    );
  }
}
