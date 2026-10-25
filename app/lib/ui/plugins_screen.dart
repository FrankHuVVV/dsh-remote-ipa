/// 插件页 —— 移植自鸿蒙版 `ui/PluginsScreen.ets`。
///
/// 关键点：`restartRequired` **恒为 true**（profile 清单只在 DSH 启动时读一次），
/// 所以开关只是「写进 profile」，界面必须明说，否则用户以为开关坏了。
library;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../l10n/strings.dart';
import '../state/harness_view_model.dart';
import 'widgets.dart';

class PluginsScreen extends StatelessWidget {
  const PluginsScreen({super.key, required this.viewModel});

  final HarnessViewModel viewModel;

  Strings get s => viewModel.strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (BuildContext context, _) {
        final state = viewModel.state;
        final inventory = state.pluginInventory;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.get('plugins_title')),
            actions: <Widget>[
              IconButton(
                tooltip: s.get('plugin_check_updates'),
                onPressed: state.pluginCheckingUpdates
                    ? null
                    : () => viewModel.refreshPlugins(checkUpdates: true),
                icon: state.pluginCheckingUpdates
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.system_update_alt),
              ),
              IconButton(
                tooltip: s.get('refresh'),
                onPressed: viewModel.refreshPlugins,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              if (state.error != null) ErrorBar(message: state.error!, onDismiss: viewModel.clearError),
              if (state.notice != null) NoticeBar(message: state.notice!, onDismiss: viewModel.clearNotice),
              Expanded(
                child: inventory == null
                    ? EmptyState(text: s.get('loading'))
                    : !inventory.available
                        ? EmptyState(
                            text: s.format('plugin_inventory_unavailable', <String, String>{
                              'reason': inventory.reason ?? '—',
                            }),
                          )
                        : ListView.separated(
                            itemCount: inventory.items.length + 1,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (BuildContext context, int index) {
                              if (index == 0) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                                  child: Text(
                                    '${inventory.loadedCount} / ${inventory.items.length}'
                                    '${inventory.problemCount > 0 ? '  ⚠ ${inventory.problemCount}' : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                );
                              }
                              return _row(context, inventory.items[index - 1]);
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, PluginEntry plugin) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        plugin.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (plugin.official) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          s.get('plugin_official'),
                          style: TextStyle(fontSize: 9, color: scheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  plugin.installed ?? plugin.declared ?? '',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Text(
                  _stateLabel(plugin),
                  style: TextStyle(
                    fontSize: 11,
                    color: _isProblem(plugin) ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
                if (plugin.updateAvailable == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      s.format('plugin_update_available', <String, String>{
                        'version': plugin.latestVersion ?? '',
                      }),
                      style: TextStyle(fontSize: 11, color: scheme.primary),
                    ),
                  ),
                if (plugin.description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      plugin.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          if (plugin.toggleable)
            Switch(
              value: plugin.loaded,
              onChanged: viewModel.state.busy
                  ? null
                  : (bool value) => viewModel.togglePlugin(plugin, value),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Icon(
                plugin.loaded ? Icons.check_circle_outline : Icons.remove_circle_outline,
                size: 18,
                color: scheme.outline,
              ),
            ),
        ],
      ),
    );
  }

  bool _isProblem(PluginEntry plugin) =>
      plugin.state == 'declared-missing' || (plugin.declared != null && plugin.installed != null && plugin.declared != plugin.installed);

  String _stateLabel(PluginEntry plugin) {
    switch (plugin.state) {
      case 'loaded':
        return s.get('plugin_state_loaded');
      case 'installed-not-loaded':
        return s.get('plugin_state_installed_not_loaded');
      case 'declared-missing':
        return s.get('plugin_state_declared_missing');
      case 'runtime-provided':
        return s.get('plugin_state_runtime_provided');
      default:
        return plugin.state;
    }
  }
}
