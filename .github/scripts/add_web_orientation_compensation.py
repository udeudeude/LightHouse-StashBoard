from pathlib import Path

path = Path('lib/ui/board_screen_next.dart')
text = path.read_text()

old = "import '../platform/motion_permission.dart';\nimport 'board_painter.dart';"
new = "import '../platform/motion_permission.dart';\nimport '../platform/web_orientation.dart';\nimport 'board_painter.dart';"
if old not in text:
    raise SystemExit('import anchor not found')
text = text.replace(old, new, 1)

old = """  double _brightness = 1.0;
  bool _orientationLocked = false;
  double? _rotationSnapDegrees;
"""
new = """  double _brightness = 1.0;
  bool _orientationLocked = false;
  Size? _webBoardSize;
  EdgeInsets? _webBoardPadding;
  EdgeInsets? _webBoardViewPadding;
  double? _webReferenceOrientationAngle;
  double? _rotationSnapDegrees;
"""
if old not in text:
    raise SystemExit('orientation field anchor not found')
text = text.replace(old, new, 1)

old = """  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_orientationLocked || kIsWeb) return;
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
"""
new = """  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final media = MediaQuery.of(context);
      _webBoardSize ??= media.size;
      _webBoardPadding ??= media.padding;
      _webBoardViewPadding ??= media.viewPadding;
      _webReferenceOrientationAngle ??= currentWebOrientationAngle();
    }
    if (_orientationLocked || kIsWeb) return;
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
  void didChangeMetrics() {
    if (!kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
"""
if old not in text:
    raise SystemExit('didChangeDependencies anchor not found')
text = text.replace(old, new, 1)

old = """    final mediaSize = MediaQuery.sizeOf(context);
    final padding = MediaQuery.viewPaddingOf(context);
"""
new = """    final mediaSize = _webBoardSize ?? MediaQuery.sizeOf(context);
    final padding = _webBoardViewPadding ?? MediaQuery.viewPaddingOf(context);
"""
if old not in text:
    raise SystemExit('underlay size anchor not found')
text = text.replace(old, new, 1)

old = """              : defaultTargetPlatform == TargetPlatform.iOS
              ? 'The iPhone/iPad web browser does not expose a reliable page orientation lock. The native LightHouse app can lock orientation.'
              : 'Orientation locking depends on browser and platform support. The native mobile app locks the board while it is open.',
"""
new = """              : defaultTargetPlatform == TargetPlatform.iOS
              ? 'Safari may rotate its viewport, but LightHouse freezes the board in the orientation where it opened and compensates for later turns so the play surface stays fixed to the glass.'
              : 'Orientation locking depends on browser and platform support. The native mobile app locks the board while it is open.',
"""
if old not in text:
    raise SystemExit('orientation info anchor not found')
text = text.replace(old, new, 1)

old = """  Widget _instructionsPane() {
    final size = MediaQuery.sizeOf(context);
"""
new = """  Widget _instructionsPane() {
    final size = _webBoardSize ?? MediaQuery.sizeOf(context);
"""
if old not in text:
    raise SystemExit('instructions size anchor not found')
text = text.replace(old, new, 1)

start = text.find("  @override\n  Widget build(BuildContext context) {\n")
end = text.find("\n}\n\nclass _MenuCirclePainter", start)
if start < 0 or end < 0:
    raise SystemExit('build block not found')
old_block = text[start:end]
new_block = r'''  Widget _buildBoardSurface(BuildContext surfaceContext) {
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
              child: _randomizerControls(),
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
    if (reference == null) return 0;
    final raw = currentWebOrientationAngle() - reference;
    final normalized = ((raw % 360) + 360) % 360;
    final quarterTurns = (normalized / 90).round() % 4;
    return quarterTurns * math.pi / 2;
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
'''
text = text[:start] + new_block + text[end:]
path.write_text(text)

readme = Path('README.md')
r = readme.read_text()
old = '- native mobile orientation lock; web builds explain the browser limitation and defer to the device\'s rotation lock\n'
new = '- native mobile orientation lock; iPhone/iPad web freezes the opening board frame and compensates for Safari viewport rotation so the physical play surface stays fixed to the glass\n'
if old not in r:
    raise SystemExit('README orientation line not found')
r = r.replace(old, new, 1)
readme.write_text(r)

changelog = Path('CHANGELOG.md')
c = changelog.read_text()
marker = '## Unreleased\n\n'
note = '- iPhone/iPad web now preserves the board\'s opening physical orientation and compensates for Safari viewport rotation instead of relying on browser orientation lock support.\n'
if marker not in c:
    raise SystemExit('CHANGELOG marker not found')
if note not in c:
    c = c.replace(marker, marker + note, 1)
changelog.write_text(c)

pubspec = Path('pubspec.yaml')
p = pubspec.read_text()
if 'version: 0.4.0+5' in p:
    p = p.replace('version: 0.4.0+5', 'version: 0.4.1+6', 1)
pubspec.write_text(p)
