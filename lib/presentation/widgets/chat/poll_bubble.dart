import 'package:flutter/material.dart';
import '../../../data/models/message_model.dart';
import '../../../data/services/api_service.dart';

class PollBubble extends StatefulWidget {
  final MessageModel message;
  final ApiService api;
  final bool isMine;
  final Color foreground;
  final VoidCallback? onUpdated;

  const PollBubble({
    super.key,
    required this.message,
    required this.api,
    required this.isMine,
    required this.foreground,
    this.onUpdated,
  });

  @override
  State<PollBubble> createState() => _PollBubbleState();
}

class _PollBubbleState extends State<PollBubble> {
  late PollModel _poll;
  bool _voting = false;

  @override
  void initState() {
    super.initState();
    _poll = widget.message.poll!;
  }

  @override
  void didUpdateWidget(covariant PollBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message.poll != oldWidget.message.poll) {
      _poll = widget.message.poll!;
    }
  }

  Future<void> _vote(int index) async {
    if (_poll.isClosed || _voting) return;
    setState(() => _voting = true);
    try {
      // Determine new selection
      List<int> newVotes;
      if (_poll.allowsMultiple) {
        final cur = List<int>.from(_poll.myVotes);
        if (cur.contains(index)) {
          cur.remove(index);
        } else {
          cur.add(index);
        }
        newVotes = cur;
      } else {
        if (_poll.myVotes.length == 1 && _poll.myVotes.first == index) {
          // Already voted same option -> allow unvote? For single, tapping same = no change
          setState(() => _voting = false);
          return;
        }
        newVotes = [index];
      }
      final res = await widget.api.post('/messages/${widget.message.id}/poll/vote', {
        'option_indexes': newVotes,
      });
      final pollJson = res['poll'] as Map<String, dynamic>?;
      if (pollJson != null && mounted) {
        final updated = PollModel.fromJson(pollJson);
        // Merge myVotes from server if provided, else keep local
        // Also need to fetch my_votes separately if not in response
        // Try to get fresh poll with my_votes
        try {
          final fresh = await widget.api.get('/messages/${widget.message.id}/poll');
          final p = fresh['poll'] as Map<String, dynamic>?;
          if (p != null && mounted) {
            setState(() => _poll = PollModel.fromJson(p));
            widget.onUpdated?.call();
            return;
          }
        } catch (_) {}
        setState(() => _poll = updated);
        widget.onUpdated?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطا: $e')));
      }
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  Future<void> _closePoll() async {
    if (_poll.isClosed) return;
    try {
      final res = await widget.api.post('/messages/${widget.message.id}/poll/close', {});
      final pollJson = res['poll'] as Map<String, dynamic>?;
      if (pollJson != null && mounted) {
        setState(() => _poll = PollModel.fromJson(pollJson));
        widget.onUpdated?.call();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نظرسنجی بسته شد')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _poll.totalVoters == 0
        ? _poll.options.fold<int>(0, (a, o) => a + o.votes)
        : _poll.totalVoters;
    // For display, use sum votes if totalVoters zero
    final sumVotes = _poll.options.fold<int>(0, (a, o) => a + o.votes);
    final effectiveTotal = total > 0 ? total : (sumVotes > 0 ? sumVotes : 1);
    final isQuiz = _poll.isQuiz;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(isQuiz ? Icons.quiz_outlined : Icons.poll_outlined, color: widget.foreground, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _poll.question,
                style: TextStyle(color: widget.foreground, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            if (_poll.isClosed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: const Text('بسته شده', style: TextStyle(fontSize: 10, color: Colors.red)),
              ),
          ],
        ),
        if (isQuiz && _poll.explanation != null) ...[
          const SizedBox(height: 6),
          Text(_poll.explanation!, style: TextStyle(color: widget.foreground.withValues(alpha: 0.8), fontSize: 12, fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 10),
        ...List.generate(_poll.options.length, (i) {
          final opt = _poll.options[i];
          final pct = (opt.votes / effectiveTotal).clamp(0.0, 1.0);
          final isMine = _poll.myVotes.contains(i);
          final isCorrect = isQuiz && _poll.correctOption == i;
          final showResult = _poll.isClosed || _poll.myVotes.isNotEmpty || isQuiz;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: _poll.isClosed || _voting ? null : () => _vote(i),
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.foreground.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isMine ? Colors.blue : widget.foreground.withValues(alpha: 0.12)),
                    ),
                  ),
                  if (showResult)
                    FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: isCorrect
                              ? Colors.green.withValues(alpha: 0.25)
                              : (isMine ? Colors.blue.withValues(alpha: 0.25) : widget.foreground.withValues(alpha: 0.12)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          if (_poll.allowsMultiple)
                            Icon(isMine ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: widget.foreground)
                          else
                            Icon(isMine ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: widget.foreground),
                          const SizedBox(width: 8),
                          Expanded(child: Text(opt.text, style: TextStyle(color: widget.foreground, fontSize: 14))),
                          if (showResult) ...[
                            const SizedBox(width: 8),
                            Text('${(pct * 100).toStringAsFixed(0)}% • ${opt.votes}', style: TextStyle(color: widget.foreground.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.bold)),
                            if (isCorrect) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.check_circle, color: Colors.green, size: 16)),
                          ],
                          if (_voting) const SizedBox(width: 8, child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              _poll.isAnonymous ? 'ناشناس • $sumVotes رأی • ${sumVotes == 1 ? '۱ نفر' : '$total نفر'}' : '$sumVotes رأی • $total نفر',
              style: TextStyle(color: widget.foreground.withValues(alpha: 0.7), fontSize: 11),
            ),
            const Spacer(),
            if (_poll.allowsMultiple) Text('چندگزینه‌ای', style: TextStyle(color: widget.foreground.withValues(alpha: 0.7), fontSize: 11)),
          ],
        ),
        if ((widget.isMine || _poll.isClosed == false) && !_poll.isClosed)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _closePoll,
              child: const Text('بستن نظرسنجی', style: TextStyle(fontSize: 12)),
            ),
          ),
      ],
    );
  }
}
