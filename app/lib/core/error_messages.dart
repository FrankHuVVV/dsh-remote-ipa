/// 错误码 → 人话 —— 移植自鸿蒙版 `core/ErrorMessages.ts` 的取值口径。
///
/// 规矩：**认不出的错误码原样带出**，不硬套一句「未知错误」。
/// 排查时「这个码到底是什么」正是用户要看的；把它翻成笼统文案等于把线索擦掉。
library;

import 'dart:async';
import 'dart:io';

import '../l10n/strings.dart';
import 'models.dart';

/// 把任意异常翻成一句可直接展示的话。
String describeError(Object error, Strings s) {
  if (error is DshApiException) {
    return _apiErrorText(error, s);
  }
  if (error is TimeoutException) {
    return s.get('network_error').replaceAll('{reason}', 'timeout');
  }
  if (error is SocketException) {
    return s.get('network_error').replaceAll('{reason}', error.osError?.message ?? 'socket');
  }
  if (error is StateError) {
    return error.message;
  }
  if (error is FormatException) {
    return error.message;
  }
  return error.toString().replaceFirst(RegExp(r'^Exception: '), '');
}

String _apiErrorText(DshApiException error, Strings s) {
  switch (error.code) {
    case 'UNAUTHORIZED':
    case 'AUTH_REQUIRED':
    case 'TOKEN_INVALID':
      return s.get('unauthorized');
    case 'FORBIDDEN':
    case 'SCOPE_MISSING':
      return s.get('forbidden');
    case 'ROUTE_NOT_FOUND':
      return s.get('route_not_found');
    case 'RATE_LIMITED':
      return s.get('rate_limited');
    case 'QUESTION_REPLY_QUEUED':
      return s.get('question_reply_queued');
    case 'QUESTION_NOT_PENDING':
      return s.get('question_not_pending');
    case 'AGENT_PRESET_LOCKED':
    case 'DSH_AGENT_PRESET_LOCKED':
      return s.get('agent_preset_locked');
    case 'ETAG_MISMATCH':
    case 'PRECONDITION_FAILED':
      return s.get('etag_conflict');
    case 'PATH_OUTSIDE_ROOTS':
    case 'PATH_NOT_ABSOLUTE':
    case 'PATH_NOT_FILE':
    case 'PATH_NOT_FOUND':
      return s.get('unknown_error').replaceAll('{reason}', error.code);
    default:
      if (error.code == 'HTTP_ERROR' && error.status == 401) {
        return s.get('unauthorized');
      }
      if (error.code == 'HTTP_ERROR' && error.status == 403) {
        return s.get('forbidden');
      }
      if (error.message.isNotEmpty) {
        return error.message;
      }
      return 'HTTP ${error.status} ${error.code}';
  }
}

/// 服务端错误体里的 `message` 通常已是人话；这里只在没有码时兜底。
String apiMessageOrCode(DshApiException error) =>
    error.message.isNotEmpty ? error.message : error.code;
