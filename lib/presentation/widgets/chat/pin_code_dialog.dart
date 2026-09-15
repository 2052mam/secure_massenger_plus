import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_labels.dart';

/// A four digit PIN prompt used by the archive lock.
///
/// The PIN never leaves this dialog: the caller receives it only to exchange
/// it for a server token, and the field is cleared as soon as it is submitted.
class PinCodeDialog extends StatefulWidget {
  const PinCodeDialog({
    super.key,
    required this.title,
    required this.onSubmit,
    this.subtitle,
    this.confirmLabel,
    this.requireRepeat = false,
    this.requireCurrent = false,
  });

  final String title;
  final String? subtitle;

  /// Returns an error message to display, or null when the PIN was accepted.
  final Future<String?> Function(String pin, String? currentPin) onSubmit;
  final String? confirmLabel;
  final bool requireRepeat;
  final bool requireCurrent;

  @override
  State<PinCodeDialog> createState() => _PinCodeDialogState();
}

class _PinCodeDialogState extends State<PinCodeDialog> {
  final _pin = TextEditingController();
  final _repeat = TextEditingController();
  final _current = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _repeat.dispose();
    _current.dispose();
    super.dispose();
  }

  bool _isFourDigits(String value) => RegExp(r'^\d{4}$').hasMatch(value);

  Future<void> _submit() async {
    if (_busy) return;
    final labels = ChatLabels.of(context);
    final pin = _pin.text.trim();
    final current = _current.text.trim();
    if (!_isFourDigits(pin) ||
        (widget.requireCurrent && !_isFourDigits(current))) {
      setState(() => _error = labels.archivePinInvalid);
      return;
    }
    if (widget.requireRepeat && _repeat.text.trim() != pin) {
      setState(() => _error = labels.archivePinMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(
      pin,
      widget.requireCurrent ? current : null,
    );
    if (!mounted) return;
    _pin.clear();
    _repeat.clear();
    _current.clear();
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool autofocus = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        enabled: !_busy,
        obscureText: true,
        maxLength: 4,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, letterSpacing: 8),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = ChatLabels.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.subtitle != null)
              Text(widget.subtitle!, style: const TextStyle(fontSize: 13)),
            if (widget.requireCurrent)
              _field(_current, labels.archivePinCurrent, autofocus: true),
            _field(
              _pin,
              widget.requireRepeat ? labels.archivePinNew : labels.archivePinTitle,
              autofocus: !widget.requireCurrent,
            ),
            if (widget.requireRepeat) _field(_repeat, labels.archivePinRepeat),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(labels.cancel),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.confirmLabel ?? labels.unlock),
        ),
      ],
    );
  }
}
