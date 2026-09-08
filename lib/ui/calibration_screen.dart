import 'package:flutter/material.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.onComplete});

  final ValueChanged<double> onComplete;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  static const double _referenceMm = 50;
  static const double _largeBaseMm = 25.4;
  double _logicalPixelsPerMm = 4.8;
  bool _usePyramid = false;

  @override
  Widget build(BuildContext context) {
    final referenceWidth = _referenceMm * _logicalPixelsPerMm;
    final pyramidWidth = _largeBaseMm * _logicalPixelsPerMm;

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
                  const SizedBox(height: 20),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Ruler')),
                      ButtonSegment(value: true, label: Text('Large pyramid')),
                    ],
                    selected: {_usePyramid},
                    onSelectionChanged: (selection) {
                      setState(() => _usePyramid = selection.first);
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _usePyramid
                        ? 'Place a Large pyramid upright over the square. Adjust the slider until its base matches the square exactly. The upper-left corner stays fixed.'
                        : 'Hold a ruler to the screen with 0 aligned to the fixed left end. Adjust the slider until the right end reaches exactly 50 mm.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    height: _usePyramid ? 180 : 72,
                    width: double.infinity,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _usePyramid
                        ? Align(
                            alignment: Alignment.topLeft,
                            child: Container(
                              width: pyramidWidth,
                              height: pyramidWidth,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                            ),
                          )
                        : Container(
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
