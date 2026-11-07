import 'dart:ffi';

bool get canRetryAndroidTranscription => sizeOf<IntPtr>() == 8;
