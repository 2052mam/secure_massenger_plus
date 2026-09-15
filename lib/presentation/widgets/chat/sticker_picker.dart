import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../data/models/sticker_model.dart';
import '../../../data/services/api_service.dart';

class StickerPicker extends StatefulWidget {
  final ApiService api;
  final ValueChanged<StickerModel> onStickerSelected;
  const StickerPicker({super.key, required this.api, required this.onStickerSelected});

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> with SingleTickerProviderStateMixin {
  List<StickerPackModel> _packs = [];
  List<StickerModel> _stickers = [];
  int _selectedPackIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    try {
      final res = await widget.api.get('/stickers/packs');
      final packs = (res['packs'] as List? ?? []).map((e) => StickerPackModel.fromJson(e as Map<String, dynamic>)).toList();
      if (packs.isEmpty) {
        setState(() { _loading = false; });
        return;
      }
      // Load first pack stickers
      final first = await widget.api.get('/stickers/packs/${packs.first.id}');
      final packDetail = StickerPackModel.fromJson(first['pack'] as Map<String, dynamic>);
      setState(() {
        _packs = packs;
        _stickers = packDetail.stickers ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _selectPack(int index) async {
    if (index == _selectedPackIndex) return;
    setState(() { _selectedPackIndex = index; _stickers = []; });
    try {
      final res = await widget.api.get('/stickers/packs/${_packs[index].id}');
      final pack = StickerPackModel.fromJson(res['pack'] as Map<String, dynamic>);
      setState(() { _stickers = pack.stickers ?? []; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _packs.length,
                        itemBuilder: (ctx, i) => GestureDetector(
                          onTap: () => _selectPack(i),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: i == _selectedPackIndex ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: i == _selectedPackIndex ? Theme.of(context).colorScheme.primary : Colors.transparent),
                            ),
                            child: Row(
                              children: [
                                if (_packs[i].thumbnailUrl != null)
                                  CachedNetworkImage(imageUrl: _packs[i].thumbnailUrl!, width: 22, height: 22),
                                const SizedBox(width: 6),
                                Text(_packs[i].title, style: TextStyle(fontSize: 12, fontWeight: i==_selectedPackIndex? FontWeight.w600:FontWeight.normal)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8),
                        itemCount: _stickers.length,
                        itemBuilder: (ctx, idx) {
                          final s = _stickers[idx];
                          return InkWell(
                            onTap: () => widget.onStickerSelected(s),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: s.fileUrl != null
                                  ? CachedNetworkImage(imageUrl: s.fileUrl!, fit: BoxFit.contain, placeholder: (_, __) => const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))), errorWidget: (_, __, ___) => Center(child: Text(s.emoji ?? '🙂', style: const TextStyle(fontSize: 28))))
                                  : Center(child: Text(s.emoji ?? '🙂', style: const TextStyle(fontSize: 32))),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
