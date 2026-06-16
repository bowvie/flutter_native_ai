# flutter_native_ai_example

Example app for `flutter_native_ai`.

The app checks native model availability on launch, lets you edit a prompt, and
streams generated text into the UI when the current device supports on-device AI.

Run it on a physical device for meaningful results:

```sh
flutter run
```

Simulators and older OS versions usually report the model as unavailable.

The iOS and macOS example runners are configured for Flutter's Swift Package
Manager integration. The macOS runner intentionally does not include a Podfile or
CocoaPods workspace integration. Android uses `minSdk 26` to match the plugin's
native dependency requirements.
