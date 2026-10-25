/// 线上模型 —— **文件与目录**。
library;

import 'json.dart';

/// 目录里的一条。
class FileEntry {
  FileEntry({
    this.name = '',
    this.path = '',
    this.kind = '',
    this.size = 0,
    this.modifiedAt = 0,
    this.writable = false,
  });

  String name;
  String path;
  String kind;
  int size;
  int modifiedAt;
  bool writable;

  bool isDirectory() => kind == 'directory';

  FileEntry withSize(int size) => FileEntry(
        name: name,
        path: path,
        kind: kind,
        size: size,
        modifiedAt: modifiedAt,
        writable: writable,
      );

  factory FileEntry.fromJson(Object? map) => FileEntry(
        name: stringOrNull(map, 'name') ?? '',
        path: stringOrNull(map, 'path') ?? '',
        kind: stringOrNull(map, 'kind') ?? '',
        size: intOrNull(map, 'size') ?? 0,
        modifiedAt: intOrNull(map, 'modifiedAt') ?? 0,
        writable: boolOrNull(map, 'writable') ?? false,
      );
}

/// 一页目录。
class DirectoryPage {
  DirectoryPage({this.path = '', this.entries = const <FileEntry>[], this.nextCursor});

  String path;
  List<FileEntry> entries;
  String? nextCursor;

  DirectoryPage withMerged(List<FileEntry> entries, String? nextCursor) =>
      DirectoryPage(path: path, entries: entries, nextCursor: nextCursor);

  factory DirectoryPage.fromJson(Object? map) => DirectoryPage(
        path: stringOrNull(map, 'path') ?? '',
        entries: [for (final e in objArr(map, 'entries')) FileEntry.fromJson(e)],
        nextCursor: stringOrNull(map, 'nextCursor'),
      );
}

/// `GET roots/resolve?path=` 的响应：服务器绝对路径 → `rootId` + 相对路径。
class ResolvedPath {
  ResolvedPath({
    this.rootId = '',
    this.path = '',
    this.kind = '',
    this.size,
    this.modifiedAt = 0,
    this.contentType,
  });

  String rootId;
  String path;
  String kind;
  int? size;
  int modifiedAt;
  String? contentType;

  factory ResolvedPath.fromJson(Object? map) => ResolvedPath(
        rootId: stringOrNull(map, 'rootId') ?? '',
        path: stringOrNull(map, 'path') ?? '',
        kind: stringOrNull(map, 'kind') ?? '',
        size: intOrNull(map, 'size'),
        modifiedAt: intOrNull(map, 'modifiedAt') ?? 0,
        contentType: stringOrNull(map, 'contentType'),
      );
}

/// 回收站条目。
class TrashEntry {
  TrashEntry({
    this.id = '',
    this.rootId = '',
    this.path = '',
    this.kind = '',
    this.size = 0,
    this.createdAt = 0,
    this.status = '',
  });

  String id;
  String rootId;
  String path;
  String kind;
  int size;
  int createdAt;
  String status;

  factory TrashEntry.fromJson(Object? map) => TrashEntry(
        id: stringOrNull(map, 'id') ?? '',
        rootId: stringOrNull(map, 'rootId') ?? '',
        path: stringOrNull(map, 'path') ?? '',
        kind: stringOrNull(map, 'kind') ?? '',
        size: intOrNull(map, 'size') ?? 0,
        createdAt: intOrNull(map, 'createdAt') ?? 0,
        status: stringOrNull(map, 'status') ?? '',
      );
}

/// 文件内容 + 版本标识（字节流 + ETag / Content-Type 头）。
class FileContent {
  FileContent({required this.bytes, this.etag = '', this.contentType});

  final List<int> bytes;
  final String etag;
  final String? contentType;
}
