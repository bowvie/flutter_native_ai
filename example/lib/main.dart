import 'dart:async';

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

  OnDeviceAiStatus? _status;
  String _output = '';
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final status = await _ai.status();
    if (!mounted) {
      return;
    }
    setState(() => _status = status);
  }

  Future<void> _generate() async {
    final status = _status;
    if (status == null || _isGenerating) {
      return;
    }
    if (!status.isAvailable && !status.canInitialize) {
      return;
    }

    setState(() {
      _isGenerating = true;
      _output = '';
    });

    try {
      final session = await _ai.createSession(
        instructions: 'You are concise and practical.',
        initializationPolicy: OnDeviceAiInitializationPolicy.whenNeeded,
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
        unawaited(_checkStatus());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;

    return Scaffold(
      appBar: AppBar(title: const Text('On-device AI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            status == null
                ? 'Checking status...'
                : status.isAvailable
                ? 'Ready (${status.platformStatus ?? 'available'})'
                : status.canInitialize
                ? 'Model can be initialized (${status.platformStatus ?? 'not ready'})'
                : status.reason ?? 'Unavailable',
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
            onPressed:
                status != null &&
                    (status.isAvailable || status.canInitialize) &&
                    !_isGenerating
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
