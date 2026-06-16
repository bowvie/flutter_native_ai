import 'package:flutter/material.dart';
import 'package:flutter_native_ai/flutter_native_ai.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const OnDeviceAiExampleScreen(),
    );
  }
}

class OnDeviceAiExampleScreen extends StatefulWidget {
  const OnDeviceAiExampleScreen({super.key});

  @override
  State<OnDeviceAiExampleScreen> createState() =>
      _OnDeviceAiExampleScreenState();
}

class _OnDeviceAiExampleScreenState extends State<OnDeviceAiExampleScreen> {
  final _ai = OnDeviceAi();
  final _promptController = TextEditingController(
    text: 'Explain on-device AI in one short sentence.',
  );

  OnDeviceAiAvailability? _availability;
  String _output = '';
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    final availability = await _ai.availability();
    if (!mounted) {
      return;
    }
    setState(() => _availability = availability);
  }

  Future<void> _generate() async {
    final availability = _availability;
    if (availability == null || !availability.isAvailable || _isGenerating) {
      return;
    }

    setState(() {
      _isGenerating = true;
      _output = '';
    });

    try {
      final session = await _ai.createSession(
        instructions: 'You are concise and practical.',
      );
      try {
        await for (final chunk in session.generateTextStream(
          prompt: _promptController.text,
          config: const OnDeviceAiGenerationConfig(maxTokens: 120),
        )) {
          if (!mounted) {
            return;
          }
          setState(() => _output = chunk.text);
        }
      } finally {
        await session.dispose();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _output = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;

    return Scaffold(
      appBar: AppBar(title: const Text('On-device AI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            availability == null
                ? 'Checking availability...'
                : availability.isAvailable
                ? 'Available (${availability.modelStatus ?? 'ready'})'
                : availability.reason ?? 'Unavailable',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _promptController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Prompt',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: availability?.isAvailable == true && !_isGenerating
                ? _generate
                : null,
            child: Text(_isGenerating ? 'Generating...' : 'Generate'),
          ),
          const SizedBox(height: 24),
          SelectableText(_output),
        ],
      ),
    );
  }
}
