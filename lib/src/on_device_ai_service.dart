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

/// Entry point for checking local AI availability and creating sessions.
///
/// Generation always runs through an [OnDeviceAiSession]. Reusing the same
/// session is the cross-platform way to preserve native session context when a
/// platform supports it, such as Apple Foundation Models.
class OnDeviceAi {
  OnDeviceAi({
    generated.OnDeviceAiHostApi? hostApi,
    Stream<generated.LocalAiStreamChunkMessage> Function()? generationStream,
  }) : _api = hostApi ?? generated.OnDeviceAiHostApi(),
       _generationStream = generationStream ?? generated.generationStream;

  final generated.OnDeviceAiHostApi _api;
  final Stream<generated.LocalAiStreamChunkMessage> Function()
  _generationStream;

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

  /// Creates a reusable native model session.
  ///
  /// Pass [instructions] to set the session's system behavior. Keep and reuse
  /// the returned [OnDeviceAiSession] for related prompts so platforms with
  /// stateful model sessions can retain context between calls.
  Future<OnDeviceAiSession> createSession({String? instructions}) async {
    final session = await _api.createSession(instructions ?? '');
    return OnDeviceAiSession._(
      hostApi: _api,
      generationStream: _generationStream,
      session: session,
    );
  }
}

/// A reusable native local AI model session.
///
/// Sessions own platform model state. Dispose a session when the surrounding UI
/// flow is finished so native resources and any retained context can be freed.
class OnDeviceAiSession {
  OnDeviceAiSession._({
    required generated.OnDeviceAiHostApi hostApi,
    required Stream<generated.LocalAiStreamChunkMessage> Function()
    generationStream,
    required String session,
  }) : _api = hostApi,
       _generationStream = generationStream,
       _session = session;

  final generated.OnDeviceAiHostApi _api;
  final Stream<generated.LocalAiStreamChunkMessage> Function()
  _generationStream;
  final String _session;

  /// Whether [dispose] has been called.
  bool get isDisposed => _isDisposed;

  bool _isDisposed = false;

  /// Generates one complete local AI response in this session.
  Future<OnDeviceAiGenerationResult> generateText({
    required String prompt,
    OnDeviceAiGenerationConfig config = const OnDeviceAiGenerationConfig(),
  }) async {
    _ensureActive();
    final response = await _api.generateText(
      _session,
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

  /// Streams local AI response snapshots in this session.
  ///
  /// Stream chunks are cumulative snapshots. If the model emits `Hello` and then
  /// `Hello world`, this stream emits both snapshots. Cancelling the Dart stream
  /// also asks the native bridge to cancel the active generation. Only one
  /// streaming generation should be active at a time for a plugin instance.
  Stream<OnDeviceAiStreamChunk> generateTextStream({
    required String prompt,
    OnDeviceAiGenerationConfig config = const OnDeviceAiGenerationConfig(),
  }) {
    _ensureActive();
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
      subscription = _generationStream().listen(
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
        _api.startStreamingText(_session, prompt, generatedConfig).catchError((
          Object error,
        ) {
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
      await _api.cancelStreamingText(_session);
    };

    return controller.stream;
  }

  /// Cancels the active streaming request in this session, if any.
  Future<void> cancelStreamingText() {
    _ensureActive();
    return _api.cancelStreamingText(_session);
  }

  /// Releases this session's native resources and retained model context.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    // Mark disposed up front so concurrent calls don't double-dispose, but
    // revert if the native call fails so the session stays usable and the
    // native resources can be released by a later retry.
    _isDisposed = true;
    try {
      await _api.disposeSession(_session);
    } catch (_) {
      _isDisposed = false;
      rethrow;
    }
  }

  void _ensureActive() {
    if (_isDisposed) {
      throw StateError('This OnDeviceAiSession has been disposed.');
    }
  }
}
