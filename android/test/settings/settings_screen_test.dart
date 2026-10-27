import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:video_streamer/api/api_client.dart';
import 'package:video_streamer/api/providers.dart';
import 'package:video_streamer/main.dart';
import 'package:video_streamer/settings/server_address.dart';

import '../helpers.dart';

void main() {
  testWidgets('アドレスが未設定なら設定画面を出し、保存すると一覧画面に移る', (tester) async {
    final storage = InMemoryServerAddressStorage();
    await tester.pumpWidget(
      testScope(
        overrides: [
          serverAddressStorageProvider.overrideWithValue(storage),
          apiClientProvider.overrideWithValue(
            ApiClient(
              Uri.parse('http://192.168.0.10:8765'),
              httpClient: MockClient(
                (_) async => http.Response('{"path":"","entries":[]}', 200),
              ),
            ),
          ),
        ],
        child: const VideoStreamerApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('サーバーの設定'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '192.168.0.10:8765');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(storage.saved, '192.168.0.10:8765');
    expect(find.text('ライブラリ'), findsOneWidget);
  });

  testWidgets('LAN の外のアドレスは保存せず、理由を表示する', (tester) async {
    final storage = InMemoryServerAddressStorage();
    await tester.pumpWidget(
      testScope(
        overrides: [serverAddressStorageProvider.overrideWithValue(storage)],
        child: const VideoStreamerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '8.8.8.8:8765');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(storage.saved, isNull);
    expect(find.textContaining('LAN 内の IP アドレス'), findsOneWidget);
  });
}
