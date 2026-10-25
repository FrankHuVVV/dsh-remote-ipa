/// 线上模型 —— **配置域**：权限选择、模型选择、供应商设置、插件清单。
library;

import 'json.dart';
import 'models_wire.dart';

class PermissionOption {
  PermissionOption({this.value = '', this.name = '', this.description});

  String value;
  String name;
  String? description;

  factory PermissionOption.fromJson(Object? map) => PermissionOption(
        value: stringOrNull(map, 'value') ?? '',
        name: stringOrNull(map, 'name') ?? '',
        description: stringOrNull(map, 'description'),
      );
}

class PermissionSelect {
  PermissionSelect({this.options = const <PermissionOption>[], this.currentValue = ''});

  List<PermissionOption> options;
  String currentValue;

  factory PermissionSelect.fromJson(Object? map) => PermissionSelect(
        options: [for (final o in objArr(map, 'options')) PermissionOption.fromJson(o)],
        currentValue: stringOrNull(map, 'currentValue') ?? '',
      );
}

class ModelSelection {
  ModelSelection({this.provider = '', this.model = '', this.reasoningEffort});

  String provider;
  String model;
  String? reasoningEffort;

  Map<String, dynamic> toMap() => WireBuilder()
      .put('provider', provider)
      .put('model', model)
      .put('reasoningEffort', reasoningEffort)
      .buildMap();

  factory ModelSelection.fromJson(Object? map) => ModelSelection(
        provider: stringOrNull(map, 'provider') ?? '',
        model: stringOrNull(map, 'model') ?? '',
        reasoningEffort: stringOrNull(map, 'reasoningEffort'),
      );
}

class ModelReasoningEffort {
  ModelReasoningEffort({this.id = '', this.name = '', this.description});

  String id;
  String name;
  String? description;

  factory ModelReasoningEffort.fromJson(Object? map) => ModelReasoningEffort(
        id: stringOrNull(map, 'id') ?? '',
        name: stringOrNull(map, 'name') ?? '',
        description: stringOrNull(map, 'description'),
      );
}

class ModelReasoning {
  ModelReasoning({this.efforts = const <ModelReasoningEffort>[], this.defaultEffort});

  List<ModelReasoningEffort> efforts;
  String? defaultEffort;

  factory ModelReasoning.fromJson(Object? map) => ModelReasoning(
        efforts: [for (final e in objArr(map, 'efforts')) ModelReasoningEffort.fromJson(e)],
        defaultEffort: stringOrNull(map, 'defaultEffort'),
      );
}

class ModelView {
  ModelView({
    this.id = '',
    this.name = '',
    this.description,
    this.contextWindow,
    this.maxTokens,
    this.reasoning,
  });

  String id;
  String name;
  String? description;
  int? contextWindow;
  int? maxTokens;
  ModelReasoning? reasoning;

  factory ModelView.fromJson(Object? map) {
    final reasoning = obj(map, 'reasoning');
    return ModelView(
      id: stringOrNull(map, 'id') ?? '',
      name: stringOrNull(map, 'name') ?? '',
      description: stringOrNull(map, 'description'),
      contextWindow: intOrNull(map, 'contextWindow'),
      maxTokens: intOrNull(map, 'maxTokens'),
      reasoning: reasoning == null ? null : ModelReasoning.fromJson(reasoning),
    );
  }
}

class ModelProviderGroup {
  ModelProviderGroup({this.id = '', this.name = '', this.models = const <ModelView>[]});

  String id;
  String name;
  List<ModelView> models;

  factory ModelProviderGroup.fromJson(Object? map) => ModelProviderGroup(
        id: stringOrNull(map, 'id') ?? '',
        name: stringOrNull(map, 'name') ?? '',
        models: [for (final m in objArr(map, 'models')) ModelView.fromJson(m)],
      );
}

class ModelFailure {
  ModelFailure({this.provider = '', this.message = ''});

  String provider;
  String message;

  factory ModelFailure.fromJson(Object? map) => ModelFailure(
        provider: stringOrNull(map, 'provider') ?? '',
        message: stringOrNull(map, 'message') ?? '',
      );
}

class SessionModels {
  SessionModels({
    ModelSelection? current,
    this.routable = false,
    this.groups = const <ModelProviderGroup>[],
    this.failures = const <ModelFailure>[],
  }) : current = current ?? ModelSelection();

  ModelSelection current;
  bool routable;
  List<ModelProviderGroup> groups;
  List<ModelFailure> failures;

  factory SessionModels.fromJson(Object? map) => SessionModels(
        current: ModelSelection.fromJson(obj(map, 'current')),
        routable: boolOrNull(map, 'routable') ?? false,
        groups: [for (final g in objArr(map, 'groups')) ModelProviderGroup.fromJson(g)],
        failures: [for (final f in objArr(map, 'failures')) ModelFailure.fromJson(f)],
      );
}

class ProviderModel {
  ProviderModel({this.id = '', this.name, this.contextWindow, this.maxTokens});

  String id;
  String? name;
  int? contextWindow;
  int? maxTokens;

  Map<String, dynamic> toMap() => WireBuilder()
      .put('id', id)
      .put('name', name)
      .put('contextWindow', contextWindow)
      .put('maxTokens', maxTokens)
      .buildMap();

  factory ProviderModel.fromJson(Object? map) => ProviderModel(
        id: stringOrNull(map, 'id') ?? '',
        name: stringOrNull(map, 'name'),
        contextWindow: intOrNull(map, 'contextWindow'),
        maxTokens: intOrNull(map, 'maxTokens'),
      );
}

class ProviderConfig {
  ProviderConfig({
    this.baseURL,
    this.api,
    this.displayName,
    this.thinking,
    this.reasoningEffort,
    this.models = const <ProviderModel>[],
    this.modelsInherited = false,
  });

  String? baseURL;
  String? api;
  String? displayName;
  String? thinking;
  String? reasoningEffort;
  List<ProviderModel> models;
  bool modelsInherited;

  factory ProviderConfig.fromJson(Object? map) => ProviderConfig(
        baseURL: stringOrNull(map, 'baseURL'),
        api: stringOrNull(map, 'api'),
        displayName: stringOrNull(map, 'displayName'),
        thinking: stringOrNull(map, 'thinking'),
        reasoningEffort: stringOrNull(map, 'reasoningEffort'),
        models: [for (final m in objArr(map, 'models')) ProviderModel.fromJson(m)],
        modelsInherited: boolOrNull(map, 'modelsInherited') ?? false,
      );
}

class CredentialState {
  CredentialState({this.ref = '', this.configured = false, this.source, this.writable = false});

  String ref;
  bool configured;
  String? source;
  bool writable;

  factory CredentialState.fromJson(Object? map) => CredentialState(
        ref: stringOrNull(map, 'ref') ?? '',
        configured: boolOrNull(map, 'configured') ?? false,
        source: stringOrNull(map, 'source'),
        writable: boolOrNull(map, 'writable') ?? false,
      );
}

class ProviderView {
  ProviderView({
    this.id = '',
    this.displayName = '',
    this.active = false,
    this.declared,
    this.configurable = false,
    this.configured = false,
    this.removable = false,
    CredentialState? credential,
    ProviderConfig? config,
  })  : credential = credential ?? CredentialState(),
        config = config ?? ProviderConfig();

  String id;
  String displayName;
  bool active;
  bool? declared;
  bool configurable;
  bool configured;
  bool removable;
  CredentialState credential;
  ProviderConfig config;

  factory ProviderView.fromJson(Object? map) => ProviderView(
        id: stringOrNull(map, 'id') ?? '',
        displayName: stringOrNull(map, 'displayName') ?? '',
        active: boolOrNull(map, 'active') ?? false,
        declared: boolOrNull(map, 'declared'),
        configurable: boolOrNull(map, 'configurable') ?? false,
        configured: boolOrNull(map, 'configured') ?? false,
        removable: boolOrNull(map, 'removable') ?? false,
        credential: CredentialState.fromJson(obj(map, 'credential')),
        config: ProviderConfig.fromJson(obj(map, 'config')),
      );
}

class CustomProviderCapability {
  CustomProviderCapability({this.available = false, this.protocols = const <String>[], this.revision});

  bool available;
  List<String> protocols;
  int? revision;

  factory CustomProviderCapability.fromJson(Object? map) => CustomProviderCapability(
        available: boolOrNull(map, 'available') ?? false,
        protocols: stringArr(map, 'protocols'),
        revision: intOrNull(map, 'revision'),
      );
}

class ProviderSettings {
  ProviderSettings({
    this.writable = false,
    this.revisionByNamespace = const <String, int>{},
    CustomProviderCapability? customProvider,
    this.providers = const <ProviderView>[],
  }) : customProvider = customProvider ?? CustomProviderCapability();

  bool writable;
  Map<String, int> revisionByNamespace;
  CustomProviderCapability customProvider;
  List<ProviderView> providers;

  int? revision(String namespace) => revisionByNamespace[namespace];

  factory ProviderSettings.fromJson(Object? map) {
    final revisions = <String, int>{};
    final raw = obj(map, 'revisionByNamespace');
    if (raw != null) {
      raw.forEach((key, value) {
        if (value is num) {
          revisions[key] = value.toInt();
        }
      });
    }
    return ProviderSettings(
      writable: boolOrNull(map, 'writable') ?? false,
      revisionByNamespace: revisions,
      customProvider: CustomProviderCapability.fromJson(obj(map, 'customProvider')),
      providers: [for (final p in objArr(map, 'providers')) ProviderView.fromJson(p)],
    );
  }
}

/// `PATCH settings/providers/{id}` 请求体：未指定的字段**不出现**（不是发 null）。
class ProviderPatch {
  ProviderPatch({
    this.displayName,
    this.baseURL,
    this.api,
    this.apiKey,
    this.thinking,
    this.reasoningEffort,
    this.models,
    this.expectedRevision,
  });

  String? displayName;
  String? baseURL;
  String? api;
  String? apiKey;
  String? thinking;
  String? reasoningEffort;
  List<ProviderModel>? models;
  int? expectedRevision;

  String toJsonString() {
    final builder = WireBuilder()
      ..put('displayName', displayName)
      ..put('baseURL', baseURL)
      ..put('api', api)
      ..put('apiKey', apiKey)
      ..put('thinking', thinking)
      ..put('reasoningEffort', reasoningEffort)
      ..put('expectedRevision', expectedRevision);
    if (models != null) {
      builder.put('models', [for (final m in models!) m.toMap()]);
    }
    return builder.build();
  }
}

class CustomProviderCreate {
  CustomProviderCreate({
    this.id = '',
    this.displayName,
    this.baseURL = '',
    this.api = '',
    this.apiKey,
    this.models = const <ProviderModel>[],
    this.expectedRevision,
  });

  String id;
  String? displayName;
  String baseURL;
  String api;
  String? apiKey;
  List<ProviderModel> models;
  int? expectedRevision;

  String toJsonString() => WireBuilder()
      .put('id', id)
      .put('displayName', displayName)
      .put('baseURL', baseURL)
      .put('api', api)
      .put('apiKey', apiKey)
      .put('expectedRevision', expectedRevision)
      .put('models', [for (final m in models) m.toMap()])
      .build();
}

// ---------------------------------------------------------------------------
// 插件
// ---------------------------------------------------------------------------

/// 已安装插件清单里的一条。字段全带默认值（缺键不能让整页打挂）。
class PluginEntry {
  PluginEntry({
    this.name = '',
    this.declared,
    this.installed,
    this.loaded = false,
    this.official = false,
    this.state = '',
    this.description,
    this.homepage,
    this.updateAvailable,
    this.latestVersion,
    this.toggleable = false,
  });

  String name;
  String? declared;
  String? installed;
  bool loaded;
  bool official;
  String state;
  String? description;
  String? homepage;

  /// 三态：`null` = 没查 / 查不到，与 `false`（已是最新）不是一回事。
  bool? updateAvailable;
  String? latestVersion;
  bool toggleable;

  factory PluginEntry.fromJson(Object? map) => PluginEntry(
        name: stringOrNull(map, 'name') ?? '',
        declared: stringOrNull(map, 'declared'),
        installed: stringOrNull(map, 'installed'),
        loaded: boolOrNull(map, 'loaded') ?? false,
        official: boolOrNull(map, 'official') ?? false,
        state: stringOrNull(map, 'state') ?? '',
        description: stringOrNull(map, 'description'),
        homepage: stringOrNull(map, 'homepage'),
        updateAvailable: boolOrNull(map, 'updateAvailable'),
        latestVersion: stringOrNull(map, 'latestVersion'),
        toggleable: boolOrNull(map, 'toggleable') ?? false,
      );
}

class PluginToggleResult {
  PluginToggleResult({
    this.name = '',
    this.loaded = false,
    this.backupName = '',
    this.bundleCount = 0,
    this.restartRequired = true,
  });

  String name;
  bool loaded;
  String backupName;
  int bundleCount;

  /// 恒为 true：清单只在 DSH 启动时读一次。界面必须明说，否则用户以为开关坏了。
  bool restartRequired;

  factory PluginToggleResult.fromJson(Object? map) => PluginToggleResult(
        name: stringOrNull(map, 'name') ?? '',
        loaded: boolOrNull(map, 'loaded') ?? false,
        backupName: stringOrNull(map, 'backupName') ?? '',
        bundleCount: intOrNull(map, 'bundleCount') ?? 0,
        restartRequired: boolOrNull(map, 'restartRequired') ?? true,
      );
}

class PluginInventory {
  PluginInventory({
    this.profile,
    this.profilePath,
    this.available = false,
    this.reason,
    this.loadedCount = 0,
    this.problemCount = 0,
    this.items = const <PluginEntry>[],
  });

  String? profile;
  String? profilePath;
  bool available;
  String? reason;
  int loadedCount;
  int problemCount;
  List<PluginEntry> items;

  factory PluginInventory.fromJson(Object? map) => PluginInventory(
        profile: stringOrNull(map, 'profile'),
        profilePath: stringOrNull(map, 'profilePath'),
        available: boolOrNull(map, 'available') ?? false,
        reason: stringOrNull(map, 'reason'),
        loadedCount: intOrNull(map, 'loadedCount') ?? 0,
        problemCount: intOrNull(map, 'problemCount') ?? 0,
        items: [for (final i in objArr(map, 'items')) PluginEntry.fromJson(i)],
      );
}
