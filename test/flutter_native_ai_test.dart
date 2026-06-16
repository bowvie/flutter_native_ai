import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_native_ai/src/generated/on_device_ai.g.dart'
    as generated;
import 'package:flutter_native_ai/src/on_device_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OnDeviceAi', () {
    test('maps availability responses', () async {
      final service = OnDeviceAi(
        api: _FakeLocalAiApi(
          availabilityResponse: generated.LocalAiAvailabilityMessage(
            isAvailable: true,
            modelStatus: 'available',
          ),
        ),
      );

      final availability = await service.availability();

      expect(availability.isAvailable, isTrue);
      expect(availability.reason, isNull);
      expect(availability.modelStatus, 'available');
    });

    test(
      'returns unsupported availability for missing platform plugin',
      () async {
        final service = OnDeviceAi(
          api: _FakeLocalAiApi(availabilityError: MissingPluginException()),
        );

        final availability = await service.availability();

        expect(availability.isAvailable, isFalse);
        expect(availability.modelStatus, 'unsupported-platform');
      },
    );

    test('maps platform availability errors into unavailable state', () async {
      final service = OnDeviceAi(
        api: _FakeLocalAiApi(
          availabilityError: PlatformException(
            code: 'availability-failed',
            message: 'Model status could not be read.',
          ),
        ),
      );

      final availability = await service.availability();

      expect(availability.isAvailable, isFalse);
      expect(availability.reason, 'Model status could not be read.');
      expect(availability.modelStatus, 'availability-failed');
    });

    test('uses fallback availability message for platform errors', () async {
      final service = OnDeviceAi(
        api: _FakeLocalAiApi(
          availabilityError: PlatformException(code: 'availability-failed'),
        ),
      );

      final availability = await service.availability();

      expect(availability.isAvailable, isFalse);
      expect(
        availability.reason,
        'Local AI availability could not be checked.',
      );
      expect(availability.modelStatus, 'availability-failed');
    });

    test('creates a session with default empty instructions', () async {
      final api = _FakeLocalAiApi();
      final service = OnDeviceAi(api: api);

      await service.createSession();

      expect(api.createdInstructions, ['']);
    });

    test('creates a session with custom instructions', () async {
      final api = _FakeLocalAiApi();
      final service = OnDeviceAi(api: api);

      await service.createSession(instructions: 'Answer in one sentence.');

      expect(api.createdInstructions, ['Answer in one sentence.']);
    });
  });

  group('OnDeviceAiSession', () {
    test('maps generation config and response', () async {
      final api = _FakeLocalAiApi(
        generationResponse: generated.LocalAiGenerationResponseMessage(
          text: 'item is a Grass-type card.',
          tokenCount: 8,
          durationMs: 42,
        ),
      );
      final session = await OnDeviceAi(
        api: api,
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
      final api = _FakeLocalAiApi(
        streamChunks: [
          generated.LocalAiStreamChunkMessage(text: 'Fire', isDone: false),
          generated.LocalAiStreamChunkMessage(
            text: 'Fire binder',
            isDone: true,
          ),
        ],
      );
      final session = await OnDeviceAi(api: api).createSession();

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
      final api = _FakeLocalAiApi(
        streamChunks: [
          generated.LocalAiStreamChunkMessage(text: 'Done', isDone: true),
          generated.LocalAiStreamChunkMessage(
            text: 'Done extra',
            isDone: false,
          ),
        ],
      );
      final session = await OnDeviceAi(api: api).createSession();

      final chunks = await session
          .generateTextStream(prompt: 'Stop after done.')
          .toList();

      expect(chunks.map((chunk) => chunk.text), ['Done']);
      expect(api.generationStreamCancelled, isTrue);
    });

    test('closes the generation stream after a native stream error', () async {
      final api = _FakeLocalAiApi(
        streamError: PlatformException(
          code: 'stream-error',
          message: 'Stream failed',
        ),
      );
      final session = await OnDeviceAi(api: api).createSession();

      await expectLater(
        session.generateTextStream(prompt: 'Fail from stream.').toList(),
        throwsA(isA<PlatformException>()),
      );
      expect(api.generationStreamCancelled, isTrue);
    });

    test('maps terminal error chunks without throwing', () async {
      final api = _FakeLocalAiApi(
        streamChunks: [
          generated.LocalAiStreamChunkMessage(
            text: 'Partial text',
            isDone: true,
            errorCode: 'local-ai-generation-failed',
            errorMessage: 'Generation failed.',
          ),
        ],
      );
      final session = await OnDeviceAi(api: api).createSession();

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
        final api = _FakeLocalAiApi(
          startStreamError: PlatformException(
            code: 'start-error',
            message: 'Start failed',
          ),
        );
        final session = await OnDeviceAi(api: api).createSession();

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
        final api = _FakeLocalAiApi(
          streamChunks: [
            generated.LocalAiStreamChunkMessage(text: 'First', isDone: false),
            generated.LocalAiStreamChunkMessage(text: 'Second', isDone: false),
          ],
        );
        final session = await OnDeviceAi(api: api).createSession();

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
      final api = _FakeLocalAiApi();
      final session = await OnDeviceAi(api: api).createSession();

      await session.cancelStreamingText();

      expect(api.cancelledStreamSession, 'session-1');
    });

    test('disposes native session once', () async {
      final api = _FakeLocalAiApi();
      final session = await OnDeviceAi(api: api).createSession();

      await session.dispose();
      await session.dispose();

      expect(api.disposedSessions, ['session-1']);
      expect(session.isDisposed, isTrue);
    });

    test('throws when used after disposal', () async {
      final session = await OnDeviceAi(api: _FakeLocalAiApi()).createSession();

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

class _FakeLocalAiApi implements OnDeviceAiApi {
  _FakeLocalAiApi({
    this.availabilityResponse,
    this.availabilityError,
    this.generationResponse,
    this.streamChunks = const [],
    this.streamError,
    this.startStreamError,
  });

  final generated.LocalAiAvailabilityMessage? availabilityResponse;
  final Exception? availabilityError;
  final generated.LocalAiGenerationResponseMessage? generationResponse;
  final List<generated.LocalAiStreamChunkMessage> streamChunks;
  final Exception? streamError;
  final Exception? startStreamError;

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
  Future<generated.LocalAiAvailabilityMessage> availability() async {
    final error = availabilityError;
    if (error != null) {
      throw error;
    }
    return availabilityResponse ??
        generated.LocalAiAvailabilityMessage(
          isAvailable: false,
          reason: 'Unavailable',
          modelStatus: 'unavailable',
        );
  }

  @override
  Future<String> createSession(String instructions) async {
    createdInstructions.add(instructions);
    return 'session-${createdInstructions.length}';
  }

  @override
  Future<void> disposeSession(String session) async {
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

  @override
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
}
