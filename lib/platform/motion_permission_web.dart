import 'dart:js_interop';

@JS('lighthouseRequestMotionPermission')
external JSPromise<JSBoolean> _requestMotionPermission();

Future<bool> requestWebMotionPermission() async {
  try {
    final result = await _requestMotionPermission().toDart;
    return result.toDart;
  } on Object {
    return false;
  }
}
