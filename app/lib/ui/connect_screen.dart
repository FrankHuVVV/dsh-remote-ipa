/// 连接页 —— 移植自鸿蒙版 `ui/ConnectScreen.ets`。
///
/// 三处关键行为（都是踩过坑才定下来的，不许简化）：
/// 1. 两条连接方式默认都收起、且互斥展开 —— 屏幕上不会同时铺两份表单；
/// 2. 「测试连接」只探活、不放行：用户点完还留在原页看结果；
/// 3. 「连接」与「测试」的启用条件分开：前者要真的建连，后者只发一次未鉴权请求。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/connection_models.dart';
import '../l10n/strings.dart';
import '../state/harness_state.dart';
import '../state/harness_view_model.dart';
import 'widgets.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.viewModel});

  final HarnessViewModel viewModel;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _endpoint = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _deviceName = TextEditingController();
  final TextEditingController _configText = TextEditingController();

  bool _importExpanded = false;
  bool _pairingExpanded = false;
  bool _seeded = false;

  HarnessViewModel get vm => widget.viewModel;
  Strings get s => vm.strings;

  @override
  void dispose() {
    _endpoint.dispose();
    _code.dispose();
    _deviceName.dispose();
    _configText.dispose();
    super.dispose();
  }

  void _seedOnce() {
    if (_seeded) {
      return;
    }
    _seeded = true;
    if (_endpoint.text.isEmpty) {
      _endpoint.text = vm.state.endpointDraft;
    }
    if (_deviceName.text.isEmpty) {
      _deviceName.text = _defaultDeviceName();
    }
  }

  String _defaultDeviceName() {
    final name = vm.deps.platform.deviceName();
    return name.isEmpty ? 'iPhone' : name;
  }

  @override
  Widget build(BuildContext context) {
    _seedOnce();
    return AnimatedBuilder(
      animation: vm,
      builder: (BuildContext context, _) {
        final state = vm.state;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                if (state.error != null)
                  ErrorBar(message: state.error!, onDismiss: vm.clearError),
                if (state.notice != null)
                  NoticeBar(message: state.notice!, onDismiss: vm.clearNotice),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const BrandMark(size: 46),
                          const Spacer(),
                          _languageButton(context, state),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        s.get('connect_title'),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        s.get('connect_subtitle'),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 22),
                      if (state.restoring || state.connecting) _connectingBanner(state),
                      _savedComputers(context, state),
                      const SizedBox(height: 16),
                      _importPanel(context),
                      const SizedBox(height: 10),
                      _pairingPanel(context),
                      const SizedBox(height: 22),
                      _footer(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _languageButton(BuildContext context, HarnessState state) {
    final label = s.isEnglish ? '中文 ›' : 'English ›';
    return TextButton(
      onPressed: () {
        final next = s.isEnglish ? 'zh-CN' : 'en';
        vm.setLanguage(next);
        setState(() {});
      },
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _connectingBanner(HarnessState state) {
    final scheme = Theme.of(context).colorScheme;
    final probing = state.endpointProbes.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.connecting ? s.get('probing') : s.get('loading_saved_computers'),
              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
            ),
          ),
          if (probing > 0)
            Text('$probing', style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12)),
        ],
      ),
    );
  }

  // ————————————————— 已保存的电脑 —————————————————

  Widget _savedComputers(BuildContext context, HarnessState state) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            s.get('saved_computers'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        if (state.hosts.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              state.restoring ? s.get('loading_saved_computers') : s.get('no_hosts_yet'),
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (final host in state.hosts) _hostCard(context, host, state),
      ],
    );
  }

  Widget _hostCard(BuildContext context, Host host, HarnessState state) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = host.id == state.activeHostId && state.connected;
    final hostProbes = <String, EndpointProbe>{
      for (final probe in state.endpointProbes) probe.endpointId: probe,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'PC',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        host.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: <Widget>[
                          Text(
                            s.format('endpoint_count', <String, String>{
                              'count': '${host.endpoints.length}',
                            }),
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                          if (isActive) ...<Widget>[
                            const SizedBox(width: 8),
                            StatusLabel(label: s.get('connected'), active: true),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (String value) async {
                    if (value == 'delete') {
                      final ok = await confirmDialog(
                        context,
                        title: s.get('forget_host'),
                        message: s.get('delete_confirm'),
                        confirmLabel: s.get('delete'),
                        cancelLabel: s.get('cancel'),
                      );
                      if (ok) {
                        await vm.removeHost(host.id);
                      }
                    } else if (value == 'rename') {
                      final name = await textInputDialog(
                        context,
                        title: s.get('rename'),
                        initialValue: host.displayName,
                      );
                      if (name != null && name.trim().isNotEmpty) {
                        await vm.renameHost(host.id, name);
                      }
                    } else if (value == 'add-endpoint') {
                      final address = await textInputDialog(
                        context,
                        title: s.get('endpoint_label'),
                        hint: s.get('endpoint_hint'),
                      );
                      if (address != null && address.trim().isNotEmpty) {
                        await vm.addEndpoint(host.id, address.trim(), address.trim());
                      }
                    }
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'rename', child: Text(s.get('rename'))),
                    PopupMenuItem<String>(value: 'add-endpoint', child: Text(s.get('endpoint_label'))),
                    PopupMenuItem<String>(value: 'delete', child: Text(s.get('forget_host'))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final endpoint in host.endpoints)
              _endpointRow(context, host, endpoint, hostProbes[endpoint.id]),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: state.busy || state.connecting ? null : () => vm.connectHost(host.id),
                  child: Text(s.get('connect_this_host')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _endpointRow(BuildContext context, Host host, Endpoint endpoint, EndpointProbe? probe) {
    final scheme = Theme.of(context).colorScheme;
    final latency = probe?.ok == true && probe?.latencyMs != null ? '${probe!.latencyMs} ms' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              endpointKindLabel(endpoint.kind),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              endpoint.baseUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          if (latency != null)
            Text(latency, style: const TextStyle(fontSize: 11, color: Color(0xFF2E9E5B))),
          if (probe != null && !probe.ok)
            Text(
              probe.error ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: scheme.error),
            ),
        ],
      ),
    );
  }

  // ————————————————— 导入配置 —————————————————

  Widget _importPanel(BuildContext context) {
    return _panel(
      title: s.get('import_config'),
      icon: '📥',
      expanded: _importExpanded,
      onToggle: () => setState(() {
        _importExpanded = !_importExpanded;
        if (_importExpanded) {
          _pairingExpanded = false;
        }
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _configText,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(hintText: s.get('import_config_hint')),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    setState(() => _configText.text = data!.text!);
                  }
                },
                icon: const Icon(Icons.content_paste, size: 18),
                label: Text(s.get('import_config')),
              ),
              const Spacer(),
              FilledButton(
                onPressed: vm.state.busy
                    ? null
                    : () async {
                        await vm.importConfiguration(_configText.text);
                        if (vm.state.error == null && mounted) {
                          _configText.clear();
                        }
                      },
                child: Text(s.get('import')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ————————————————— 配对码 —————————————————

  Widget _pairingPanel(BuildContext context) {
    return _panel(
      title: s.get('manual_pairing'),
      icon: '🔗',
      expanded: _pairingExpanded,
      onToggle: () => setState(() {
        _pairingExpanded = !_pairingExpanded;
        if (_pairingExpanded) {
          _importExpanded = false;
        }
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _endpoint,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: s.get('endpoint_label'),
              hintText: s.get('endpoint_hint'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: s.get('pairing_code_label'),
              hintText: s.get('pairing_code_hint'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _deviceName,
            decoration: InputDecoration(labelText: s.get('device_name_label')),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              OutlinedButton(
                onPressed: vm.state.busy ? null : () => vm.testConnection(_endpoint.text),
                child: Text(s.get('test_connection')),
              ),
              const SizedBox(width: 8),
              if (vm.state.healthOk)
                StatusLabel(label: s.get('connection_ok'), active: true),
              const Spacer(),
              FilledButton(
                onPressed: vm.state.busy
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus();
                        await vm.pair(
                          endpoint: _endpoint.text,
                          code: _code.text,
                          deviceName: _deviceName.text,
                        );
                      },
                child: Text(s.get('pair')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel({
    required String title,
    required String icon,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: <Widget>[
                  Text(icon, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: child,
            ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      s.get('settings_privacy'),
      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
    );
  }
}
