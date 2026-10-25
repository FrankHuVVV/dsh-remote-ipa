/// 主界面外壳 —— 移植自鸿蒙版 `ui/AppShell.ets` 的「分节 + 权限过滤」。
///
/// 三个取舍必须保留：
/// 1. **默认分节按 `scopes` 选**：有 `chat.read` 进会话，否则 `files.read` 进文件，否则设置；
/// 2. **模型页 / 设置页永远可进**（即便缺 `settings.read`）—— 否则「为什么不可用」这条
///    提示永远不可达，用户只看到「没有这个页面」；
/// 3. **插件页要 `settings.read`**（它读的就是 `settings/plugins`）。
library;

import 'package:flutter/material.dart';

import '../state/harness_view_model.dart';
import 'files_screen.dart';
import 'models_screen.dart';
import 'plugins_screen.dart';
import 'sessions_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

enum MainSection { chat, files, plugins, models, settings }

bool sectionEnabled(MainSection section, List<String> scopes) {
  switch (section) {
    case MainSection.chat:
      return scopes.contains('chat.read');
    case MainSection.files:
      return scopes.contains('files.read');
    case MainSection.plugins:
      return scopes.contains('settings.read');
    case MainSection.models:
    case MainSection.settings:
      return true;
  }
}

String sectionKey(MainSection section) {
  switch (section) {
    case MainSection.chat:
      return 'chat';
    case MainSection.files:
      return 'files';
    case MainSection.plugins:
      return 'plugins';
    case MainSection.models:
      return 'models';
    case MainSection.settings:
      return 'settings';
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.viewModel});

  final HarnessViewModel viewModel;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  MainSection _section = MainSection.chat;
  String _scopesKey = '';

  HarnessViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.addListener(_onVmChanged);
    _syncSection();
  }

  @override
  void dispose() {
    vm.removeListener(_onVmChanged);
    super.dispose();
  }

  void _onVmChanged() {
    final key = (vm.state.device?.scopes ?? const <String>[]).join(',');
    if (key == _scopesKey) {
      return;
    }
    _scopesKey = key;
    // scopes 从空变成有值时自动落到会话页；已经手动切过分节则不再抢。
    if (sectionEnabled(_section, _scopes())) {
      return;
    }
    _syncSection();
  }

  List<String> _scopes() => vm.state.device?.scopes ?? const <String>[];

  void _syncSection() {
    final scopes = _scopes();
    MainSection next = _section;
    if (scopes.contains('chat.read')) {
      next = MainSection.chat;
    } else if (scopes.contains('files.read')) {
      next = MainSection.files;
    } else if (scopes.isNotEmpty) {
      next = MainSection.settings;
    }
    setState(() => _section = next);
  }

  @override
  Widget build(BuildContext context) {
    final scopes = _scopes();
    final sections = <MainSection>[
      for (final section in MainSection.values)
        if (sectionEnabled(section, scopes)) section,
    ];
    var index = sections.indexOf(_section);
    if (index < 0) {
      index = 0;
    }
    final strings = vm.strings;
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: <Widget>[
          for (final section in sections) _body(section),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        height: 58,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (int value) => setState(() => _section = sections[value]),
        destinations: <Widget>[
          for (final section in sections)
            NavigationDestination(
              icon: Text(sectionGlyphFor(sectionKey(section)), style: const TextStyle(fontSize: 20)),
              label: strings.get(sectionKey(section)),
            ),
        ],
      ),
    );
  }

  Widget _body(MainSection section) {
    switch (section) {
      case MainSection.chat:
        return SessionsScreen(viewModel: vm);
      case MainSection.files:
        return FilesScreen(viewModel: vm);
      case MainSection.plugins:
        return PluginsScreen(viewModel: vm);
      case MainSection.models:
        return ModelsScreen(viewModel: vm);
      case MainSection.settings:
        return SettingsScreen(viewModel: vm);
    }
  }
}
