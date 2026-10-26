/// 全屏图片查看页 —— 取代原先的 `Dialog`。
///
/// 真机反馈：`Dialog` 里的图片一放大，关闭与保存按钮既没有、也够不着。
/// 全屏页面把三件事固定住：
/// 1. 左上角永远有**关闭**按钮（`Icons.close`，`maybePop`）；
/// 2. 图片在 `Expanded` 里 `InteractiveViewer`（双指缩放、拖动）；
/// 3. 底部固定操作条：保存到相册 / 存到文件（任一未注入则不显示该项）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';

class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({
    super.key,
    required this.name,
    required this.bytes,
    required this.strings,
    this.onSaveToAlbum,
    this.onExportImage,
  });

  final String name;
  final List<int> bytes;
  final Strings strings;
  final Future<void> Function(String name, List<int> bytes)? onSaveToAlbum;
  final Future<void> Function(String name, List<int> bytes)? onExportImage;

  @override
  Widget build(BuildContext context) {
    final hasActions = onSaveToAlbum != null || onExportImage != null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: strings.get('close'),
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
      ),
      body: SizedBox.expand(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 6,
          child: Center(
            child: Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
      bottomNavigationBar: hasActions
          ? SafeArea(
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    if (onSaveToAlbum != null)
                      TextButton.icon(
                        onPressed: () => onSaveToAlbum!(name, bytes),
                        icon: const Icon(Icons.photo_library_outlined, size: 18, color: Colors.white),
                        label: Text(strings.get('save_to_album'),
                            style: const TextStyle(color: Colors.white)),
                      ),
                    if (onExportImage != null)
                      TextButton.icon(
                        onPressed: () => onExportImage!(name, bytes),
                        icon: const Icon(Icons.ios_share, size: 18, color: Colors.white),
                        label: Text(strings.get('save_to_files'),
                            style: const TextStyle(color: Colors.white)),
                      ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
