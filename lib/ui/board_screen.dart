import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../application/board_controller.dart';
import '../application/board_store.dart';
import '../domain/board_state.dart';
import '../domain/light_element.dart';
import '../domain/light_structure.dart';
import '../domain/physical_point.dart';
import 'board_painter.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({
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
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen>
    with WidgetsBindingObserver {
  static const double _interactionHaloMm = 7;
  static const double _tipThresholdMm = 4;
  static const double _scribblePathMm = 15;
  static const double _scribbleReturnMm = 4;
  static const double _tapTravelMm = 2;

  late final BoardController _controller;
  final BoardStore _store = BoardStore();

  LightElement? _gestureTarget;
  PhysicalPoint? _oneFingerStart;
  PhysicalPoint? _oneFingerLast;
  double _oneFingerPathMm = 0;
  double _lastRotation = 0;
  bool _transformStarted = false;

  String? _selectedId;
  String? _activeSavedId;
  bool _orientationLocked = false;

  bool _mouseTransform = false;
  PhysicalPoint? _mouseLast;
  double _mouseTravelMm = 0;

  double _brightness = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = BoardController(initialState: widget.initialState)
      ..addListener(_refresh);
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyBrightness());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_orientationLocked) return;
    _orientationLocked = true;
    final orientation = MediaQuery.orientationOf(context);
    SystemChrome.setPreferredOrientations(
      orientation == Orientation.portrait
          ? [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]
          : [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
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
      // Brightness is an enhancement; the board remains usable without it.
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

  void _handleDoubleTapDown(TapDownDetails details) {
    if (_mouseTransform) return;
    final point = _toPhysical(details.localPosition);
    final target = _controller.hitTest(point, haloMm: _interactionHaloMm);
    if (target == null) {
      _controller.createAt(point);
      HapticFeedback.selectionClick();
    } else {
      _controller.cycleSizeOrDelete(target);
      HapticFeedback.selectionClick();
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_mouseTransform) return;
    final point = _toPhysical(details.localFocalPoint);
    _gestureTarget = _controller.hitTest(point, haloMm: _interactionHaloMm);
    _oneFingerStart = point;
    _oneFingerLast = point;
    _oneFingerPathMm = 0;
    _lastRotation = 0;
    _transformStarted = false;

    if (details.pointerCount >= 2 && _gestureTarget != null) {
      _controller.beginTransform(_gestureTarget!);
      _transformStarted = true;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_mouseTransform) return;
    final target = _gestureTarget;
    if (target == null) return;

    if (details.pointerCount >= 2) {
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
    final current = _toPhysical(details.localFocalPoint);
    final last = _oneFingerLast;
    if (last != null) {
      final dx = current.xMm - last.xMm;
      final dy = current.yMm - last.yMm;
      _oneFingerPathMm += math.sqrt(dx * dx + dy * dy);
    }
    _oneFingerLast = current;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_mouseTransform) return;
    final target = _gestureTarget;
    if (_transformStarted) {
      _controller.endTransform();
      HapticFeedback.lightImpact();
      _clearGesture();
      return;
    }

    final start = _oneFingerStart;
    final end = _oneFingerLast;
    if (start != null && end != null) {
      final drag = PhysicalPoint(end.xMm - start.xMm, end.yMm - start.yMm);
      final displacement = math.sqrt(
        drag.xMm * drag.xMm + drag.yMm * drag.yMm,
      );

      if (target == null && displacement <= _tapTravelMm) {
        setState(() => _selectedId = null);
      } else if (target != null && displacement <= _tapTravelMm) {
        setState(() => _selectedId = target.id);
      } else if (target != null &&
          target.pose == PyramidPose.upright &&
          _oneFingerPathMm >= _scribblePathMm &&
          displacement <= _scribbleReturnMm) {
        _controller.toggleIllumination(target);
        HapticFeedback.selectionClick();
      } else if (target != null && displacement >= _tipThresholdMm) {
        _controller.tipOrStand(target, drag);
        HapticFeedback.mediumImpact();
      }
    }
    _clearGesture();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryMouseButton) {
      return;
    }
    final point = _toPhysical(event.localPosition);
    final target = _controller.hitTest(point, haloMm: _interactionHaloMm);
    if (target == null) return;
    _gestureTarget = target;
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
    final shift = keyboard.isLogicalKeyPressed(LogicalKeyboardKey.shiftLeft) ||
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
    final target = _gestureTarget;
    _controller.endTransform();
    if (target != null && _mouseTravelMm <= _tapTravelMm) {
      setState(() => _selectedId = target.id);
    }
    _mouseTransform = false;
    _mouseLast = null;
    _mouseTravelMm = 0;
    _gestureTarget = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _controller.cancelTransform();
    _mouseTransform = false;
    _mouseLast = null;
    _mouseTravelMm = 0;
    _clearGesture();
  }

  void _clearGesture() {
    _gestureTarget = null;
    _oneFingerStart = null;
    _oneFingerLast = null;
    _oneFingerPathMm = 0;
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
        const SnackBar(content: Text('No compatible nearby structure.')),
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
            Container(
              width: 25 * pixelsPerMm,
              height: 6,
              color: Colors.white,
            ),
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
          'On iPhone or iPad, open this site in Safari, tap Share, then Add to Home Screen. The installed web app gets a cleaner full-screen workspace. On desktop browsers, use the browser install-app command when offered.',
        ),
      ),
    );
  }

  Future<void> _handleBoardMenu(String value) async {
    switch (value) {
      case 'new':
        _controller.newBoard();
        setState(() {
          _activeSavedId = null;
          _selectedId = null;
        });
      case 'save':
        await _saveBoard();
      case 'save-copy':
        await _saveBoard(asCopy: true);
      case 'library':
        await _manageSavedBoards();
      case 'rename':
        await _renameBoard();
      case 'export':
        await _exportBoard();
      case 'import':
        await _importBoard();
      case 'brightness':
        await _showBrightnessDialog();
      case 'install':
        await _showWebInstallHelp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final structure = selected == null
        ? null
        : _controller.structureFor(selected);
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
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      _controller.state.title,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: _controller.canUndo
                            ? _controller.undo
                            : null,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: 'Redo',
                        onPressed: _controller.canRedo
                            ? _controller.redo
                            : null,
                        icon: const Icon(Icons.redo),
                      ),
                      if (selected != null)
                        PopupMenuButton<String>(
                          tooltip: structure == null
                              ? 'Structure actions'
                              : '${structure.kind.name} structure',
                          icon: const Icon(Icons.layers_outlined),
                          onSelected: _structureAction,
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'stack',
                              child: Text('Snap into nearby stack'),
                            ),
                            const PopupMenuItem(
                              value: 'nest',
                              child: Text('Snap into nearby nest'),
                            ),
                            if (structure != null)
                              const PopupMenuItem(
                                value: 'toggle',
                                child: Text('Toggle stack / nest'),
                              ),
                            if (structure != null)
                              const PopupMenuItem(
                                value: 'detach',
                                child: Text('Detach this footprint'),
                              ),
                          ],
                        ),
                      IconButton(
                        tooltip: widget.calibrationLabel,
                        onPressed: _showCalibrationCheck,
                        icon: const Icon(Icons.straighten),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Board menu',
                        icon: const Icon(Icons.more_horiz),
                        onSelected: _handleBoardMenu,
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'new',
                            child: Text('New board'),
                          ),
                          const PopupMenuItem(
                            value: 'save',
                            child: Text('Save board'),
                          ),
                          const PopupMenuItem(
                            value: 'save-copy',
                            child: Text('Save a copy'),
                          ),
                          const PopupMenuItem(
                            value: 'library',
                            child: Text('Saved boards'),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename board'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'export',
                            child: Text('Copy board JSON'),
                          ),
                          const PopupMenuItem(
                            value: 'import',
                            child: Text('Import JSON from clipboard'),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'brightness',
                            child: Text('Brightness'),
                          ),
                          if (kIsWeb)
                            const PopupMenuItem(
                              value: 'install',
                              child: Text('Install / full-screen help'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
