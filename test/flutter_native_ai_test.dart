import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_native_ai/src/generated/on_device_ai.g.dart'
    as generated;
import 'package:flutter_native_ai/src/on_device_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

OnDeviceAi _serviceFor(_FakeHostApi api) => OnDeviceAi(
  hostApi: api,
  generationStream: api.generationStream,
  statusStream: api.statusStream,
);

void main() {
  group('OnDeviceAi', () {
    test('maps status responses', () async {
      final service = _serviceFor(
        _FakeHostApi(
          statusResponse: generated.LocalAiStatusMessage(
            isSupported: true,
            isReady: true,
            canInitialize: false,
            isInitializing: false,
            platformStatus: 'available',
          ),
        ),
      );

      final status = await service.status();

      expect(status.isSupported, isTrue);
      expect(status.isReady, isTrue);
      expect(status.isAvailable, isTrue);
      expect(status.reason, isNull);
      expect(status.platformStatus, 'available');
    });

    test('maps initialization status fields', () async {
      final service = _serviceFor(
        _FakeHostApi(
          statusResponse: generated.LocalAiStatusMessage(
            isSupported: true,
            isReady: false,
            canInitialize: true,
            isInitializing: true,
            initializationProgress: 42,
            reason: 'Downloading model.',
            platformStatus: 'downloading',
          ),
        ),
      );

      final status = await service.status();

      expect(status.isAvailable, isFalse);
      expect(status.canInitialize, isTrue);
      expect(status.isInitializing, isTrue);
      expect(status.initializationProgress, 42);
      expect(status.reason, 'Downloading model.');
      expect(status.platformStatus, 'downloading');
    });

    test('returns unsupported status for missing platform plugin', () async {
      final service = _serviceFor(
        _FakeHostApi(statusError: MissingPluginException()),
      );

      final status = await service.status();

      expect(status.isAvailable, isFalse);
      expect(status.platformStatus, 'unsupported-platform');
    });

    test('maps platform status errors into unavailable state', () async {
      final service = _serviceFor(
        _FakeHostApi(
          statusError: PlatformException(
            code: 'status-failed',
            message: 'Model status could not be read.',
          ),
        ),
      );

      final status = await service.status();

      expect(status.isAvailable, isFalse);
      expect(status.reason, 'Model status could not be read.');
      expect(status.platformStatus, 'status-failed');
    });

    test('uses fallback status message for platform errors', () async {
      final service = _serviceFor(
        _FakeHostApi(statusError: PlatformException(code: 'status-failed')),
      );

      final status = await service.status();

      expect(status.isAvailable, isFalse);
      expect(status.reason, 'Local AI status could not be checked.');
      expect(status.platformStatus, 'status-failed');
    });

    test('ensures readiness with the requested policy', () async {
      final api = _FakeHostApi(
        ensureReadyResponse: generated.LocalAiStatusMessage(
          isSupported: true,
          isReady: true,
          canInitialize: false,
          isInitializing: false,
          initializationProgress: 100,
          platformStatus: 'available',
        ),
      );
      final service = _serviceFor(api);

      final status = await service.ensureReady(
        policy: OnDeviceAiInitializationPolicy.always,
      );

      expect(status.isAvailable, isTrue);
      expect(status.initializationProgress, 100);
      expect(api.ensureReadyPolicies, [
        generated.LocalAiInitializationPolicyMessage.always,
      ]);
    });

    test('maps status stream updates', () async {
      final service = _serviceFor(
        _FakeHostApi(
          statusChunks: [
            generated.LocalAiStatusMessage(
              isSupported: true,
              isReady: false,
              canInitialize: true,
              isInitializing: true,
              initializationProgress: null,
              platformStatus: 'downloading',
            ),
            generated.LocalAiStatusMessage(
              isSupported: true,
              isReady: true,
              canInitialize: false,
              isInitializing: false,
              initializationProgress: 100,
              platformStatus: 'available',
            ),
          ],
        ),
      );

      final statuses = await service.statusStream().toList();

      expect(statuses.map((status) => status.isInitializing), [true, false]);
      expect(statuses.last.initializationProgress, 100);
    });

    test('creates a session with default empty instructions', () async {
      final api = _FakeHostApi();
      final service = _serviceFor(api);

      await service.createSession();

      expect(api.createdInstructions, ['']);
    });

    test('creates a session with custom instructions', () async {
      final api = _FakeHostApi();
      final service = _serviceFor(api);

      await service.createSession(instructions: 'Answer in one sentence.');

      expect(api.createdInstructions, ['Answer in one sentence.']);
    });

    test('ensures readiness before session creation when requested', () async {
      final api = _FakeHostApi(
        ensureReadyResponse: generated.LocalAiStatusMessage(
          isSupported: true,
          isReady: true,
          canInitialize: false,
          isInitializing: false,
          platformStatus: 'available',
        ),
      );
      final service = _serviceFor(api);

      await service.createSession(
        initializationPolicy: OnDeviceAiInitializationPolicy.whenNeeded,
      );

      expect(api.ensureReadyPolicies, [
        generated.LocalAiInitializationPolicyMessage.whenNeeded,
      ]);
      expect(api.createdInstructions, ['']);
    });

    test(
      'does not create a session when initialization cannot make AI ready',
      () async {
        final api = _FakeHostApi(
          ensureReadyResponse: generated.LocalAiStatusMessage(
            isSupported: true,
            isReady: false,
            canInitialize: false,
            isInitializing: false,
            reason: 'Model blocked.',
            platformStatus: 'blocked',
          ),
        );
        final service = _serviceFor(api);

        await expectLater(
          service.createSession(
            initializationPolicy: OnDeviceAiInitializationPolicy.whenNeeded,
          ),
          throwsA(
            isA<PlatformException>()
                .having((error) => error.code, 'code', 'blocked')
                .having((error) => error.message, 'message', 'Model blocked.'),
          ),
        );
        expect(api.createdInstructions, isEmpty);
      },
    );
  });

  group('OnDeviceAiSession', () {
    test('maps generation config and response', () async {
      final api = _FakeHostApi(
        generationResponse: generated.LocalAiGenerationResponseMessage(
          text: 'item is a Grass-type card.',
          tokenCount: 8,
          durationMs: 42,
        ),
      );
      final session = await _serviceFor(
        api,
      ).createSession(instructions: 'Stay brief.');

      final result = await session.generateText(
        prompt: 'Summarize item.',
        config: const OnDeviceAiGenerationConfig(
          maxTokens: 64,
          temperature: 0.2,
        ),
      );

      expect(api.createdInstructions, ['Stay brief.']);
      expect(api.lastSession, 'session-1');
      expect(api.lastPrompt, 'Summarize item.');
      expect(api.lastConfig?.maxTokens, 64);
      expect(api.lastConfig?.temperature, 0.2);
      expect(result.text, 'item is a Grass-type card.');
      expect(result.tokenCount, 8);
      expect(result.durationMs, 42);
    });

    test('starts generation and maps stream chunks', () async {
      final api = _FakeHostApi(
        streamChunks: [
          generated.LocalAiStreamChunkMessage(text: 'Fire', isDone: false),
          generated.LocalAiStreamChunkMessage(
            text: 'Fire binder',
            isDone: true,
          ),
        ],
      );
      final session = await _serviceFor(api).createSession();

      final chunks = await session
          .generateTextStream(
            prompt: 'Name this binder.',
            config: const OnDeviceAiGenerationConfig(
              maxTokens: 24,
              temperature: 0.1,
            ),
          )
          .toList();

      expect(api.startedStreamSession, 'session-1');
      expect(api.startedStreamPrompt, 'Name this binder.');
      expect(api.startedStreamConfig?.maxTokens, 24);
      expect(api.startedStreamConfig?.temperature, 0.1);
      expect(chunks.map((chunk) => chunk.text), ['Fire', 'Fire binder']);
      expect(chunks.last.isDone, isTrue);
    });

    test('cancels the generation stream after a done chunk', () async {
      final api = _FakeHostApi(
        streamChunks: [
          generated.LocalAiStreamChunkMessage(text: 'Done', isDone: true),
          generated.LocalAiStreamChunkMessage(
            text: 'Done extra',
            isDone: false,
          ),
        ],
      );
      final session = await _serviceFor(api).createSession();

      final chunks = await session
          .generateTextStream(prompt: 'Stop after done.')
          .toList();

      expect(chunks.map((chunk) => chunk.text), ['Done']);
      expect(api.generationStreamCancelled, isTrue);
    });

    test('closes the generation stream after a native stream error', () async {
      final api = _FakeHostApi(
        streamError: PlatformException(
          code: 'stream-error',
          message: 'Stream failed',
        ),
      );
      final session = await _serviceFor(api).createSession();

      await expectLater(
        session.generateTextStream(prompt: 'Fail from stream.').toList(),
        throwsA(isA<PlatformException>()),
      );
      expect(api.generationStreamCancelled, isTrue);
    });

    test('maps terminal error chunks without throwing', () async {
      final api = _FakeHostApi(
        streamChunks: [
          generated.LocalAiStreamChunkMessage(
            text: 'Partial text',
            isDone: true,
            errorCode: 'local-ai-generation-failed',
            errorMessage: 'Generation failed.',
          ),
        ],
      );
      final session = await _serviceFor(api).createSession();

      final chunks = await session
          .generateTextStream(prompt: 'Surface native terminal errors.')
          .toList();

      expect(chunks, hasLength(1));
      expect(chunks.single.text, 'Partial text');
      expect(chunks.single.isDone, isTrue);
      expect(chunks.single.errorCode, 'local-ai-generation-failed');
      expect(chunks.single.errorMessage, 'Generation failed.');
      expect(api.generationStreamCancelled, isTrue);
    });

    test(
      'closes the generation stream when starting generation fails',
      () async {
        final api = _FakeHostApi(
          startStreamError: PlatformException(
            code: 'start-error',
            message: 'Start failed',
          ),
        );
        final session = await _serviceFor(api).createSession();

        await expectLater(
          session.generateTextStream(prompt: 'Fail to start.').toList(),
          throwsA(isA<PlatformException>()),
        );
        expect(api.generationStreamCancelled, isTrue);
      },
    );

    test(
      'cancels native generation when stream subscription is cancelled',
      () async {
        final api = _FakeHostApi(
          streamChunks: [
            generated.LocalAiStreamChunkMessage(text: 'First', isDone: false),
            generated.LocalAiStreamChunkMessage(text: 'Second', isDone: false),
          ],
        );
        final session = await _serviceFor(api).createSession();

        late final StreamSubscription<OnDeviceAiStreamChunk> subscription;
        final firstChunk = Completer<void>();
        subscription = session
            .generateTextStream(prompt: 'Cancel early.')
            .listen((chunk) {
              if (!firstChunk.isCompleted) {
                firstChunk.complete();
              }
              unawaited(subscription.cancel());
            });
        await firstChunk.future;
        await pumpEventQueue();

        expect(api.cancelledStreamSession, 'session-1');
        expect(api.generationStreamCancelled, isTrue);
      },
    );

    test('forwards explicit stream cancellation', () async {
      final api = _FakeHostApi();
      final session = await _serviceFor(api).createSession();

      await session.cancelStreamingText();

      expect(api.cancelledStreamSession, 'session-1');
    });

    test('disposes native session once', () async {
      final api = _FakeHostApi();
      final session = await _serviceFor(api).createSession();

      await session.dispose();
      await session.dispose();

      expect(api.disposedSessions, ['session-1']);
      expect(session.isDisposed, isTrue);
    });

    test('stays usable when native disposal fails', () async {
      final api = _FakeHostApi(
        disposeError: PlatformException(code: 'dispose-failed'),
      );
      final session = await _serviceFor(api).createSession();

      await expectLater(session.dispose(), throwsA(isA<PlatformException>()));
      expect(session.isDisposed, isFalse);

      api.disposeError = null;
      await session.dispose();
      expect(session.isDisposed, isTrue);
      expect(api.disposedSessions, ['session-1']);
    });

    test('throws when used after disposal', () async {
      final session = await _serviceFor(_FakeHostApi()).createSession();

      await session.dispose();

      expect(
        () => session.generateText(prompt: 'Nope.'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => session.generateTextStream(prompt: 'Nope.'),
        throwsA(isA<StateError>()),
      );
      expect(() => session.cancelStreamingText(), throwsA(isA<StateError>()));
    });
  });
}

class _FakeHostApi extends generated.OnDeviceAiHostApi {
  _FakeHostApi({
    this.statusResponse,
    this.statusError,
    this.ensureReadyResponse,
    this.statusChunks = const [],
    this.generationResponse,
    this.streamChunks = const [],
    this.streamError,
    this.startStreamError,
    this.disposeError,
  });

  final generated.LocalAiStatusMessage? statusResponse;
  final Exception? statusError;
  final generated.LocalAiStatusMessage? ensureReadyResponse;
  final List<generated.LocalAiStatusMessage> statusChunks;
  final generated.LocalAiGenerationResponseMessage? generationResponse;
  final List<generated.LocalAiStreamChunkMessage> streamChunks;
  final Exception? streamError;
  final Exception? startStreamError;
  Exception? disposeError;

  final ensureReadyPolicies = <generated.LocalAiInitializationPolicyMessage>[];
  final createdInstructions = <String>[];
  final disposedSessions = <String>[];
  String? lastSession;
  String? lastPrompt;
  generated.LocalAiGenerationConfigMessage? lastConfig;
  String? startedStreamSession;
  String? startedStreamPrompt;
  generated.LocalAiGenerationConfigMessage? startedStreamConfig;
  String? cancelledStreamSession;
  bool generationStreamCancelled = false;

  @override
  Future<generated.LocalAiStatusMessage> status() async {
    final error = statusError;
    if (error != null) {
      throw error;
    }
    return statusResponse ??
        generated.LocalAiStatusMessage(
          isSupported: false,
          isReady: false,
          canInitialize: false,
          isInitializing: false,
          reason: 'Unavailable',
          platformStatus: 'unavailable',
        );
  }

  @override
  Future<generated.LocalAiStatusMessage> ensureReady(
    generated.LocalAiInitializationPolicyMessage policy,
  ) async {
    ensureReadyPolicies.add(policy);
    return ensureReadyResponse ?? await status();
  }

  @override
  Future<String> createSession(String instructions) async {
    createdInstructions.add(instructions);
    return 'session-${createdInstructions.length}';
  }

  @override
  Future<void> disposeSession(String session) async {
    final error = disposeError;
    if (error != null) {
      throw error;
    }
    disposedSessions.add(session);
  }

  @override
  Future<generated.LocalAiGenerationResponseMessage> generateText(
    String session,
    String prompt,
    generated.LocalAiGenerationConfigMessage config,
  ) async {
    lastSession = session;
    lastPrompt = prompt;
    lastConfig = config;
    return generationResponse ??
        generated.LocalAiGenerationResponseMessage(text: 'Generated response');
  }

  @override
  Future<void> startStreamingText(
    String session,
    String prompt,
    generated.LocalAiGenerationConfigMessage config,
  ) async {
    startedStreamSession = session;
    startedStreamPrompt = prompt;
    startedStreamConfig = config;
    final error = startStreamError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> cancelStreamingText(String session) async {
    cancelledStreamSession = session;
  }

  Stream<generated.LocalAiStreamChunkMessage> generationStream() {
    final controller = StreamController<generated.LocalAiStreamChunkMessage>()
      ..onCancel = () {
        generationStreamCancelled = true;
      };

    scheduleMicrotask(() {
      for (final chunk in streamChunks) {
        if (controller.isClosed) {
          return;
        }
        controller.add(chunk);
      }
      final error = streamError;
      if (error != null && !controller.isClosed) {
        controller.addError(error);
        return;
      }
      if (startStreamError != null) {
        return;
      }
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
    });

    return controller.stream;
  }

  Stream<generated.LocalAiStatusMessage> statusStream() {
    return Stream<generated.LocalAiStatusMessage>.fromIterable(statusChunks);
  }
}
