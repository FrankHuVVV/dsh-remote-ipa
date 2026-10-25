/// 入口 —— 组装依赖、启动主状态机。
///
/// 依赖顺序是刻意的：偏好（明文）先就绪，再打开钥匙串中的主机记录 —— 后者失败也要
/// 让界面起来（只是没有已保存的电脑），而不是白屏。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_preferences.dart';
import 'core/host_store.dart';
import 'platform/http_transport.dart';
import 'platform/platform_deps.dart';
import 'platform/secure_store.dart';
import 'platform/ws_transport.dart';
import 'state/harness_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await PrefsKeyValueStore.open();
  final prefs = AppPreferences(store);
  final hostStore = HostStore(store, KeychainSecretBox());
  final timers = TimerBridgeImpl();
  final deps = AppDeps(
    hostStore: hostStore,
    prefs: prefs,
    platform: PlatformDeps(),
    http: HttpTransportImpl(),
    socket: const WebSocketTransportImpl(),
    timers: timers,
  );
  final viewModel = HarnessViewModel(deps);
  runApp(DshApp(viewModel: viewModel));
  unawaited(viewModel.init());
}
