import 'dart:js_interop';

@JS('lighthouseOrientationAngle')
external JSNumber _orientationAngle();

double currentWebOrientationAngle() {
  try {
    return _orientationAngle().toDartDouble;
  } on Object {
    return 0;
  }
}
