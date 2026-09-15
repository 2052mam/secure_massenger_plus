import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/media_utils.dart';
import '../../../data/models/gif_model.dart';
import '../../../data/services/api_service.dart';

/// Telegram-like GIF library — user's OWN saved GIFs only.
///
/// - No online / trending GIFs.
/// - No "make GIF from video".
/// - Users add GIFs they downloaded from the Internet via "Add GIF" (picks a
///   .gif file, uploads it, saves to the library), then tap to send.
class GifPicker extends StatefulWidget {
  final ApiService api;
  final String? token;
  final ValueChanged<GifModel> onGifSelected;
  const GifPicker({super.key, required this.api, this.token, required this.onGifSelected});

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  List<GifModel> _saved = [];
  List<GifModel> _filtered = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.get('/gifs/saved');
      final list = (res['gifs'] as List? ?? [])
          .map((e) => GifModel.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _saved = list;
          _applyFilter();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = List.of(_saved);
    } else {
      _filtered = _saved.where((g) => (g.title ?? '').toLowerCase().contains(q)).toList();
    }
  }

  String _resolveUrl(GifModel g) {
    // Prefer media-based URL (authenticated) so uploaded GIFs render.
    final raw = g.gifUrl ?? g.previewUrl ?? '';
    if (raw.isEmpty && (g.mediaId?.isNotEmpty == true)) {
      return resolveMediaUrl(g.mediaId);
    }
    if (raw.startsWith('http')) return raw;
    if (raw.startsWith('/')) return resolveMediaUrl(null, existingUrl: raw);
    if (raw.isNotEmpty) return raw;
    if (g.mediaId?.isNotEmpty == true) return resolveMediaUrl(g.mediaId);
    return '';
  }

  Future<void> _addGif() async {
    if (_uploading) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gif'],
      withData: false,
    );
    if (result == null || result.files.single.path == null || !mounted) return;
    final path = result.files.single.path!;
    final name = result.files.single.name;
    setState(() => _uploading = true);
    try {
      final upload = await widget.api.uploadFile('/media/upload', File(path));
      final mediaId = upload['id'] as String;
      final title = name.replaceAll(RegExp(r'\.gif$', caseSensitive: false), '');
      final saved = await widget.api.post('/gifs/save', {
        'media_id': mediaId,
        'title': title.isEmpty ? 'GIF' : title,
      });
      final gif = GifModel.fromJson((saved['gif'] ?? saved) as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          _saved.insert(0, gif);
          _applyFilter();
          _uploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('گیف به کتابخانه اضافه شد')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('افزودن گیف ناموفق: $e')));
      }
    }
  }

  Future<void> _unsave(GifModel gif) async {
    try {
      await widget.api.post('/gifs/saved/${gif.id}', {});
      setState(() {
        _saved.removeWhere((g) => g.id == gif.id);
        _applyFilter();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('گیف حذف شد')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _grid() {
    if (_filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gif_box_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                _saved.isEmpty ? 'هنوز گیفی ذخیره نکرده‌اید' : 'نتیجه‌ای یافت نشد',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'گیف‌های دانلودشده از اینترنت را با «افزودن گیف» به کتابخانه اضافه کنید، سپس برای ارسال لمس کنید.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _uploading ? null : _addGif,
                icon: _uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add, size: 18),
                label: Text(_uploading ? 'در حال آپلود...' : 'افزودن گیف (.gif)'),
              ),
            ],
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.95,
      ),
      itemCount: _filtered.length,
      itemBuilder: (ctx, i) {
        final g = _filtered[i];
        final url = _resolveUrl(g);
        return Stack(
          children: [
            GestureDetector(
              onTap: () => widget.onGifSelected(g),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: url.isEmpty
                      ? const Center(child: Icon(Icons.gif, size: 36, color: Colors.grey))
                      : CachedNetworkImage(
                          imageUrl: url,
                          httpHeaders: widget.token == null ? null : {'Authorization': 'Bearer ${widget.token}'},
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          errorWidget: (_, __, ___) => Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.gif, size: 28, color: Colors.blue),
                              const SizedBox(height: 4),
                              Text(g.title ?? 'GIF',
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                  textAlign: TextAlign.center,
                                  maxLines: 2),
                            ]),
                          ),
                        ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => _unsave(g),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.delete_outline, size: 14, color: Colors.white),
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: const Text('GIF',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 520,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(children: [
              const Icon(Icons.gif_box_outlined, color: Colors.blue),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('گیف‌های من', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              IconButton(tooltip: 'بروزرسانی', onPressed: _loadSaved, icon: const Icon(Icons.refresh, size: 20)),
              FilledButton.icon(
                onPressed: _uploading ? null : _addGif,
                icon: _uploading
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add, size: 16),
                label: const Text('افزودن'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(_applyFilter),
              decoration: const InputDecoration(
                hintText: 'جستجو در گیف‌های ذخیره‌شده...',
                prefixIcon: Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                            const SizedBox(height: 8),
                            TextButton(onPressed: _loadSaved, child: const Text('تلاش مجدد')),
                          ]),
                        ),
                      )
                    : _grid(),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey),
              SizedBox(width: 6),
              Expanded(
                  child: Text('فقط گیف‌های خودتان نمایش داده می‌شود. فایل .gif دانلودشده را اضافه کنید.',
                      style: TextStyle(fontSize: 11, color: Colors.grey))),
            ]),
          ),
        ],
      ),
    );
  }
}
