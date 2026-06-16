import 'package:flutter/services.dart';
import 'package:flutter_native_ai/src/generated/on_device_ai.g.dart'
    as generated;
import 'package:flutter_native_ai/src/on_device_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pigeon message codec', () {
    test('round-trips all local AI message types', () {
      final codec = generated.OnDeviceAiHostApi.pigeonChannelCodec;
      final messages = <Object?>[
        generated.LocalAiAvailabilityMessage(
          isAvailable: false,
          reason: 'Needs model download.',
          modelStatus: 'downloadable',
        ),
        generated.LocalAiGenerationConfigMessage(
          maxTokens: 128,
          temperature: 0.35,
        ),
        generated.LocalAiGenerationResponseMessage(
          text: 'Generated text',
          tokenCount: 12,
          durationMs: 24.5,
        ),
        generated.LocalAiStreamChunkMessage(
          text: 'Partial text',
          isDone: true,
          errorCode: 'local-ai-generation-failed',
          errorMessage: 'Native model failed.',
        ),
      ];

      for (final message in messages) {
        expect(codec.decodeMessage(codec.encodeMessage(message)), message);
      }
    });

    test('treats NaN values as equal and hash-compatible', () {
      final first = generated.LocalAiGenerationConfigMessage(
        temperature: double.nan,
      );
      final second = generated.LocalAiGenerationConfigMessage(
        temperature: double.nan,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('OnDeviceAiHostApi channel bridge', () {
    late TestDefaultBinaryMessenger messenger;
    late List<_HostCall> calls;
    const suffix = 'hardening';

    setUp(() {
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      calls = <_HostCall>[];
    });

    tearDown(() {
      for (final method in _hostMethods) {
        _clearHostHandler(messenger, method, suffix);
      }
    });

    test('uses suffixed channels and maps host replies', () async {
      _setHostHandler(messenger, 'availability', suffix, calls, (_) async {
        return <Object?>[
          generated.LocalAiAvailabilityMessage(
            isAvailable: true,
            modelStatus: 'available',
          ),
        ];
      });
      final hostApi = generated.OnDeviceAiHostApi(
        binaryMessenger: messenger,
        messageChannelSuffix: suffix,
      );
      final adapter = OnDeviceAiHostApiAdapter(hostApi: hostApi);

      final availability = await adapter.availability();

      expect(availability.isAvailable, isTrue);
      expect(availability.modelStatus, 'available');
      expect(calls.single.channelName, _hostChannel('availability', suffix));
      expect(calls.single.message, isNull);
    });

    test('sends prompt and generation config over the bridge', () async {
      _setHostHandler(messenger, 'generateText', suffix, calls, (
        message,
      ) async {
        final args = message! as List<Object?>;
        final config = args[1]! as generated.LocalAiGenerationConfigMessage;

        expect(args[0], 'Summarize privately.');
        expect(config.maxTokens, 96);
        expect(config.temperature, 0.25);

        return <Object?>[
          generated.LocalAiGenerationResponseMessage(
            text: 'Private summary',
            tokenCount: 4,
            durationMs: 10,
          ),
        ];
      });
      final hostApi = generated.OnDeviceAiHostApi(
        binaryMessenger: messenger,
        messageChannelSuffix: suffix,
      );
      final adapter = OnDeviceAiHostApiAdapter(hostApi: hostApi);

      final response = await adapter.generateText(
        'Summarize privately.',
        generated.LocalAiGenerationConfigMessage(
          maxTokens: 96,
          temperature: 0.25,
        ),
      );

      expect(response.text, 'Private summary');
      expect(response.tokenCount, 4);
      expect(calls.single.channelName, _hostChannel('generateText', suffix));
    });

    test('propagates platform errors from host replies', () async {
      _setHostHandler(messenger, 'generateText', suffix, calls, (_) async {
        return <Object?>[
          'local-ai-unavailable',
          'Model unavailable.',
          'downloadable',
        ];
      });
      final hostApi = generated.OnDeviceAiHostApi(
        binaryMessenger: messenger,
        messageChannelSuffix: suffix,
      );
      final adapter = OnDeviceAiHostApiAdapter(hostApi: hostApi);

      await expectLater(
        adapter.generateText(
          'Hello',
          generated.LocalAiGenerationConfigMessage(),
        ),
        throwsA(
          isA<PlatformException>()
              .having((error) => error.code, 'code', 'local-ai-unavailable')
              .having((error) => error.message, 'message', 'Model unavailable.')
              .having((error) => error.details, 'details', 'downloadable'),
        ),
      );
    });

    test('throws channel error when host is not registered', () async {
      final hostApi = generated.OnDeviceAiHostApi(
        binaryMessenger: messenger,
        messageChannelSuffix: suffix,
      );
      final adapter = OnDeviceAiHostApiAdapter(hostApi: hostApi);

      await expectLater(
        adapter.availability(),
        throwsA(
          isA<PlatformException>()
              .having((error) => error.code, 'code', 'channel-error')
              .having(
                (error) => error.message,
                'message',
                contains(_hostChannel('availability', suffix)),
              ),
        ),
      );
    });
  });

  group('generation stream bridge', () {
    late TestDefaultBinaryMessenger messenger;
    const instanceName = 'hardeningStream';
    const channelName =
        'dev.flutter.pigeon.flutter_native_ai.OnDeviceAiStreamApi.generationStream.$instanceName';

    setUp(() {
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(
        MethodChannel(channelName, generated.pigeonMethodCodec),
        null,
      );
    });

    test('decodes native stream events', () async {
      final methodCalls = <MethodCall>[];
      messenger.setMockMethodCallHandler(
        MethodChannel(channelName, generated.pigeonMethodCodec),
        (call) async {
          methodCalls.add(call);
          return null;
        },
      );

      final chunksFuture = generated
          .generationStream(instanceName: instanceName)
          .take(1)
          .toList();
      await pumpEventQueue();

      await messenger.handlePlatformMessage(
        channelName,
        generated.pigeonMethodCodec.encodeSuccessEnvelope(
          generated.LocalAiStreamChunkMessage(text: 'Streamed', isDone: false),
        ),
        (_) {},
      );

      final chunks = await chunksFuture;

      expect(methodCalls.map((call) => call.method), ['listen', 'cancel']);
      expect(chunks.single.text, 'Streamed');
      expect(chunks.single.isDone, isFalse);
    });
  });
}

const _hostMethods = <String>[
  'availability',
  'initialize',
  'generateText',
  'startStreamingText',
  'cancelStreamingText',
];

typedef _HostReplyBuilder = Future<Object?> Function(Object? message);

class _HostCall {
  const _HostCall(this.channelName, this.message);

  final String channelName;
  final Object? message;
}

String _hostChannel(String method, String suffix) {
  return 'dev.flutter.pigeon.flutter_native_ai.OnDeviceAiHostApi.$method.$suffix';
}

void _setHostHandler(
  TestDefaultBinaryMessenger messenger,
  String method,
  String suffix,
  List<_HostCall> calls,
  _HostReplyBuilder buildReply,
) {
  final channelName = _hostChannel(method, suffix);
  final channel = BasicMessageChannel<Object?>(
    channelName,
    generated.OnDeviceAiHostApi.pigeonChannelCodec,
    binaryMessenger: messenger,
  );
  messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
    calls.add(_HostCall(channelName, message));
    return buildReply(message);
  });
}

void _clearHostHandler(
  TestDefaultBinaryMessenger messenger,
  String method,
  String suffix,
) {
  final channel = BasicMessageChannel<Object?>(
    _hostChannel(method, suffix),
    generated.OnDeviceAiHostApi.pigeonChannelCodec,
    binaryMessenger: messenger,
  );
  messenger.setMockDecodedMessageHandler<Object?>(channel, null);
}
