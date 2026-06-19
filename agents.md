# Agent Instructions

This is a Flutter plugin that exposes a single, intentionally small Dart API for private, on-device text generation. It bridges Apple Foundation Models (iOS 26+, macOS 26+) and Gemini Nano through ML Kit Prompt API (Android). The package can initialize/download supported Android models locally when explicitly requested. It does not send prompts or generated text to any server.

## Architecture

The plugin has three layers:

1. **Pigeon contract** (`pigeons/on_device_ai.dart`) — the single source of truth for the platform channel interface. Never edit generated files directly.
2. **Dart service** (`lib/src/on_device_ai_service.dart`) — wraps the generated host API into the public `OnDeviceAi` and `OnDeviceAiSession` classes that consumers use.
3. **Native bridges** — one per platform, each implementing `OnDeviceAiHostApi` from the Pigeon contract:
   - `darwin/flutter_native_ai/Sources/flutter_native_ai/OnDeviceAiBridge.swift` — shared iOS/macOS, uses `FoundationModels`
   - `android/src/main/kotlin/com/bowvie/flutter_native_ai/OnDeviceAiBridge.kt` — uses `com.google.mlkit.genai`

The public API surface is exported from `lib/flutter_native_ai.dart`. Only what is listed in that export is public.

## Key Constraints

**Status must be checked first.** The plugin installs on older OS versions where native AI is unavailable. `status()` is the gate; never assume a session can be created without checking it.

**Status separates support from readiness.** `OnDeviceAiStatus.isSupported` means the host can support local AI; `isReady` means generation can run now; `isAvailable` is the convenience getter for `isSupported && isReady`. `canInitialize` and `isInitializing` describe model initialization/download capability, not generation state.

**Initialization is explicit.** `ensureReady()` may initialize/download a model when the platform supports it. `createSession()` does not initialize by default; callers must pass `initializationPolicy: OnDeviceAiInitializationPolicy.whenNeeded` or `always` for just-in-time initialization.

**Initialization progress is real or null.** `statusStream()` emits model initialization status snapshots. `initializationProgress` is a nullable `0..100` integer and must only be set from real native progress. Do not synthesize percentages from time, polling count, or guessed phases.

**Stream chunks are cumulative snapshots.** Each chunk contains the full text generated so far, not a delta. If the model emits `"Hello"` then `"Hello world"`, the stream emits both. Consumer UIs should replace, not append.

**One active stream per plugin instance.** The event channel carries no session identifier. Starting a new stream cancels any in-flight one on both Apple and Android bridges.

**Sessions own native resources.** Always call `dispose()` when a generation flow is finished. Android sessions also maintain a rolling conversation history (capped at 20 messages) to simulate stateful context.

**Session disposal is retryable.** If `disposeSession` throws, `isDisposed` reverts to `false` so the caller can retry. This is intentional — do not change it.

## Pigeon Code Generation

All platform channel types and method signatures live in `pigeons/on_device_ai.dart`. After changing this file, regenerate all bindings:

```sh
dart run pigeon --input pigeons/on_device_ai.dart
dart format lib/src/generated/on_device_ai.g.dart pigeons/on_device_ai.dart
```

The generated Swift file goes to `darwin/flutter_native_ai/Sources/flutter_native_ai/OnDeviceAi.g.swift`, where it is shared by both CocoaPods and Swift Package Manager. The Kotlin binding goes to `android/src/main/kotlin/com/bowvie/flutter_native_ai/OnDeviceAi.g.kt`.

**Known Pigeon quirk:** Pigeon emits `open fun` modifiers in the generated Kotlin event-channel wrapper. The local lint configuration rejects `open fun`. Remove those modifiers from the checked-in Kotlin binding after regeneration.

## Platform Notes

### Apple (iOS / macOS)
- Requires `FoundationModels` framework, available from iOS 26.0 and macOS 26.0.
- The bridge is compiled even on SDKs without `FoundationModels` using `#if canImport(FoundationModels)` guards, so older SDKs build cleanly.
- Runtime status maps `SystemLanguageModel.default.availability` into `LocalAiStatusMessage`.
- `ensureReady()` is an immediate status refresh on Apple. Foundation Models does not expose an app-triggered download path today.
- Sessions are stored as `[String: Any]` keyed by a UUID string. Type-cast to `LocalAiSession` when retrieved.
- Streaming uses `LanguageModelSession.streamResponse`. Foundation Models itself emits cumulative snapshots: each `snapshot.content` is the full text generated so far. The bridge assigns `latestText = snapshot.content` and forwards it directly — no manual accumulation needed on the Apple side.
- The shared Darwin source package lives under `darwin/flutter_native_ai`. Both CocoaPods (`darwin/flutter_native_ai.podspec`) and Swift Package Manager (`darwin/flutter_native_ai/Package.swift`) consume it.

### Android
- Uses ML Kit Prompt API (`com.google.mlkit.genai`).
- `status()` maps `FeatureStatus.AVAILABLE` to ready, `DOWNLOADABLE` to supported/not ready/can initialize, `DOWNLOADING` to supported/not ready/initializing, and `UNAVAILABLE` to unsupported/not ready.
- `ensureReady()` uses `GenerativeModel.download()` for Android model download/provisioning when the model is downloadable or already downloading.
- Android initialization progress comes from ML Kit `DownloadStatus`: `DownloadStarted.bytesToDownload`, `DownloadProgress.totalBytesDownloaded`, `DownloadCompleted`, and `DownloadFailed`. Compute `initializationProgress` only when real byte progress is available; emit `100` on completion.
- `LocalAiSession` manually simulates conversation history by composing a text prompt that includes instructions, previous turns (user + assistant), and the new user request. History is capped at 20 messages.
- The bridge runs on a `CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)`. Background work dispatches to `Dispatchers.Default`. Stream handler runs on its own `CoroutineScope(Dispatchers.Default)`.
- `maxOutputTokens` is clamped to `[1, 256]`. The default when not specified is 160.
- Cancellation emits a terminal chunk with `isDone = true` in a `NonCancellable` context so Dart listeners complete deterministically.
- Call `OnDeviceAiBridge.close()` during plugin detach to cancel all coroutines.

## Testing

Unit tests live in `test/`. They use a `_FakeHostApi` that extends the generated `OnDeviceAiHostApi` directly — no mocking framework. Tests cover the Dart service layer and do not test native bridges.

Run tests:
```sh
flutter test test
```

Integration tests are in `example/integration_test/plugin_integration_test.dart` and require a real device.

## CI

CI runs on `ubuntu-latest` via `.github/workflows/ci.yml` on every push to `main` and every PR. Steps:
1. `flutter pub get`
2. `dart format --set-exit-if-changed lib test pigeons example/lib example/test example/integration_test`
3. `flutter analyze`
4. `flutter test test`
5. `dart pub publish --dry-run`

All five steps must pass before merging. Format and analyze are strict — no warnings are acceptable.

## Release Workflow

1. Bump `version` in `pubspec.yaml` and `s.version` in `darwin/flutter_native_ai.podspec` to the new version (they must always match).
2. Add a `## <version>` section at the top of `CHANGELOG.md`.
3. Run `flutter analyze`, `flutter test test`, and `dart pub publish --dry-run` — all must pass.
4. Commit, open a PR, merge to `main`.
5. Create a Git tag with **no `v` prefix** — e.g. `0.4.1`, not `v0.4.1`. The `.github/workflows/publish.yml` trigger pattern is `[0-9]+.[0-9]+.[0-9]+`; a `v`-prefixed tag will not match and the publish workflow will not run.
   ```sh
   git tag 0.4.1 <commit-sha>
   git push origin 0.4.1
   ```
6. Create the GitHub release targeting that tag:
   ```sh
   gh release create 0.4.1 --title "0.4.1" --notes "<changelog content>"
   ```

## Development Workflow

### Adding a new API method
1. Add the method to the `@HostApi` class in `pigeons/on_device_ai.dart`.
2. Regenerate bindings (see above) and remove `open fun` from the Kotlin output.
3. Implement the method in `OnDeviceAiBridge.swift` and `OnDeviceAiBridge.kt`.
4. Expose the method through `OnDeviceAiSession` or `OnDeviceAi` in `on_device_ai_service.dart`.
5. Export any new public types from `lib/flutter_native_ai.dart`.
6. Add unit tests in `test/` using `_FakeHostApi`.
7. Update `CHANGELOG.md`.

### Updating model lifecycle behaviour
1. Keep `status()` non-mutating. It should only report current support/readiness/initialization state.
2. Put mutating model setup in `ensureReady()`.
3. Keep `createSession()` default behaviour non-mutating. Any just-in-time initialization must be gated by an explicit initialization policy.
4. Preserve nullable progress semantics: report progress only when the native platform provides real progress.

### Adding a new platform
1. Add an entry under `flutter.plugin.platforms` in `pubspec.yaml`.
2. Create a bridge class implementing `OnDeviceAiHostApi` from the Pigeon contract.
3. Register the bridge in the plugin registration class for that platform.
4. Extend CI if the platform can be tested on the CI runner.

## Code Style

- No lint suppressions without a comment explaining why.
- Comments only where the code is non-obvious; avoid restating what the code does.
- Dart: follow `flutter_lints`. No `open fun` in generated Kotlin (lint rejects it).
- Swift: use `#if canImport` and `#available` guards rather than assuming SDK version.
- Keep the public Dart API intentionally small. Resist adding convenience methods that callers can implement themselves.
