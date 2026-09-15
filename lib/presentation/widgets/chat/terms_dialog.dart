import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/locale_provider.dart';
import '../../../data/services/terms_service.dart';

/// Rules popup: the user must scroll to the bottom before the checkbox
/// becomes enabled (Telegram-style explicit acceptance).
class TermsDialog extends ConsumerStatefulWidget {
  final bool requireAccept;
  const TermsDialog({super.key, this.requireAccept = true});

  static Future<bool?> show(BuildContext context, {bool requireAccept = true}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: !requireAccept,
      builder: (_) => TermsDialog(requireAccept: requireAccept),
    );
  }

  @override
  ConsumerState<TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends ConsumerState<TermsDialog> {
  final _scrollCtrl = ScrollController();
  bool _reachedBottom = false;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    final pos = _scrollCtrl.position.pixels;
    // Short content (no scroll) counts as read.
    final reached = max <= 0 || pos >= max - 24;
    if (reached != _reachedBottom && mounted) {
      setState(() => _reachedBottom = reached);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFa = ref.watch(localeProvider).languageCode == 'fa';
    final rules = TermsService.rulesFor(isFa ? 'fa' : 'en');
    return AlertDialog(
      title: Text(isFa ? 'قوانین برنامه' : 'App Rules'),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Scrollbar(
                  controller: _scrollCtrl,
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    child: Text(rules, style: const TextStyle(fontSize: 13, height: 1.7)),
                  ),
                ),
              ),
            ),
            if (widget.requireAccept) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _accepted,
                enabled: _reachedBottom,
                onChanged: _reachedBottom ? (v) => setState(() => _accepted = v ?? false) : null,
                title: Text(
                  isFa ? 'قوانین را خواندم و می‌پذیرم' : 'I have read and accept the rules',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: _reachedBottom
                    ? null
                    : Text(isFa ? 'برای فعال شدن، تا انتهای قوانین اسکرول کنید' : 'Scroll to the bottom to enable',
                        style: const TextStyle(fontSize: 11, color: Colors.orange)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(isFa ? 'بستن' : 'Close'),
        ),
        if (widget.requireAccept)
          FilledButton(
            onPressed: _accepted ? () => Navigator.pop(context, true) : null,
            child: Text(isFa ? 'تایید' : 'Accept'),
          ),
      ],
    );
  }
}
