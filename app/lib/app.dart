/// 应用外壳 —— 主题、语言、字号、前后台事件流。
library;

import 'package:flutter/material.dart';

import 'core/small_parts.dart';
import 'l10n/strings.dart';
import 'state/harness_view_model.dart';
import 'ui/app_shell.dart';
import 'ui/connect_screen.dart';
import 'ui/theme.dart';

class DshApp extends StatefulWidget {
  const DshApp({super.key, required this.viewModel});

  final HarnessViewModel viewModel;

  @override
  State<DshApp> createState() => _DshAppState();
}

class _DshAppState extends State<DshApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 熄屏 / 切后台只关事件流，保留连接与令牌；回来时重开并补拉（见 ViewModel.resumeEvents）。
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      widget.viewModel.pauseEvents();
    } else if (state == AppLifecycleState.resumed) {
      widget.viewModel.resumeEvents();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (BuildContext context, _) {
        final state = widget.viewModel.state;
        final strings = Strings.of(state.languageTag);
        final scale = effectiveFontScale(
          followsSystem: state.fontFollowsSystem,
          scale: state.fontScale,
        );
        return MaterialApp(
          title: strings.get('app_name'),
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(brightness: Brightness.light),
          darkTheme: buildAppTheme(brightness: Brightness.dark),
          themeMode: themeModeOf(state.themeMode),
          locale: Locale(strings.isEnglish ? 'en' : 'zh'),
          builder: (BuildContext context, Widget? child) {
            final media = MediaQuery.of(context);
            final systemScale = media.textScaler.scale(1);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(systemScale * scale),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: state.connected
              ? AppShell(viewModel: widget.viewModel)
              : ConnectScreen(viewModel: widget.viewModel),
        );
      },
    );
  }
}
