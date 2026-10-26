/// 聊天页的洞察入口（待办 / 交付物 / 统计 / 轨迹），同为 `chat_screen.dart` 的 part 扩展。
part of 'chat_screen.dart';

extension ChatInsightsActions on _ChatScreenState {
  // ————————————————— 洞察 / 统计 / 轨迹 —————————————————

  void _showInsights(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SessionInsightsSheet(
        state: vm.state,
        strings: s,
        onOpenDeliverable: (String path) {
          Navigator.of(sheetContext).pop();
          unawaited(_openDeliverable(path));
        },
        onOpenStats: () => _showStats(context),
        onOpenTrajectory: () => _openTrajectory(context),
      ),
    );
  }

  void _showStats(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: SessionStatsView(stats: sessionStatsOf(vm.state.history), strings: s),
      ),
    );
  }

  void _openTrajectory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => TrajectoryScreen(history: vm.state.history, strings: s),
      ),
    );
  }

  Future<void> _openDeliverable(String path) async {
    final opened = await vm.openAbsolutePath(path);
    if (!opened || !mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => FileViewerScreen(viewModel: vm),
      ),
    );
  }
}
