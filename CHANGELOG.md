## 0.4.0

- Replaces `availability()` with `status()` and `OnDeviceAiStatus`, separating
    platform support, model readiness, initialization capability, and raw native
    diagnostics.
- Adds `ensureReady()` for explicit model initialization/download flows.
- Adds `OnDeviceAiInitializationPolicy` and opt-in just-in-time initialization
    through `createSession(initializationPolicy: ...)`.
- Adds `statusStream()` for model initialization status updates, including real
    `0..100` Android download progress when ML Kit supplies enough byte data.
- Adds Android Gemini Nano model download support through ML Kit
    `GenerativeModel.download()`.

## 0.3.0

- Replaces service-level initialization and generation with explicit
    `OnDeviceAiSession` creation.
- Adds session-scoped non-streaming generation, streaming generation,
    cancellation, and disposal.
- Documents that only one streaming generation should be active at a time for a
    plugin instance.
- Reuses native Apple Foundation Models sessions across prompts in the same
    Dart session.
- Keeps per-session Android instructions and prompt history for Gemini Nano
    requests.

## 0.2.0

- Adds macOS plugin registration and an example macOS runner.
- Reuses the Apple Foundation Models bridge on macOS with runtime availability
    checks for macOS 26.0 or later.
- Adds Swift Package Manager support for the shared iOS/macOS implementation.
- Uses Swift Package Manager for both Apple example runners, including removing
    CocoaPods integration from the macOS runner.

## 0.1.1

iOS hotfix release.

- Fixes the Swift Package Manager library product name to match Flutter's
    generated hyphenated plugin product reference.

## 0.1.0

Initial pre-release

- Added an automated publish workflow

## 0.1.0-alpha.1

Initial alpha release.

- Adds a Dart API for on-device text generation availability, initialization,
  single response generation, streaming generation, and cancellation.
- Adds an iOS bridge for Apple Foundation Models.
- Adds an Android bridge for Gemini Nano through ML Kit Prompt API.
- Adds Pigeon-generated Dart, Swift, and Kotlin bindings.
