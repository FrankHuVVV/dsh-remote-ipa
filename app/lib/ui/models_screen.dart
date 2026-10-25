/// 模型页 —— 移植自鸿蒙版 `ui/ModelsScreen.ets` 的只读视角。
///
/// 刻意**只读凭据的存在性与来源，不读正文**：`settings/providers` 从不返回 apiKey，
/// 界面也没有任何输入框能把它显示出来。
library;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../l10n/strings.dart';
import '../state/harness_view_model.dart';
import 'widgets.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key, required this.viewModel});

  final HarnessViewModel viewModel;

  Strings get s => viewModel.strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (BuildContext context, _) {
        final state = viewModel.state;
        final settings = state.providerSettings;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.get('models_title')),
            actions: <Widget>[
              IconButton(
                tooltip: s.get('refresh'),
                onPressed: viewModel.refreshProviders,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              if (state.error != null) ErrorBar(message: state.error!, onDismiss: viewModel.clearError),
              Expanded(
                child: settings == null
                    ? EmptyState(text: s.get('loading'))
                    : ListView(
                        children: <Widget>[
                          SectionHeader(
                            title: s.get('providers'),
                            subtitle: settings.writable ? null : s.get('file_read_only'),
                          ),
                          if (settings.providers.isEmpty)
                            EmptyState(text: s.get('no_roots'))
                          else
                            for (final provider in settings.providers) _provider(context, provider),
                          const Divider(height: 24),
                          SectionHeader(title: s.get('permission_presets')),
                          if (state.permissionCatalog == null)
                            EmptyState(text: '—')
                          else
                            for (final option in state.permissionCatalog!.options)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  option.value == state.permissionCatalog!.currentValue
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 18,
                                ),
                                title: Text(option.name, style: const TextStyle(fontSize: 14)),
                                subtitle: option.description == null
                                    ? null
                                    : Text(
                                        option.description!,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                onTap: option.value == state.permissionCatalog!.currentValue
                                    ? null
                                    : () async {
                                        final ok = await confirmDialog(
                                          context,
                                          title: s.get('switch_permission'),
                                          message: option.description ?? option.name,
                                          confirmLabel: s.get('confirm'),
                                          cancelLabel: s.get('cancel'),
                                        );
                                        if (ok) {
                                          await viewModel.selectPermissionPreset(option.value);
                                        }
                                      },
                              ),
                          const SizedBox(height: 30),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _provider(BuildContext context, ProviderView provider) {
    final scheme = Theme.of(context).colorScheme;
    final config = provider.config;
    return InkWell(
      onTap: provider.configurable ? () => _editProvider(context, provider) : null,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  provider.displayName.isEmpty ? provider.id : provider.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (provider.active)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s.get('provider_active'),
                    style: TextStyle(fontSize: 10, color: scheme.onPrimaryContainer),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${provider.credential.configured ? s.get('provider_configured') : s.get('provider_no_credential')}'
            '${config.baseURL == null ? '' : ' · ${config.baseURL}'}',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          if (config.models.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                config.models.map((ProviderModel m) => m.name ?? m.id).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
      ),
    );
  }

  void _editProvider(BuildContext context, ProviderView provider) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _ProviderEditSheet(viewModel: viewModel, provider: provider),
      ),
    );
  }
}

/// 供应商编辑面板：只发用户真的填了的字段。
///
/// **apiKey 永远不回填**（服务端也不返回明文），留空 = 不修改 —— 这一条是刻意设计，
/// 不是遗漏：把已保存的密钥显示在输入框里，等于让它出现在截屏与录屏里。
class _ProviderEditSheet extends StatefulWidget {
  const _ProviderEditSheet({required this.viewModel, required this.provider});

  final HarnessViewModel viewModel;
  final ProviderView provider;

  @override
  State<_ProviderEditSheet> createState() => _ProviderEditSheetState();
}

class _ProviderEditSheetState extends State<_ProviderEditSheet> {
  late final TextEditingController _displayName =
      TextEditingController(text: widget.provider.displayName);
  late final TextEditingController _baseURL =
      TextEditingController(text: widget.provider.config.baseURL ?? '');
  late final TextEditingController _api =
      TextEditingController(text: widget.provider.config.api ?? '');
  final TextEditingController _apiKey = TextEditingController();
  late List<ProviderModel> _models = widget.provider.config.models;
  bool _discovering = false;
  bool _saving = false;

  HarnessViewModel get vm => widget.viewModel;
  Strings get s => vm.strings;

  @override
  void dispose() {
    _displayName.dispose();
    _baseURL.dispose();
    _api.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Text('${s.get('edit_provider')} · ${widget.provider.id}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _displayName,
              decoration: InputDecoration(labelText: s.get('providers')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _baseURL,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(labelText: s.get('base_url')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _api,
              autocorrect: false,
              decoration: InputDecoration(labelText: s.get('api_protocol')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _apiKey,
              autocorrect: false,
              obscureText: true,
              decoration: InputDecoration(
                labelText: s.get('api_key'),
                hintText: s.get('api_key_hint'),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _discovering ? null : _discover,
                  icon: _discovering
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.travel_explore, size: 18),
                  label: Text(s.get('discover_models')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(s.get('save')),
                ),
              ],
            ),
            if (_models.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _models.map((ProviderModel m) => m.name ?? m.id).join(' · '),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _discover() async {
    setState(() => _discovering = true);
    final found = await vm.discoverModels(
      widget.provider.id,
      baseURL: _baseURL.text.trim().isEmpty ? null : _baseURL.text.trim(),
      api: _api.text.trim().isEmpty ? null : _api.text.trim(),
      apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _discovering = false;
      if (found.isNotEmpty) {
        _models = found;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.format('models_found', <String, String>{'count': '${found.length}'})),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await vm.updateProviderConfig(
      widget.provider.id,
      displayName: _displayName.text.trim().isEmpty ? null : _displayName.text.trim(),
      baseURL: _baseURL.text.trim().isEmpty ? null : _baseURL.text.trim(),
      api: _api.text.trim().isEmpty ? null : _api.text.trim(),
      apiKey: _apiKey.text.trim().isEmpty ? null : _apiKey.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop();
    }
  }
}
