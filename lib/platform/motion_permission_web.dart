import 'dart:js_interop';

@JS('lighthouseRequestMotionPermission')
external JSPromise<JSBoolean> _requestMotionPermission();

@JS('lighthouseMotionX')
external JSNumber _motionX();

@JS('lighthouseMotionY')
external JSNumber _motionY();

@JS('lighthouseMotionZ')
external JSNumber _motionZ();

Future<bool> requestWebMotionPermission() async {
  try {
    final result = await _requestMotionPermission().toDart;
    return result.toDart;
  } on Object {
    return false;
  }
}

({double x, double y, double z})? currentWebMotionSample() {
  try {
    final x = _motionX().toDartDouble;
    final y = _motionY().toDartDouble;
    final z = _motionZ().toDartDouble;
    if (!x.isFinite || !y.isFinite || !z.isFinite) return null;
    return (x: x, y: y, z: z);
  } on Object {
    return null;
  }
}
