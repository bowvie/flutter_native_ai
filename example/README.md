# flutter_on_device_ai_example

Example app for `flutter_on_device_ai`.

The app checks native model availability on launch, lets you edit a prompt, and
streams generated text into the UI when the current device supports on-device AI.

Run it on a physical device for meaningful results:

```sh
flutter run
```

Simulators and older OS versions usually report the model as unavailable.
