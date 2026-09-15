import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../data/services/media_download_service.dart';
import '../../widgets/media/media_labels.dart';
import '../../widgets/media/photo_canvas.dart';

class PhotoViewerScreen extends StatefulWidget {
  final String url;
  final String? token;
  final String? caption;

  const PhotoViewerScreen({
    super.key,
    required this.url,
    this.token,
    this.caption,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final ImageProvider _image = CachedNetworkImageProvider(
    widget.url,
    headers: widget.token == null
        ? null
        : {'Authorization': 'Bearer ${widget.token}'},
  );
  bool _showChrome = true;
  bool _downloading = false;

  Future<void> _downloadPhoto() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final filename = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = await MediaDownloadService.downloadMedia(
        mediaUrl: widget.url,
        fileName: filename,
        token: widget.token,
      );
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('عکس با موفقیت ذخیره شد ($filename)')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره عکس: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = MediaLabels.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PhotoCanvas(
            image: _image,
            onTap: () => setState(() => _showChrome = !_showChrome),
          ),
          if (_showChrome)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: labels.close,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      Text(
                        labels.photo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'دانلود عکس',
                        onPressed: _downloading ? null : _downloadPhoto,
                        icon: _downloading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.download_rounded,
                                color: Colors.white,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_showChrome && widget.caption?.isNotEmpty == true)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ColoredBox(
                color: Colors.black54,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.all(16),
                  child: Text(
                    widget.caption!,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
