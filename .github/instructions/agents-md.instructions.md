---
description: "Use when modifying the plugin architecture, Pigeon contract, Dart service, native bridges, public API surface, CI workflow, or platform support. Ensures agents.md stays current as the library grows."
applyTo:
  - "pigeons/**"
  - "lib/**"
  - "darwin/**/*.swift"
  - "darwin/**/*.podspec"
  - "android/**/*.kt"
  - "pubspec.yaml"
  - ".github/workflows/ci.yml"
---

# Keeping agents.md Up to Date

`agents.md` at the repository root is the primary context document for AI agents working in this codebase. It must be updated whenever a change affects how agents should understand or work with this project.

## When to update agents.md

Update it after any change to:

- **Pigeon contract** (`pigeons/on_device_ai.dart`) — new methods, types, or the event channel shape
- **Dart service** (`lib/src/on_device_ai_service.dart`) — public API behaviour, session lifecycle rules, streaming semantics
- **Public exports** (`lib/flutter_native_ai.dart`) — what is and is not part of the public surface
- **Native bridges** — platform-specific behaviour, availability logic, session management, concurrency model, or known quirks
- **Platform support** (`pubspec.yaml` `flutter.plugin.platforms`) — new or removed platform entries
- **Release artefacts** (`pubspec.yaml` `version`, `darwin/flutter_native_ai.podspec` `s.version`, `CHANGELOG.md`) — version numbers must stay in sync across all three files
- **CI steps** (`.github/workflows/ci.yml`) — steps agents need to know about before submitting changes
- **Constraints or invariants** — anything that would cause a bug if an agent assumed the wrong thing (e.g. cumulative stream chunks, single active stream, retryable dispose)

## What to update

Edit only the sections of `agents.md` affected by the change. Do not rewrite the whole file.

- Add new methods to the relevant **Architecture** or **Platform Notes** section
- Update the **Pigeon Code Generation** section if the regeneration workflow changes
- Update **Key Constraints** if a new behavioural rule or invariant is introduced
- Update the **Development Workflow** steps if the process changes
- Keep descriptions concrete: reference actual file paths, type names, and method names from the codebase
