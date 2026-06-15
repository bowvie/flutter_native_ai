import 'package:pigeon/pigeon.dart';

/// Pigeon contract for the app's native local AI bridges.
///
/// The generated Dart, Kotlin, and Swift files are intentionally not edited
/// directly. Change this file, then regenerate the bindings.
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/on_device_ai.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/bowvie/flutter_native_ai/OnDeviceAi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.bowvie.flutter_native_ai'),
    swiftOut:
        'ios/flutter_native_ai/Sources/flutter_native_ai/OnDeviceAi.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'flutter_native_ai',
  ),
)
/// Availability state returned by the native local AI bridge.
class LocalAiAvailabilityMessage {
  LocalAiAvailabilityMessage({
    required this.isAvailable,
    this.reason,
    this.modelStatus,
  });

  /// Whether generation can run on this host.
  bool isAvailable;

  /// Human-readable unavailable reason.
  String? reason;

  /// Raw platform model status for diagnostics.
  String? modelStatus;
}

/// Generation controls passed from Dart to the native model session.
class LocalAiGenerationConfigMessage {
  LocalAiGenerationConfigMessage({this.maxTokens, this.temperature});

  /// Soft cap for generated response length.
  int? maxTokens;

  /// Sampling temperature for the generated response.
  double? temperature;
}

/// Complete response from a non-streaming native generation request.
class LocalAiGenerationResponseMessage {
  LocalAiGenerationResponseMessage({
    required this.text,
    this.tokenCount,
    this.durationMs,
  });

  /// Generated response text.
  String text;

  /// Token count if the native framework exposes one.
  int? tokenCount;

  /// Generation duration in milliseconds.
  double? durationMs;
}

/// Snapshot emitted by the native streaming generation request.
class LocalAiStreamChunkMessage {
  LocalAiStreamChunkMessage({
    required this.text,
    required this.isDone,
    this.errorCode,
    this.errorMessage,
  });

  /// Latest generated text snapshot.
  String text;

  /// Whether this chunk completes the stream.
  bool isDone;

  /// Error code encoded into the stream when generation fails.
  String? errorCode;

  /// Error message encoded into the stream when generation fails.
  String? errorMessage;
}

/// Host methods implemented by each supported platform runner.
@HostApi()
abstract class OnDeviceAiHostApi {
  /// Checks whether the current device and OS can run local AI.
  @async
  LocalAiAvailabilityMessage availability();

  /// Stores system instructions for subsequent generations.
  @async
  void initialize(String instructions);

  /// Generates a complete response for [prompt].
  @async
  LocalAiGenerationResponseMessage generateText(
    String prompt,
    LocalAiGenerationConfigMessage config,
  );

  /// Starts an asynchronous streaming response for [prompt].
  @async
  void startStreamingText(String prompt, LocalAiGenerationConfigMessage config);

  /// Cancels the active streaming response.
  @async
  void cancelStreamingText();
}

/// Event stream used for local AI streaming text snapshots.
@EventChannelApi()
// Pigeon event channel APIs must be abstract classes, even with one stream.
// ignore: one_member_abstracts
abstract class OnDeviceAiStreamApi {
  /// Emits cumulative generation snapshots from the active native request.
  LocalAiStreamChunkMessage generationStream();
}
