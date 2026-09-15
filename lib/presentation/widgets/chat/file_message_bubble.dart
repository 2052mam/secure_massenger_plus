import 'package:flutter/material.dart';
import '../../../data/models/message_model.dart';
import '../../../data/services/media_download_service.dart';

class FileMessageBubble extends StatefulWidget {
  final MessageModel message;
  final String mediaUrl;
  final String? token;
  final bool isMine;
  final Color foregroundColor;

  const FileMessageBubble({
    super.key,
    required this.message,
    required this.mediaUrl,
    this.token,
    required this.isMine,
    required this.foregroundColor,
  });

  @override
  State<FileMessageBubble> createState() => _FileMessageBubbleState();
}

class _FileMessageBubbleState extends State<FileMessageBubble> {
  bool _downloading = false;
  double _progress = 0.0;
  String? _downloadedPath;

  IconData _getFileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return Icons.folder_zip;
    if (['doc', 'docx', 'txt'].contains(ext)) return Icons.description;
    if (['xls', 'xlsx'].contains(ext)) return Icons.table_chart;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow;
    if (['apk'].contains(ext)) return Icons.android;
    if (['mp3', 'wav', 'ogg'].contains(ext)) return Icons.audio_file;
    if (['mp4', 'avi', 'mkv'].contains(ext)) return Icons.video_file;
    return Icons.insert_drive_file;
  }

  Future<void> _startDownload() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0.0;
    });

    final fileName = widget.message.originalName ??
        widget.message.content ??
        'file_${widget.message.id}';

    try {
      final path = await MediaDownloadService.downloadMedia(
        mediaUrl: widget.mediaUrl,
        fileName: fileName,
        token: widget.token,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloading = false;
          _downloadedPath = path;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فایل در دستگاه ذخیره شد: $fileName'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در دانلود فایل: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.message.originalName ??
        (widget.message.content?.isNotEmpty == true
            ? widget.message.content!
            : 'فایل ضمیمه');
    final fileSizeText = widget.message.fileSize != null
        ? MediaDownloadService.formatBytes(widget.message.fileSize!)
        : '';
    final fg = widget.foregroundColor;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: widget.isMine
            ? Colors.white.withValues(alpha: 0.15)
            : Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: widget.isMine
                  ? Colors.white24
                  : Theme.of(context).primaryColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getFileIcon(fileName),
              color: fg,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (fileSizeText.isNotEmpty || _downloadedPath != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _downloadedPath != null
                        ? 'ذخیره شده ($fileSizeText)'
                        : fileSizeText,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _downloading ? null : _startDownload,
            icon: _downloading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      strokeWidth: 2.5,
                      color: fg,
                    ),
                  )
                : Icon(
                    _downloadedPath != null
                        ? Icons.check_circle_outline
                        : Icons.download_rounded,
                    color: fg,
                    size: 26,
                  ),
            tooltip: 'دانلود فایل',
          ),
        ],
      ),
    );
  }
}
