import 'dart:async';

import 'package:flutter/services.dart';

import 'generated/on_device_ai.g.dart' as generated;

/// Current host support for on-device local AI generation.
class OnDeviceAiAvailability {
  const OnDeviceAiAvailability({
    required this.isAvailable,
    this.reason,
    this.modelStatus,
  });

  /// Whether the host can run local AI generation for the current user/device.
  final bool isAvailable;

  /// Human-readable reason when [isAvailable] is false.
  final String? reason;

  /// Raw platform status used for logging or diagnostics.
  final String? modelStatus;

  /// Availability returned when the platform plugin is not registered.
  static const unsupported = OnDeviceAiAvailability(
    isAvailable: false,
    reason: 'Local AI is not available on this platform.',
    modelStatus: 'unsupported-platform',
  );
}

/// Generation options forwarded to the native on-device model.
class OnDeviceAiGenerationConfig {
  const OnDeviceAiGenerationConfig({this.maxTokens, this.temperature});

  /// Soft cap for response length, when supported by the host model.
  final int? maxTokens;

  /// Sampling temperature, when supported by the host model.
  final double? temperature;
}

/// Complete response from a non-streaming local AI request.
class OnDeviceAiGenerationResult {
  const OnDeviceAiGenerationResult({
    required this.text,
    this.tokenCount,
    this.durationMs,
  });

  /// Generated response text.
  final String text;

  /// Token count returned by the host, when available.
  final int? tokenCount;

  /// Generation duration in milliseconds, when measured by the host.
  final double? durationMs;
}

/// Incremental text update from a streaming local AI request.
class OnDeviceAiStreamChunk {
  const OnDeviceAiStreamChunk({
    required this.text,
    required this.isDone,
    this.errorCode,
    this.errorMessage,
  });

  /// Latest generated text snapshot.
  final String text;

  /// Whether this chunk completes the stream.
  final bool isDone;

  /// Host error code encoded as a final stream chunk.
  final String? errorCode;

  /// Host error message encoded as a final stream chunk.
  final String? errorMessage;
}

/// Testable boundary around the generated Pigeon API.
abstract class OnDeviceAiApi {
  /// Checks whether local AI is available on the current host.
  Future<generated.LocalAiAvailabilityMessage> availability();

  /// Initializes the host session with system instructions.
  Future<void> initialize(String instructions);

  /// Generates a complete response for [prompt].
  Future<generated.LocalAiGenerationResponseMessage> generateText(
    String prompt,
    generated.LocalAiGenerationConfigMessage config,
  );

  /// Starts a streaming generation request for [prompt].
  Future<void> startStreamingText(
    String prompt,
    generated.LocalAiGenerationConfigMessage config,
  );

  /// Cancels the active streaming request, if any.
  Future<void> cancelStreamingText();

  /// Emits text snapshots for the active streaming request.
  Stream<generated.LocalAiStreamChunkMessage> generationStream();
}

/// Adapter that connects the app service to the generated Pigeon host API.
class OnDeviceAiHostApiAdapter implements OnDeviceAiApi {
  OnDeviceAiHostApiAdapter({generated.OnDeviceAiHostApi? hostApi})
    : _hostApi = hostApi ?? generated.OnDeviceAiHostApi();

  final generated.OnDeviceAiHostApi _hostApi;

  @override
  Future<generated.LocalAiAvailabilityMessage> availability() =>
      _hostApi.availability();

  @override
  Future<void> initialize(String instructions) =>
      _hostApi.initialize(instructions);

  @override
  Future<generated.LocalAiGenerationResponseMessage> generateText(
    String prompt,
    generated.LocalAiGenerationConfigMessage config,
  ) => _hostApi.generateText(prompt, config);

  @override
  Future<void> startStreamingText(
    String prompt,
    generated.LocalAiGenerationConfigMessage config,
  ) => _hostApi.startStreamingText(prompt, config);

  @override
  Future<void> cancelStreamingText() => _hostApi.cancelStreamingText();

  @override
  Stream<generated.LocalAiStreamChunkMessage> generationStream() =>
      generated.generationStream();
}

/// App-facing service for local AI availability and text generation.
///
/// This class keeps generated Pigeon types out of UI code, maps host failures
/// into stable app models, and owns the extra stream cancellation needed when
/// the host sends a final `isDone` chunk.
class OnDeviceAi {
  OnDeviceAi({OnDeviceAiApi? api}) : _api = api ?? OnDeviceAiHostApiAdapter();

  final OnDeviceAiApi _api;

  /// Returns local AI support for the current platform and model state.
  Future<OnDeviceAiAvailability> availability() async {
    try {
      final message = await _api.availability();
      return OnDeviceAiAvailability(
        isAvailable: message.isAvailable,
        reason: message.reason,
        modelStatus: message.modelStatus,
      );
    } on PlatformException catch (error) {
      return OnDeviceAiAvailability(
        isAvailable: false,
        reason: error.message ?? 'Local AI availability could not be checked.',
        modelStatus: error.code,
      );
    } on MissingPluginException {
      return OnDeviceAiAvailability.unsupported;
    }
  }

  /// Initializes the local AI session with optional system instructions.
  Future<void> initialize({String? instructions}) {
    return _api.initialize(
      instructions ??
          'You are an on-device assistant. Keep answers short and practical.',
    );
  }

  /// Generates one complete local AI response.
  Future<OnDeviceAiGenerationResult> generateText({
    required String prompt,
    OnDeviceAiGenerationConfig config = const OnDeviceAiGenerationConfig(),
  }) async {
    final response = await _api.generateText(
      prompt,
      generated.LocalAiGenerationConfigMessage(
        maxTokens: config.maxTokens,
        temperature: config.temperature,
      ),
    );

    return OnDeviceAiGenerationResult(
      text: response.text,
      tokenCount: response.tokenCount,
      durationMs: response.durationMs,
    );
  }

  /// Streams local AI response snapshots until the host sends a done chunk.
  ///
  /// The host currently emits cumulative text snapshots. When an `isDone` chunk
  /// arrives, the subscription is cancelled immediately so late host chunks do
  /// not reach already completed UI state.
  Stream<OnDeviceAiStreamChunk> generateTextStream({
    required String prompt,
    OnDeviceAiGenerationConfig config = const OnDeviceAiGenerationConfig(),
  }) {
    late final StreamSubscription<generated.LocalAiStreamChunkMessage>
    subscription;
    final controller = StreamController<OnDeviceAiStreamChunk>();
    var isClosing = false;
    final generatedConfig = generated.LocalAiGenerationConfigMessage(
      maxTokens: config.maxTokens,
      temperature: config.temperature,
    );

    Future<void> closeStream({bool cancelSubscription = false}) async {
      if (isClosing) {
        return;
      }

      isClosing = true;
      if (cancelSubscription) {
        await subscription.cancel();
      }
      await controller.close();
    }

    controller.onListen = () {
      subscription = _api.generationStream().listen(
        (chunk) {
          if (isClosing) {
            return;
          }

          final mapped = OnDeviceAiStreamChunk(
            text: chunk.text,
            isDone: chunk.isDone,
            errorCode: chunk.errorCode,
            errorMessage: chunk.errorMessage,
          );
          controller.add(mapped);

          if (mapped.isDone) {
            unawaited(closeStream(cancelSubscription: true));
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!isClosing) {
            controller.addError(error, stackTrace);
            unawaited(closeStream(cancelSubscription: true));
          }
        },
        onDone: () {
          unawaited(closeStream());
        },
      );

      unawaited(
        _api.startStreamingText(prompt, generatedConfig).catchError((error) {
          if (isClosing) {
            return null;
          }

          controller.addError(error);
          unawaited(closeStream(cancelSubscription: true));
          return null;
        }),
      );
    };

    // ignore: cascade_invocations
    controller.onCancel = () async {
      await subscription.cancel();
      await _api.cancelStreamingText();
    };

    return controller.stream;
  }

  /// Cancels the active streaming request, if any.
  Future<void> cancelStreamingText() => _api.cancelStreamingText();
}
