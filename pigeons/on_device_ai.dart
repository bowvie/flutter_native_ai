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
        'darwin/flutter_native_ai/Sources/flutter_native_ai/OnDeviceAi.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'flutter_native_ai',
  ),
)
/// Current local AI support and model readiness state.
class LocalAiStatusMessage {
  LocalAiStatusMessage({
    required this.isSupported,
    required this.isReady,
    required this.canInitialize,
    required this.isInitializing,
    this.initializationProgress,
    this.reason,
    this.platformStatus,
  });

  /// Whether this platform, OS, and device can support local AI.
  bool isSupported;

  /// Whether generation can run now.
  bool isReady;

  /// Whether the native platform can initialize or download the model.
  bool canInitialize;

  /// Whether model initialization or download is currently running.
  bool isInitializing;

  /// Real initialization progress from 0 to 100, when the platform provides it.
  int? initializationProgress;

  /// Human-readable unavailable or initialization failure reason.
  String? reason;

  /// Raw platform model status for diagnostics.
  String? platformStatus;
}

/// Policy controlling whether readiness methods may initialize the model.
enum LocalAiInitializationPolicyMessage {
  /// Only check current status; never start model initialization.
  never,

  /// Initialize only when the model is supported but not ready.
  whenNeeded,

  /// Ask the platform to initialize or refresh readiness before proceeding.
  always,
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
  /// Checks the current device, OS, and model readiness.
  @async
  LocalAiStatusMessage status();

  /// Ensures the native model is ready according to [policy].
  @async
  LocalAiStatusMessage ensureReady(LocalAiInitializationPolicyMessage policy);

  /// Creates a native model session.
  @async
  String createSession(String instructions);

  /// Releases the native resources associated with [session].
  @async
  void disposeSession(String session);

  /// Generates a complete response for [prompt] in [session].
  @async
  LocalAiGenerationResponseMessage generateText(
    String session,
    String prompt,
    LocalAiGenerationConfigMessage config,
  );

  /// Starts an asynchronous streaming response for [prompt] in [session].
  @async
  void startStreamingText(
    String session,
    String prompt,
    LocalAiGenerationConfigMessage config,
  );

  /// Cancels the active streaming response for [session].
  @async
  void cancelStreamingText(String session);
}

/// Event stream used for local AI streaming text snapshots.
@EventChannelApi()
// Pigeon event channel APIs must be abstract classes, even with one stream.
// ignore: one_member_abstracts
abstract class OnDeviceAiStreamApi {
  /// Emits cumulative generation snapshots from the active native request.
  LocalAiStreamChunkMessage generationStream();

  /// Emits model initialization status snapshots.
  LocalAiStatusMessage statusStream();
}
