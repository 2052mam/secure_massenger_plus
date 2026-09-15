import '../constants/api_constants.dart';

String resolveMediaUrl(String? mediaId, {String? existingUrl}) {
  if (existingUrl != null && existingUrl.isNotEmpty) {
    return Uri.parse(
      '${ApiConstants.baseUrl}/',
    ).resolve(existingUrl).toString();
  }
  if (mediaId == null || mediaId.isEmpty) return '';
  return '${ApiConstants.baseUrl}/media/$mediaId';
}

String formatMediaDuration(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 359999);
  final minutes = (seconds ~/ 60).toString();
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  if (seconds < 3600) return '$minutes:$remainder';
  return '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:$remainder';
}

Duration clampMediaPosition(Duration position, Duration duration) => Duration(
  milliseconds: position.inMilliseconds
      .clamp(0, duration.inMilliseconds < 0 ? 0 : duration.inMilliseconds)
      .toInt(),
);
