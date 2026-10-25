/// 文件导出 —— 把字节写进 App 的 `Documents/Exports/`，再交给系统「文件」App。
///
/// 为什么不用分享面板：多引一个原生插件就多一处编译风险，而「导出」的真实需求是
/// **把文件拿出来**。开启 `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`
/// 后，用户在「文件 → 我的 iPhone → DSH 伴侣 → Exports」里就能看到并拷走。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 把 [bytes] 写进 Documents/Exports，返回落盘的绝对路径。
///
/// 同名文件会被覆盖：导出是用户显式动作，自动改名（`a 2.txt`）反而让人找不到刚导出的那份。
Future<String> exportToDocuments(String name, List<int> bytes) async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory('${documents.path}/Exports');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final safeName = name.replaceAll(RegExp(r'[/\\]'), '_');
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
