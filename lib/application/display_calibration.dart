import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CalibrationResult {
  const CalibrationResult({
    required this.logicalPixelsPerMm,
    required this.source,
    this.deviceIdentifier,
  });

  final double logicalPixelsPerMm;
  final String source;
  final String? deviceIdentifier;
}

class DisplayCalibrationService {
  static const _manualKey = 'lighthouse-manual-logical-pixels-per-mm';
  static const _displayChannel = MethodChannel('lighthouse/display');

  static Future<CalibrationResult?> resolve(BuildContext context) async {
    final prefs = SharedPreferencesAsync();
    final savedManual = await prefs.getDouble(_manualKey);
    if (savedManual != null && savedManual > 0) {
      return CalibrationResult(
        logicalPixelsPerMm: savedManual,
        source: 'Manual calibration',
      );
    }

    if (kIsWeb) return null;

    final devicePixelRatio = View.of(context).devicePixelRatio;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final info = await DeviceInfoPlugin().iosInfo;
      final identifier = info.utsname.machine;
      final ppi = _iosPpi[identifier];
      if (ppi == null) return null;
      return CalibrationResult(
        logicalPixelsPerMm: ppi / devicePixelRatio / 25.4,
        source: 'Automatic: $identifier',
        deviceIdentifier: identifier,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final reported = await _displayChannel.invokeMapMethod<String, Object?>(
          'physicalDpi',
        );
        final xdpi = (reported?['xdpi'] as num?)?.toDouble();
        final ydpi = (reported?['ydpi'] as num?)?.toDouble();
        if (xdpi == null || ydpi == null) return null;
        final ppi = (xdpi + ydpi) / 2;
        if (ppi < 100 || ppi > 1000) return null;
        return CalibrationResult(
          logicalPixelsPerMm: ppi / devicePixelRatio / 25.4,
          source: 'Automatic: Android reported DPI',
        );
      } on PlatformException {
        return null;
      }
    }

    return null;
  }

  static Future<void> saveManual(double logicalPixelsPerMm) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setDouble(_manualKey, logicalPixelsPerMm);
  }

  static Future<void> clearManual() async {
    final prefs = SharedPreferencesAsync();
    await prefs.remove(_manualKey);
  }

  static const Map<String, double> _iosPpi = {
    'iPhone11,2': 458,
    'iPhone11,4': 458,
    'iPhone11,6': 458,
    'iPhone11,8': 326,
    'iPhone12,1': 326,
    'iPhone12,3': 458,
    'iPhone12,5': 458,
    'iPhone12,8': 326,
    'iPhone13,1': 476,
    'iPhone13,2': 460,
    'iPhone13,3': 460,
    'iPhone13,4': 458,
    'iPhone14,2': 460,
    'iPhone14,3': 458,
    'iPhone14,4': 476,
    'iPhone14,5': 460,
    'iPhone14,6': 326,
    'iPhone14,7': 460,
    'iPhone14,8': 458,
    'iPhone15,2': 460,
    'iPhone15,3': 460,
    'iPhone15,4': 460,
    'iPhone15,5': 460,
    'iPhone16,1': 460,
    'iPhone16,2': 460,
    'iPhone17,1': 460,
    'iPhone17,2': 460,
    'iPhone17,3': 460,
    'iPhone17,4': 460,
    'iPhone17,5': 460,
  };
}
