import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'server_address.dart';

/// サーバーのアドレスを入力して保存する画面。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(serverAddressProvider).value;
    _controller = TextEditingController(
      text: current == null ? '' : '${current.host}:${current.port}',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref.read(serverAddressProvider.notifier).save(_controller.text);
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('サーバーの設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'サーバーのアドレス',
                hintText: '192.168.0.10:8765',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
