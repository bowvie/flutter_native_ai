/// Base class for all flutter_native_ai exceptions.
sealed class OnDeviceAiException implements Exception {
  const OnDeviceAiException(this.message, {this.details});

  final String message;
  final Object? details;

  @override
  String toString() => '$runtimeType: $message';
}

/// The current platform or OS does not support on-device AI.
final class OnDeviceAiUnsupportedException extends OnDeviceAiException {
  const OnDeviceAiUnsupportedException(super.message, {super.details});
}

/// On-device AI is supported but not currently available or ready.
final class OnDeviceAiUnavailableException extends OnDeviceAiException {
  const OnDeviceAiUnavailableException(super.message, {super.details});
}

/// The referenced session was not found in the native session store.
final class OnDeviceAiSessionNotFoundException extends OnDeviceAiException {
  const OnDeviceAiSessionNotFoundException(super.message, {super.details});
}

/// Text generation failed in the native bridge.
final class OnDeviceAiGenerationFailedException extends OnDeviceAiException {
  const OnDeviceAiGenerationFailedException(super.message, {super.details});
}

/// The [OnDeviceAiSession] has already been disposed.
final class OnDeviceAiSessionDisposedException extends OnDeviceAiException {
  const OnDeviceAiSessionDisposedException(super.message, {super.details});
}
