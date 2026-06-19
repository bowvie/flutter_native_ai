import 'dart:async';

import 'package:flutter/services.dart';

import 'generated/on_device_ai.g.dart' as generated;
import 'on_device_ai_exception.dart';

/// Current host support and model readiness for on-device local AI generation.
class OnDeviceAiStatus {
  const OnDeviceAiStatus({
    required this.isSupported,
    required this.isReady,
    required this.canInitialize,
    required this.isInitializing,
    this.initializationProgress,
    this.reason,
    this.platformStatus,
  });

  /// Whether this platform, OS, and device can support local AI.
  final bool isSupported;

  /// Whether generation can run now.
  final bool isReady;

  /// Whether the native platform can initialize or download the model.
  final bool canInitialize;

  /// Whether model initialization or download is currently running.
  final bool isInitializing;

  /// Convenience for the previous availability concept.
  bool get isAvailable => isSupported && isReady;

  /// Real initialization progress from 0 to 100, when the platform provides it.
  final int? initializationProgress;

  /// Human-readable reason when [isAvailable] is false or initialization fails.
  final String? reason;

  /// Raw platform status used for logging or diagnostics.
  final String? platformStatus;

  /// Status returned when the platform plugin is not registered.
  static const unsupported = OnDeviceAiStatus(
    isSupported: false,
    isReady: false,
    canInitialize: false,
    isInitializing: false,
    reason: 'Local AI is not available on this platform.',
    platformStatus: 'unsupported-platform',
  );
}

/// Policy for model initialization before readiness-sensitive operations.
enum OnDeviceAiInitializationPolicy {
  /// Only check current status; never start model initialization.
  never,

  /// Initialize only when the model is supported but not ready.
  whenNeeded,

  /// Ask the platform to initialize or refresh readiness before proceeding.
  always,
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

/// Entry point for checking local AI status and creating sessions.
///
/// Generation always runs through an [OnDeviceAiSession]. Reusing the same
/// session is the cross-platform way to preserve native session context when a
/// platform supports it, such as Apple Foundation Models.
class OnDeviceAi {
  OnDeviceAi({
    generated.OnDeviceAiHostApi? hostApi,
    Stream<generated.LocalAiStreamChunkMessage> Function()? generationStream,
    Stream<generated.LocalAiStatusMessage> Function()? statusStream,
  }) : _api = hostApi ?? generated.OnDeviceAiHostApi(),
       _generationStream = generationStream ?? generated.generationStream,
       _statusStream = statusStream ?? generated.statusStream;

  final generated.OnDeviceAiHostApi _api;
  final Stream<generated.LocalAiStreamChunkMessage> Function()
  _generationStream;
  final Stream<generated.LocalAiStatusMessage> Function() _statusStream;

  /// Returns local AI support and model readiness for the current platform.
  Future<OnDeviceAiStatus> status() async {
    try {
      final message = await _api.status();
      return _mapStatus(message);
    } on PlatformException catch (error) {
      return OnDeviceAiStatus(
        isSupported: false,
        isReady: false,
        canInitialize: false,
        isInitializing: false,
        reason: error.message ?? 'Local AI status could not be checked.',
        platformStatus: error.code,
      );
    } on MissingPluginException {
      return OnDeviceAiStatus.unsupported;
    }
  }

  /// Ensures the native model is ready according to [policy].
  Future<OnDeviceAiStatus> ensureReady({
    OnDeviceAiInitializationPolicy policy =
        OnDeviceAiInitializationPolicy.whenNeeded,
  }) async {
    try {
      final message = await _api.ensureReady(_mapInitializationPolicy(policy));
      return _mapStatus(message);
    } on PlatformException catch (error) {
      return OnDeviceAiStatus(
        isSupported: false,
        isReady: false,
        canInitialize: false,
        isInitializing: false,
        reason: error.message ?? 'Local AI could not be initialized.',
        platformStatus: error.code,
      );
    } on MissingPluginException {
      return OnDeviceAiStatus.unsupported;
    }
  }

  /// Emits model initialization status snapshots from the native platform.
  Stream<OnDeviceAiStatus> statusStream() {
    return _statusStream().map(_mapStatus);
  }

  /// Creates a reusable native model session.
  ///
  /// Pass [instructions] to set the session's system behavior. Keep and reuse
  /// the returned [OnDeviceAiSession] for related prompts so platforms with
  /// stateful model sessions can retain context between calls.
  Future<OnDeviceAiSession> createSession({
    String? instructions,
    OnDeviceAiInitializationPolicy initializationPolicy =
        OnDeviceAiInitializationPolicy.never,
  }) async {
    if (initializationPolicy != OnDeviceAiInitializationPolicy.never) {
      final currentStatus = await ensureReady(policy: initializationPolicy);
      if (!currentStatus.isAvailable) {
        throw OnDeviceAiUnavailableException(
          currentStatus.reason ??
              'Local AI is not ready for generation on this platform.',
          details: currentStatus.platformStatus,
        );
      }
    }

    final session = await _api.createSession(instructions ?? '');
    return OnDeviceAiSession._(
      hostApi: _api,
      generationStream: _generationStream,
      session: session,
    );
  }

  OnDeviceAiStatus _mapStatus(generated.LocalAiStatusMessage message) {
    return OnDeviceAiStatus(
      isSupported: message.isSupported,
      isReady: message.isReady,
      canInitialize: message.canInitialize,
      isInitializing: message.isInitializing,
      initializationProgress: message.initializationProgress,
      reason: message.reason,
      platformStatus: message.platformStatus,
    );
  }

  generated.LocalAiInitializationPolicyMessage _mapInitializationPolicy(
    OnDeviceAiInitializationPolicy policy,
  ) {
    return switch (policy) {
      OnDeviceAiInitializationPolicy.never =>
        generated.LocalAiInitializationPolicyMessage.never,
      OnDeviceAiInitializationPolicy.whenNeeded =>
        generated.LocalAiInitializationPolicyMessage.whenNeeded,
      OnDeviceAiInitializationPolicy.always =>
        generated.LocalAiInitializationPolicyMessage.always,
    };
  }
}

/// Maps a [PlatformException] from the native bridge to a typed [OnDeviceAiException].
OnDeviceAiException _mapPlatformException(PlatformException e) {
  return switch (e.code) {
    'local-ai-unsupported-os' || 'local-ai-framework-unavailable' =>
      OnDeviceAiUnsupportedException(e.message ?? e.code, details: e.details),
    'local-ai-unavailable' => OnDeviceAiUnavailableException(
      e.message ?? e.code,
      details: e.details,
    ),
    'local-ai-session-not-found' => OnDeviceAiSessionNotFoundException(
      e.message ?? e.code,
      details: e.details,
    ),
    _ => OnDeviceAiGenerationFailedException(
      e.message ?? e.code,
      details: e.details,
    ),
  };
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
    try {
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
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    }
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
            final mapped = error is PlatformException
                ? _mapPlatformException(error)
                : error;
            controller.addError(mapped, stackTrace);
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

          final mapped = error is PlatformException
              ? _mapPlatformException(error)
              : error;
          controller.addError(mapped);
          unawaited(closeStream(cancelSubscription: true));
          return null;
        }),
      );
    };

    // ignore: cascade_invocations
    controller.onCancel = () async {
      if (isClosing) {
        return; // stream ended naturally; skip redundant cancel
      }
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
    } on PlatformException catch (e) {
      _isDisposed = false;
      throw _mapPlatformException(e);
    } catch (_) {
      _isDisposed = false;
      rethrow;
    }
  }

  void _ensureActive() {
    if (_isDisposed) {
      throw const OnDeviceAiSessionDisposedException(
        'This OnDeviceAiSession has been disposed.',
      );
    }
  }
}
