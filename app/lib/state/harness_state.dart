/// 界面主状态 —— 移植自鸿蒙版 `core/HarnessTypes.ts`（字段按 iOS 侧实际用到的裁剪）。
///
/// 这是**普通可变对象**：ViewModel 就地改字段再 `notifyListeners()`。
/// 字段默认值与鸿蒙版逐项对齐，改之前先读那边的注释（每一格都对应一次真机踩坑）。
library;

import '../core/chat_presentation.dart';
import '../core/connection_models.dart';
import '../core/models.dart';
import '../core/small_parts.dart';

/// 文本编辑的内存闸：2 MiB（与 Kotlin `MAX_EDIT_BYTES` 一致）。
const int maxEditBytes = 2 * 1024 * 1024;

/// 面板只读预览的字符上限。
const int previewChars = 20000;

/// 「文件」页正在编辑的那一份文档。
class OpenDocument {
  OpenDocument({
    required this.entry,
    this.text,
    this.etag = '',
    this.contentType,
    this.bytes,
    this.skippedForSize = false,
  });

  final FileEntry entry;
  String? text;
  String etag;
  String? contentType;

  /// 图片 / PDF 这类要交给解码器的才留原始字节。
  final List<int>? bytes;

  /// 预览是被**主动跳过**的（文件超过上限），而不是还没加载。
  final bool skippedForSize;

  OpenDocument withText(String text) => OpenDocument(
        entry: entry,
        text: text,
        etag: etag,
        contentType: contentType,
        bytes: bytes,
        skippedForSize: skippedForSize,
      );

  OpenDocument withEtag(String etag) => OpenDocument(
        entry: entry,
        text: text,
        etag: etag,
        contentType: contentType,
        bytes: bytes,
        skippedForSize: skippedForSize,
      );
}

/// 待发附件。
class PendingAttachment {
  PendingAttachment({
    required this.id,
    required this.part,
    required this.name,
    this.sizeBytes = 0,
    this.imageBytes,
  });

  final String id;
  final PromptPart part;
  final String name;
  final int sizeBytes;
  final List<int>? imageBytes;
}

/// 审批面板四态。
enum ApprovalUiKind { none, loading, pending, deciding }

class HarnessState {
  // ——— 连接 ———
  bool restoring = true;
  bool busy = false;
  String endpointDraft = 'http://192.168.1.20:3090';
  bool healthOk = false;
  bool connected = false;
  String endpoint = '';
  List<Host> hosts = <Host>[];
  String? activeHostId;
  String? activeEndpointId;
  List<EndpointProbe> endpointProbes = <EndpointProbe>[];
  bool connecting = false;
  String? selectedHostId;
  DeviceView? device;
  String? bridgeVersion;

  /// null = 未知（旧服务端不报或清单为空）。**未知 ≠ 缺失**。
  Set<String>? bridgeCapabilities;

  // ——— 会话 ———
  List<RootView> roots = <RootView>[];
  List<ChatSession> sessions = <ChatSession>[];
  List<ChatSession> archivedSessions = <ChatSession>[];
  List<ChatWorkspace> chatWorkspaces = <ChatWorkspace>[];
  List<AgentPreset> agentPresets = <AgentPreset>[];
  SessionModels? sessionModels;
  PermissionSelect? permissionCatalog;
  List<CommandDescriptor> commands = <CommandDescriptor>[];
  String? selectedSessionId;
  ChatHistory? history;
  LiveChatState? liveChat;
  List<ChatDisplayItem> visibleItems = <ChatDisplayItem>[];
  List<TodoItem> todos = <TodoItem>[];
  List<ChatDeliverable> deliverables = <ChatDeliverable>[];
  ApprovalUiKind approvalKind = ApprovalUiKind.none;
  List<PendingApproval> approvals = <PendingApproval>[];
  PendingApproval? decidingApproval;
  List<PendingQuestionSet> questions = <PendingQuestionSet>[];
  String? answeringCallId;
  Set<String> answeredCallIds = <String>{};

  /// 会话图片缓存：键是 `attachmentId`（交接图是 `handoff:<绝对路径>`）。
  Map<String, List<int>> attachmentImages = <String, List<int>>{};
  Map<String, String> attachmentFailures = <String, String>{};
  Set<String> attachmentLoading = <String>{};

  bool eventsConnected = false;
  int? lastEventSeq;
  int? baselineCursor;

  // ——— 文件 ———
  String? selectedRootId;
  String currentPath = '';
  DirectoryPage? directory;
  OpenDocument? document;
  bool fileLoading = false;
  String? fileError;
  List<TrashEntry> trash = <TrashEntry>[];

  /// 输入框 @ 补全的候选：当前会话工作目录下的条目；null = 还没加载。
  List<FileEntry>? mentionEntries;

  /// @ 补全这次**尝试过但没拿到**（网络失败 / 没有可用工作目录）。
  bool mentionFailed = false;

  // ——— 设置 ———
  ProviderSettings? providerSettings;
  PluginInventory? pluginInventory;
  bool pluginCheckingUpdates = false;
  String? checkedPluginName;
  String? notice;

  /// 有文件正在上传换 `receiptId`（只用于显示进度，不用来禁用发送键）。
  bool attachmentUploading = false;

  // ——— 偏好（镜像，权威在 AppPreferences）———
  String busySendMode = sendModeQueue;
  bool showContext = false;
  double fontScale = 1.0;
  bool fontFollowsSystem = true;
  String themeMode = themeModeSystem;
  String languageTag = 'zh-CN';

  String? error;

  /// 当前会话的模型可路由状态（来自 [sessionModels]）。
  bool get modelRoutable => sessionModels?.routable ?? false;

  /// 当前权限档位（投影里给的那个值）。
  String get permissionValue => permissionCatalog?.currentValue ?? '';

  /// 当前会话 obj。
  ChatSession? get currentSession {
    final id = selectedSessionId;
    if (id == null) {
      return null;
    }
    for (final s in sessions) {
      if (s.id == id) {
        return s;
      }
    }
    return null;
  }
}
