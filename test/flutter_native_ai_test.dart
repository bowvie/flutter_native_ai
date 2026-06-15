import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_ai/src/generated/on_device_ai.g.dart'
    as generated;
import 'package:flutter_native_ai/flutter_native_ai.dart';

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

    test('maps generation config and response', () async {
      final api = _FakeLocalAiApi(
        generationResponse: generated.LocalAiGenerationResponseMessage(
          text: 'item is a Grass-type card.',
          tokenCount: 8,
          durationMs: 42,
        ),
      );
      final service = OnDeviceAi(api: api);

      final result = await service.generateText(
        prompt: 'Summarize item.',
        config: const OnDeviceAiGenerationConfig(
          maxTokens: 64,
          temperature: 0.2,
        ),
      );

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
      final service = OnDeviceAi(api: api);

      final chunks = await service
          .generateTextStream(
            prompt: 'Name this binder.',
            config: const OnDeviceAiGenerationConfig(
              maxTokens: 24,
              temperature: 0.1,
            ),
          )
          .toList();

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
      final service = OnDeviceAi(api: api);

      final chunks = await service
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
      final service = OnDeviceAi(api: api);

      await expectLater(
        service.generateTextStream(prompt: 'Fail from stream.').toList(),
        throwsA(isA<PlatformException>()),
      );
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
        final service = OnDeviceAi(api: api);

        await expectLater(
          service.generateTextStream(prompt: 'Fail to start.').toList(),
          throwsA(isA<PlatformException>()),
        );
        expect(api.generationStreamCancelled, isTrue);
      },
    );
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

  String? initializedInstructions;
  String? lastPrompt;
  generated.LocalAiGenerationConfigMessage? lastConfig;
  String? startedStreamPrompt;
  generated.LocalAiGenerationConfigMessage? startedStreamConfig;
  bool cancelledStream = false;
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
  Future<void> initialize(String instructions) async {
    initializedInstructions = instructions;
  }

  @override
  Future<generated.LocalAiGenerationResponseMessage> generateText(
    String prompt,
    generated.LocalAiGenerationConfigMessage config,
  ) async {
    lastPrompt = prompt;
    lastConfig = config;
    return generationResponse ??
        generated.LocalAiGenerationResponseMessage(text: 'Generated response');
  }

  @override
  Future<void> startStreamingText(
    String prompt,
    generated.LocalAiGenerationConfigMessage config,
  ) async {
    startedStreamPrompt = prompt;
    startedStreamConfig = config;
    final error = startStreamError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> cancelStreamingText() async {
    cancelledStream = true;
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
