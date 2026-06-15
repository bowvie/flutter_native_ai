import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_ai/flutter_native_ai.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('availability returns a platform response', (_) async {
    final ai = OnDeviceAi();

    final availability = await ai.availability();

    expect(availability.modelStatus, isNotEmpty);
  });
}
