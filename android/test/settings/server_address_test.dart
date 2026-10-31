import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_streamer/settings/server_address.dart';

import '../helpers.dart';

void main() {
  group('parseServerAddress', () {
    test('プライベート IP とポートからベース URL を作る', () {
      for (final (input, expected) in [
        ('192.168.0.10:8765', 'http://192.168.0.10:8765'),
        ('10.0.2.2:8765', 'http://10.0.2.2:8765'),
        ('172.16.0.1:8080', 'http://172.16.0.1:8080'),
        ('172.31.255.255:65535', 'http://172.31.255.255:65535'),
        ('  http://192.168.1.2:8765/  ', 'http://192.168.1.2:8765'),
      ]) {
        expect(parseServerAddress(input).toString(), expected, reason: input);
      }
    });

    test('LAN の外や不正な形式のアドレスは受け付けない', () {
      for (final input in [
        '',
        '192.168.0.10',
        '8.8.8.8:8765',
        '172.32.0.1:8765',
        '192.169.0.1:8765',
        'example.com:8765',
        '192.168.0.256:8765',
        '192.168.0.010:8765',
        '192.168.0:8765',
        '192.168.0.10:0',
        '192.168.0.10:70000',
        '192.168.0.10:abc',
        'https://192.168.0.10:8765',
        '192.168.0.10:8765/api',
      ]) {
        expect(
          () => parseServerAddress(input),
          throwsFormatException,
          reason: input,
        );
      }
    });
  });

  group('ServerAddressNotifier', () {
    test('保存済みのアドレスを読み込む', () async {
      final container = ProviderContainer.test(
        overrides: [
          serverAddressStorageProvider.overrideWithValue(
            InMemoryServerAddressStorage('192.168.0.10:8765'),
          ),
        ],
      );

      final uri = await container.read(serverAddressProvider.future);

      expect(uri, Uri.parse('http://192.168.0.10:8765'));
    });

    test('保存済みの値が不正なら未設定として扱う', () async {
      final container = ProviderContainer.test(
        overrides: [
          serverAddressStorageProvider.overrideWithValue(
            InMemoryServerAddressStorage('8.8.8.8:8765'),
          ),
        ],
      );

      expect(await container.read(serverAddressProvider.future), isNull);
    });

    test('入力を正規化して保存し、状態を更新する', () async {
      final storage = InMemoryServerAddressStorage();
      final container = ProviderContainer.test(
        overrides: [serverAddressStorageProvider.overrideWithValue(storage)],
      );
      await container.read(serverAddressProvider.future);

      await container
          .read(serverAddressProvider.notifier)
          .save('http://192.168.0.10:8765/');

      expect(storage.saved, '192.168.0.10:8765');
      expect(
        container.read(serverAddressProvider).value,
        Uri.parse('http://192.168.0.10:8765'),
      );
    });

    test('不正な入力は保存しない', () async {
      final storage = InMemoryServerAddressStorage('192.168.0.10:8765');
      final container = ProviderContainer.test(
        overrides: [serverAddressStorageProvider.overrideWithValue(storage)],
      );
      await container.read(serverAddressProvider.future);

      await expectLater(
        container.read(serverAddressProvider.notifier).save('8.8.8.8:8765'),
        throwsFormatException,
      );
      expect(storage.saved, '192.168.0.10:8765');
    });
  });
}
