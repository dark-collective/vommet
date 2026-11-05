import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Vommet: picking a speaker needs HTMLMediaElement.setSinkId, which Firefox
// (without a flag) and Safari don't have (Vommet issue 283).
bool browserCanPickAudioOutput() {
  final element = globalContext.getProperty<JSObject?>('HTMLMediaElement'.toJS);
  final prototype = element?.getProperty<JSObject?>('prototype'.toJS);
  return prototype?.has('setSinkId') ?? false;
}
