/// 冒烟测试：应用能在没有任何网络的情况下起屏并显示连接页。
///
/// 这里刻意只测「纯 Dart 逻辑 + 首帧」：真正的行为口径在 `test/` 下的领域单测里，
/// 需要网络的路径一律用假 transport（见 `test/support/fakes.dart`）。
library;

import 'package:dsh_companion_ios/app.dart';
import 'package:dsh_companion_ios/core/app_preferences.dart';
import 'package:dsh_companion_ios/core/host_store.dart';
import 'package:dsh_companion_ios/platform/platform_deps.dart';
import 'package:dsh_companion_ios/state/harness_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('冷启动显示连接页', (WidgetTester tester) async {
    final store = MemoryKeyValueStore();
    final deps = AppDeps(
      hostStore: HostStore(store, MemorySecretBox()),
      prefs: AppPreferences(store),
      platform: PlatformDeps(
        uuid: () => 'test-uuid',
        timeZone: () async => 'Asia/Shanghai',
        deviceName: () => 'Test iPhone',
      ),
      http: FakeHttpTransport(),
      socket: FakeWebSocketTransport(),
      timers: FakeTimerBridge(),
    );
    final vm = HarnessViewModel(deps);
    await tester.pumpWidget(DshApp(viewModel: vm));
    await tester.pump();

    expect(find.text('连接你的电脑'), findsOneWidget);
  });
}
