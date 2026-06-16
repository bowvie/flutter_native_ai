# flutter_native_ai

A Flutter plugin for private, on-device text generation using native platform AI
models. It gives Flutter apps one small Dart API over Apple Foundation Models on
Apple platforms and Gemini Nano through ML Kit Prompt API / AICore on Android.

The package exposes one Dart API for checking availability, initializing a local
model session, generating a complete response, and streaming cumulative text
updates.

## Platform Support

| Platform | Minimum app target | Native model requirement | Runtime behavior |
| --- | --- | --- | --- |
| iOS | iOS 13.0 | Apple Foundation Models on supported OS/device combinations | Installs on older iOS versions; `availability()` returns unavailable when Foundation Models are not present |
| macOS | macOS 13.0 | Apple Foundation Models on supported OS/device combinations | Installs on macOS 13.0+; `availability()` returns unavailable when Foundation Models are not present |
| Android | minSdk 26 | Gemini Nano through ML Kit Prompt API / AICore on supported devices | Installs on Android 8.0+; `availability()` returns unavailable unless the native model is available |
| Other platforms | Not supported | None | Returns unsupported availability |

This package does not send prompts or generated text to a server. Generation is
performed by native on-device model APIs when those APIs are available.

## Use Case

The package was extracted from [Pooka](https://pooka.app), where it powers short
private collection insights without sending collection data to a backend model.

## Installation

```yaml
dependencies:
  flutter_native_ai: ^0.1.1
```

## Usage

```dart
import 'package:flutter_native_ai/flutter_native_ai.dart';

final ai = OnDeviceAi();

final availability = await ai.availability();
if (!availability.isAvailable) {
  print(availability.reason);
  return;
}

await ai.initialize(
  instructions: 'You are a concise assistant. Keep answers practical.',
);

final result = await ai.generateText(
  prompt: 'Write one sentence about on-device AI.',
  config: const OnDeviceAiGenerationConfig(
    maxTokens: 80,
    temperature: 0.4,
  ),
);

print(result.text);
```

Streaming:

```dart
await for (final chunk in ai.generateTextStream(
  prompt: 'Summarize this in two short sentences.',
)) {
  print(chunk.text);
}
```

Stream chunks are cumulative snapshots. If the model emits `"Hello"` and then
`"Hello world"`, the stream emits both snapshots rather than only the delta.

## Availability

Always call `availability()` before initializing or generating text. Native model
availability depends on the OS, device, regional/account settings, and whether
the local model is present.

The minimum app target only describes where the plugin can be installed. It does
not guarantee that native AI is available. For example, iOS versions below the
Foundation Models runtime still work as app targets, but this package reports
the model as unavailable. Foundation Models currently requires iOS 26.0 or
macOS 26.0 or later at runtime.

Android currently reports `downloadable` and `downloading` states as unavailable.
The package does not start model downloads automatically.

## API

Main entry point:

- `OnDeviceAi`

Models:

- `OnDeviceAiAvailability`
- `OnDeviceAiGenerationConfig`
- `OnDeviceAiGenerationResult`
- `OnDeviceAiStreamChunk`

Methods:

- `availability()`
- `initialize({String? instructions})`
- `generateText({required String prompt, OnDeviceAiGenerationConfig config})`
- `generateTextStream({required String prompt, OnDeviceAiGenerationConfig config})`
- `cancelStreamingText()`

## Regenerating Platform Bindings

Platform channels are generated with Pigeon from `pigeons/on_device_ai.dart`.

```sh
dart run pigeon --input pigeons/on_device_ai.dart
dart format lib/src/generated/on_device_ai.g.dart pigeons/on_device_ai.dart
```

The generated Swift binding is written to
`darwin/flutter_native_ai/Sources/flutter_native_ai/OnDeviceAi.g.swift` so the
same Apple implementation can be used by both CocoaPods and Swift Package
Manager.

## Apple Package Managers

The iOS and macOS implementations share one Darwin source package under
`darwin/flutter_native_ai`. Flutter apps can consume it through Swift Package
Manager or CocoaPods. The bundled macOS example uses Swift Package Manager and
does not include CocoaPods integration.

Pigeon currently emits `open fun` modifiers in a generated Kotlin interface.
Those are removed in the checked-in generated Kotlin binding because Kotlin
interface members are overridable by default.

## AI-Assisted Development

This package was built with AI assistance for parts of the implementation,
especially around the Pigeon contract, generated platform-channel integration,
and native bridge scaffolding. AI was used as an engineering tool in a deliberate
implementation process; the package is not vibe-coded.

## Notes

This package is an early alpha. Apple Foundation Models and Gemini Nano APIs are
new and may change. The Dart API is intentionally small so platform-specific
changes can be handled behind the plugin boundary.
