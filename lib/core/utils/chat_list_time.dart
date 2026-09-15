import 'package:intl/intl.dart';

/// Telegram-style compact timestamps, based on local calendar dates, not elapsed
/// hours (which are misleading across timezones and daylight-saving changes).
String formatChatListTime(
  DateTime value, {
  DateTime? now,
  String locale = 'en',
}) {
  final local = value.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    return DateFormat('HH:mm', locale).format(local);
  }
  return DateFormat(
    local.year == today.year ? 'MMM d' : 'yyyy/MM/dd',
    locale,
  ).format(local);
}
