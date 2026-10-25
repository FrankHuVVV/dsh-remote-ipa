/// 设置页 —— 移植自鸿蒙版 `ui/SettingsScreen.ets` 的 iOS 裁剪版。
///
/// 取舍：鸿蒙版把「切换电脑」放在连接页；iOS 侧连接页只在未连接时出现，
/// 所以这里给出「电脑列表 + 断开」入口 —— 否则一旦连上就再也换不了机器。
library;

import 'package:flutter/material.dart';

import '../core/build_stamp.dart';
import '../core/connection_models.dart';
import '../core/small_parts.dart';
import '../l10n/strings.dart';
import '../state/harness_view_model.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.viewModel});

  final HarnessViewModel viewModel;

  Strings get s => viewModel.strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (BuildContext context, _) {
        final state = viewModel.state;
        final scopes = state.device?.scopes ?? const <String>[];
        final missing = state.bridgeCapabilities == null
            ? const <String>[]
            : missingRequiredCapabilities(state.bridgeCapabilities!);
        return Scaffold(
          appBar: AppBar(title: Text(s.get('settings_title'))),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: <Widget>[
              if (state.error != null) ErrorBar(message: state.error!, onDismiss: viewModel.clearError),
              if (state.notice != null) NoticeBar(message: state.notice!, onDismiss: viewModel.clearNotice),
              if (missing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      s.format('settings_missing_capabilities', <String, String>{
                        'names': missing.join('、'),
                      }),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),

              SectionHeader(title: s.get('settings_appearance')),
              _themeTile(context, state.themeMode),
              SwitchListTile(
                dense: true,
                title: Text(s.get('font_follows_system')),
                value: state.fontFollowsSystem,
                onChanged: viewModel.setFontFollowsSystem,
              ),
              if (!state.fontFollowsSystem)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: <Widget>[
                      const Text('A', style: TextStyle(fontSize: 11)),
                      Expanded(
                        child: Slider(
                          value: state.fontScale,
                          min: fontScaleMin,
                          max: fontScaleMax,
                          divisions: 7,
                          label: state.fontScale.toStringAsFixed(1),
                          onChanged: viewModel.setFontScale,
                        ),
                      ),
                      const Text('A', style: TextStyle(fontSize: 17)),
                    ],
                  ),
                ),

              const Divider(height: 24),
              SectionHeader(title: s.get('settings_chat')),
              ListTile(
                dense: true,
                title: Text(s.get('settings_language')),
                trailing: Text(
                  state.languageTag == 'en' ? s.get('language_en') : s.get('language_zh'),
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                onTap: () => viewModel.setLanguage(state.languageTag == 'en' ? 'zh-CN' : 'en'),
              ),
              SwitchListTile(
                dense: true,
                title: Text(s.get('settings_show_context')),
                subtitle: Text(s.get('settings_show_context_hint'), style: const TextStyle(fontSize: 11)),
                value: state.showContext,
                onChanged: viewModel.setShowContext,
              ),
              ListTile(
                dense: true,
                title: Text(s.get('settings_send_mode')),
                trailing: SegmentedButton<String>(
                  segments: <ButtonSegment<String>>[
                    ButtonSegment<String>(value: sendModeQueue, label: Text(s.get('queue'))),
                    ButtonSegment<String>(value: sendModeSteer, label: Text(s.get('steer'))),
                  ],
                  selected: <String>{state.busySendMode},
                  onSelectionChanged: (Set<String> value) => viewModel.setSendMode(value.first),
                ),
              ),

              const Divider(height: 24),
              SectionHeader(title: s.get('settings_connection')),
              ListTile(
                dense: true,
                title: Text(s.get('settings_endpoint')),
                subtitle: Text(state.endpoint, style: const TextStyle(fontSize: 12)),
                trailing: StatusLabel(
                  label: state.eventsConnected ? s.get('settings_online') : s.get('settings_offline'),
                  active: state.eventsConnected,
                ),
              ),
              for (final host in state.hosts)
                ListTile(
                  dense: true,
                  leading: const Text('💻', style: TextStyle(fontSize: 16)),
                  title: Text(host.displayName),
                  subtitle: Text(
                    host.endpoints.map((Endpoint e) => e.baseUrl).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: host.id == state.activeHostId
                      ? Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: host.id == state.activeHostId ? null : () => viewModel.connectHost(host.id),
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.link_off, size: 18),
                title: Text(s.get('settings_disconnect')),
                onTap: () => viewModel.disconnect(),
              ),

              const Divider(height: 24),
              SectionHeader(title: s.get('settings_about')),
              ListTile(
                dense: true,
                title: Text(s.get('settings_version')),
                subtitle: Text('$appVersion ($appBuildNumber) · $buildStampLine', style: const TextStyle(fontSize: 11)),
              ),
              ListTile(
                dense: true,
                title: Text(s.get('settings_device')),
                subtitle: Text(
                  '${state.device?.name ?? '—'} · ${state.device?.id ?? ''}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              ListTile(
                dense: true,
                title: Text(s.get('settings_scopes')),
                subtitle: Text(scopes.isEmpty ? '—' : scopes.join(', '), style: const TextStyle(fontSize: 11)),
              ),
              ListTile(
                dense: true,
                title: Text(s.get('settings_bridge')),
                subtitle: Text(state.bridgeVersion ?? s.get('settings_bridge_unknown'), style: const TextStyle(fontSize: 11)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  s.get('settings_privacy'),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                child: Text(
                  s.get('settings_storage_note'),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _themeTile(BuildContext context, String mode) {
    return ListTile(
      dense: true,
      title: Text(s.get('settings_theme')),
      trailing: SegmentedButton<String>(
        segments: <ButtonSegment<String>>[
          ButtonSegment<String>(value: themeModeSystem, label: Text(s.get('theme_system'))),
          ButtonSegment<String>(value: themeModeLight, label: Text(s.get('theme_light'))),
          ButtonSegment<String>(value: themeModeDark, label: Text(s.get('theme_dark'))),
        ],
        selected: <String>{normalizeThemeMode(mode)},
        onSelectionChanged: (Set<String> value) => viewModel.setThemeMode(value.first),
      ),
    );
  }
}
