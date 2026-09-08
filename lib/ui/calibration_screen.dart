import 'package:flutter/material.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.onComplete});

  final ValueChanged<double> onComplete;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const double _referenceMm = 50;
  double _logicalPixelsPerMm = 4.8;

  @override
  Widget build(BuildContext context) {
    final referenceWidth = _referenceMm * _logicalPixelsPerMm;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Calibrate physical size',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Hold a ruler to the screen with 0 aligned to the fixed left end. Adjust the slider until the right end reaches exactly 50 mm.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    height: 72,
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      width: referenceWidth,
                      height: 8,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Slider(
                    min: 2.0,
                    max: 8.0,
                    divisions: 600,
                    value: _logicalPixelsPerMm,
                    onChanged: (value) {
                      setState(() => _logicalPixelsPerMm = value);
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => widget.onComplete(_logicalPixelsPerMm),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Text('Use calibration'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
