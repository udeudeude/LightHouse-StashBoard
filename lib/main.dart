import 'package:flutter/material.dart';

import 'application/board_store.dart';
import 'application/display_calibration.dart';
import 'domain/board_state.dart';
import 'ui/board_screen_next.dart';
import 'ui/calibration_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LightHouseApp());
}

class LightHouseApp extends StatefulWidget {
  const LightHouseApp({super.key});

  @override
  State<LightHouseApp> createState() => _LightHouseAppState();
}

class _LightHouseAppState extends State<LightHouseApp> {
  final BoardStore _store = BoardStore();
  BoardState? _board;
  CalibrationResult? _calibration;
  bool _resolvingCalibration = false;
  bool _forceManualCalibration = false;

  @override
  void initState() {
    super.initState();
    _loadBoard();
  }

  Future<void> _loadBoard() async {
    final board = await _store.load();
    if (!mounted) return;
    setState(() => _board = board);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_calibration == null &&
        !_resolvingCalibration &&
        !_forceManualCalibration) {
      _resolveCalibration();
    }
  }

  Future<void> _resolveCalibration() async {
    _resolvingCalibration = true;
    final result = await DisplayCalibrationService.resolve(context);
    if (!mounted) return;
    setState(() {
      _calibration = result;
      _resolvingCalibration = false;
      if (result == null) _forceManualCalibration = true;
    });
  }

  void _recalibrate() {
    setState(() {
      _forceManualCalibration = true;
      _calibration = null;
    });
  }

  Future<void> _completeManualCalibration(double value) async {
    await DisplayCalibrationService.saveManual(value);
    if (!mounted) return;
    setState(() {
      _calibration = CalibrationResult(
        logicalPixelsPerMm: value,
        source: 'Manual calibration',
      );
      _forceManualCalibration = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LightHouse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_board == null || _resolvingCalibration) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_forceManualCalibration || _calibration == null) {
      return CalibrationScreen(onComplete: _completeManualCalibration);
    }

    final calibration = _calibration!;
    return BoardScreenNext(
      logicalPixelsPerMm: calibration.logicalPixelsPerMm,
      initialState: _board!,
      calibrationLabel: calibration.source,
      onRecalibrate: _recalibrate,
    );
  }
}
