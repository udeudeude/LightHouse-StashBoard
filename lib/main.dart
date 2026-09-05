import 'package:flutter/material.dart';

import 'ui/board_screen.dart';
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
  double? _logicalPixelsPerMm;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LightHouse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: _logicalPixelsPerMm == null
          ? CalibrationScreen(
              onComplete: (value) {
                setState(() => _logicalPixelsPerMm = value);
              },
            )
          : BoardScreen(
              logicalPixelsPerMm: _logicalPixelsPerMm!,
              onRecalibrate: () {
                setState(() => _logicalPixelsPerMm = null);
              },
            ),
    );
  }
}
