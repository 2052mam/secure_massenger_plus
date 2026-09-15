import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

/// Telegram-like internal photo editor: crop (aspect ratios), rotate, flip,
/// draw (pen colors/sizes), text overlay, then send.
/// Returns the edited [File] via Navigator.pop.
///
/// Design notes (these were the source of the old bugs):
///  * The base image is decoded ONCE and kept as a `ui.Image`; the preview
///    never re-encodes JPEG during build, so panning stays smooth.
///  * Rotate/flip/crop are *non-destructive view state* — they no longer wipe
///    the user's strokes and text.
///  * Strokes and text are stored in normalised (0..1) image space, so they
///    stay glued to the picture at any widget size and survive transforms.
class PhotoEditorScreen extends StatefulWidget {
  final File imageFile;
  const PhotoEditorScreen({super.key, required this.imageFile});

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

/// A stroke in normalised image space (0..1 on both axes).
class _DrawStroke {
  final List<Offset> points;
  final Color color;

  /// Stroke width as a fraction of the image's shortest side.
  final double width;
  _DrawStroke({required this.points, required this.color, required this.width});

  _DrawStroke copyWith({List<Offset>? points}) =>
      _DrawStroke(points: points ?? this.points, color: color, width: width);
}

/// Text overlay anchored in normalised image space.
class _TextOverlay {
  String text;
  Offset position;
  Color color;

  /// Font size as a fraction of the image height.
  double size;
  _TextOverlay({
    required this.text,
    required this.position,
    required this.color,
    required this.size,
  });
}

enum _EditorTool { draw, move }

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  final _canvasKey = GlobalKey();

  ui.Image? _image;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  // Non-destructive transform state.
  int _quarterTurns = 0;
  bool _flipH = false;
  double? _aspectRatio; // null = original/free

  // Overlays (normalised coordinates).
  final List<_DrawStroke> _strokes = [];
  final List<_TextOverlay> _texts = [];
  _DrawStroke? _activeStroke;

  Color _penColor = Colors.red;
  double _penWidth = 6; // logical px at preview scale
  _EditorTool _tool = _EditorTool.draw;
  _TextOverlay? _draggingText;

  static const _colors = [
    Colors.red,
    Colors.white,
    Colors.black,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.orange,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image = frame.image;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'باز کردن تصویر ممکن نشد';
        });
      }
    }
  }

  bool get _isRotatedSideways => _quarterTurns.isOdd;

  /// Size of the visible (cropped + rotated) image in source pixels.
  Size get _croppedSourceSize {
    final image = _image;
    if (image == null) return Size.zero;
    final rotatedW =
        _isRotatedSideways ? image.height.toDouble() : image.width.toDouble();
    final rotatedH =
        _isRotatedSideways ? image.width.toDouble() : image.height.toDouble();
    final ratio = _aspectRatio;
    if (ratio == null) return Size(rotatedW, rotatedH);
    var w = rotatedW;
    var h = rotatedH;
    if (w / h > ratio) {
      w = h * ratio;
    } else {
      h = w / ratio;
    }
    return Size(w, h);
  }

  /// Destination rect (centred on the origin, in the rotated coordinate
  /// space) that makes the source image *cover* [target] without distortion.
  Rect _coverRect(Size target) {
    final image = _image!;
    // In the rotated frame the visible box swaps its axes.
    final boxW = _isRotatedSideways ? target.height : target.width;
    final boxH = _isRotatedSideways ? target.width : target.height;
    final scale = math.max(boxW / image.width, boxH / image.height);
    return Rect.fromCenter(
      center: Offset.zero,
      width: image.width * scale,
      height: image.height * scale,
    );
  }

  void _rotate() => setState(() => _quarterTurns = (_quarterTurns + 1) % 4);

  void _flip() => setState(() => _flipH = !_flipH);

  void _setAspect(double? ratio) => setState(() => _aspectRatio = ratio);

  void _undo() {
    setState(() {
      if (_texts.isNotEmpty && _strokes.isEmpty) {
        _texts.removeLast();
      } else if (_strokes.isNotEmpty) {
        _strokes.removeLast();
      }
    });
  }

  void _clearAll() {
    setState(() {
      _strokes.clear();
      _texts.clear();
    });
  }

  /// The rect the picture actually occupies inside the canvas box.
  Rect _imageRect(Size canvas) {
    final source = _croppedSourceSize;
    if (source.isEmpty || canvas.isEmpty) return Rect.zero;
    final scale =
        math.min(canvas.width / source.width, canvas.height / source.height);
    final w = source.width * scale;
    final h = source.height * scale;
    return Rect.fromLTWH(
      (canvas.width - w) / 2,
      (canvas.height - h) / 2,
      w,
      h,
    );
  }

  Offset? _toNormalised(Offset local, Size canvas) {
    final rect = _imageRect(canvas);
    if (rect.isEmpty) return null;
    return Offset(
      ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }

  Size _canvasSize() {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size ?? Size.zero;
  }

  _TextOverlay? _hitTestText(Offset local, Size canvas) {
    final rect = _imageRect(canvas);
    if (rect.isEmpty) return null;
    for (final t in _texts.reversed) {
      final center = Offset(
        rect.left + t.position.dx * rect.width,
        rect.top + t.position.dy * rect.height,
      );
      final fontSize = t.size * rect.height;
      final painter = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final box = Rect.fromCenter(
        center: center,
        width: math.max(painter.width, 40) + 24,
        height: math.max(painter.height, 24) + 24,
      );
      if (box.contains(local)) return t;
    }
    return null;
  }

  void _onPanStart(DragStartDetails d) {
    final canvas = _canvasSize();
    final text = _hitTestText(d.localPosition, canvas);
    if (text != null) {
      _draggingText = text;
      return;
    }
    if (_tool != _EditorTool.draw) return;
    final point = _toNormalised(d.localPosition, canvas);
    if (point == null) return;
    final rect = _imageRect(canvas);
    setState(() {
      _activeStroke = _DrawStroke(
        points: [point],
        color: _penColor,
        // Normalise against the shortest preview side so the exported stroke
        // matches what was drawn.
        width: _penWidth / math.min(rect.width, rect.height),
      );
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final canvas = _canvasSize();
    final dragging = _draggingText;
    if (dragging != null) {
      final rect = _imageRect(canvas);
      if (rect.isEmpty) return;
      setState(() {
        dragging.position = Offset(
          (dragging.position.dx + d.delta.dx / rect.width).clamp(0.0, 1.0),
          (dragging.position.dy + d.delta.dy / rect.height).clamp(0.0, 1.0),
        );
      });
      return;
    }
    final stroke = _activeStroke;
    if (stroke == null) return;
    final point = _toNormalised(d.localPosition, canvas);
    if (point == null) return;
    setState(() {
      _activeStroke = stroke.copyWith(points: [...stroke.points, point]);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    if (_draggingText != null) {
      _draggingText = null;
      return;
    }
    final stroke = _activeStroke;
    if (stroke == null) return;
    setState(() {
      _strokes.add(stroke);
      _activeStroke = null;
    });
  }

  Future<void> _addOrEditText([_TextOverlay? existing]) async {
    final ctrl = TextEditingController(text: existing?.text ?? '');
    var color = existing?.color ?? Colors.white;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(existing == null ? 'متن روی عکس' : 'ویرایش متن'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'متن...'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: _colors
                    .map((c) => GestureDetector(
                          onTap: () => setD(() => color = c),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color == c ? Colors.blue : Colors.grey,
                                width: color == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () => Navigator.pop(ctx, '__delete__'),
                child: const Text('حذف', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(existing == null ? 'افزودن' : 'ذخیره'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result == '__delete__') {
        if (existing != null) _texts.remove(existing);
        return;
      }
      if (result.isEmpty) return;
      if (existing != null) {
        existing.text = result;
        existing.color = color;
      } else {
        _texts.add(_TextOverlay(
          text: result,
          position: const Offset(0.5, 0.4),
          color: color,
          size: 0.07,
        ));
      }
    });
  }

  /// Renders the final image at full source resolution — independent of the
  /// preview size, so quality never depends on the phone's screen.
  Future<Uint8List?> _renderResult() async {
    final image = _image;
    if (image == null) return null;
    final target = _croppedSourceSize;
    if (target.isEmpty) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder,
        Rect.fromLTWH(0, 0, target.width, target.height));

    canvas.save();
    // Apply flip + rotation about the centre of the output.
    canvas.translate(target.width / 2, target.height / 2);
    if (_flipH) canvas.scale(-1, 1);
    canvas.rotate(_quarterTurns * math.pi / 2);
    // Cover the target rect while preserving the picture's aspect ratio, so a
    // crop actually crops instead of squashing the image.
    final dst = _coverRect(target);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    _paintOverlays(canvas, target);

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      target.width.round(),
      target.height.round(),
    );
    picture.dispose();
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    if (data == null) return null;

    // Re-encode as JPEG (smaller upload) via the image package.
    final decoded = img.decodePng(data.buffer.asUint8List());
    if (decoded == null) return data.buffer.asUint8List();
    return Uint8List.fromList(img.encodeJpg(decoded, quality: 92));
  }

  void _paintOverlays(Canvas canvas, Size size) {
    for (final stroke in [..._strokes, if (_activeStroke != null) _activeStroke!]) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width * math.min(size.width, size.height)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          Offset(stroke.points.first.dx * size.width,
              stroke.points.first.dy * size.height),
          paint.strokeWidth / 2,
          Paint()..color = stroke.color,
        );
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx * size.width,
            stroke.points.first.dy * size.height);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(
            stroke.points[i].dx * size.width, stroke.points[i].dy * size.height);
      }
      canvas.drawPath(path, paint);
    }

    for (final t in _texts) {
      final painter = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            color: t.color,
            fontSize: t.size * size.height,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
      )..layout(maxWidth: size.width * 0.9);
      painter.paint(
        canvas,
        Offset(
          t.position.dx * size.width - painter.width / 2,
          t.position.dy * size.height - painter.height / 2,
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _renderResult();
      if (!mounted) return;
      if (bytes == null) {
        Navigator.pop(context, widget.imageFile);
        return;
      }
      final path =
          '${widget.imageFile.parent.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = await File(path).writeAsBytes(bytes);
      if (mounted) Navigator.pop(context, file);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ذخیره ناموفق: $e')));
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_strokes.isEmpty &&
        _texts.isEmpty &&
        _quarterTurns == 0 &&
        !_flipH &&
        _aspectRatio == null) {
      return true;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('لغو ویرایش'),
        content: const Text('تغییرات ذخیره نشده از بین می‌رود. مطمئن هستید؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ادامه ویرایش')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('لغو ویرایش'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('ویرایش عکس'),
          actions: [
            IconButton(
              tooltip: 'چرخش',
              icon: const Icon(Icons.rotate_right),
              onPressed: image == null ? null : _rotate,
            ),
            IconButton(
              tooltip: 'آینه',
              icon: const Icon(Icons.flip),
              onPressed: image == null ? null : _flip,
            ),
            IconButton(
              tooltip: 'متن',
              icon: const Icon(Icons.text_fields),
              onPressed: image == null ? null : () => _addOrEditText(),
            ),
            IconButton(
              tooltip: 'واگرد',
              icon: const Icon(Icons.undo),
              onPressed:
                  (_strokes.isEmpty && _texts.isEmpty) ? null : _undo,
            ),
            IconButton(
              tooltip: 'ارسال',
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.green),
                    )
                  : const Icon(Icons.check, color: Colors.green),
              onPressed: (image == null || _saving) ? null : _save,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _loadError != null || image == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.broken_image_outlined,
                            color: Colors.white38, size: 48),
                        const SizedBox(height: 8),
                        Text(_loadError ?? 'تصویر در دسترس نیست',
                            style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () =>
                              Navigator.pop(context, widget.imageFile),
                          child: const Text('ارسال بدون ویرایش'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(children: [
                          _cropChip('اصلی', null),
                          _cropChip('۱:۱', 1.0),
                          _cropChip('۴:۳', 4 / 3),
                          _cropChip('۳:۴', 3 / 4),
                          _cropChip('۱۶:۹', 16 / 9),
                          _cropChip('۹:۱۶', 9 / 16),
                        ]),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanStart: _onPanStart,
                            onPanUpdate: _onPanUpdate,
                            onPanEnd: _onPanEnd,
                            onTapUp: (d) {
                              final t =
                                  _hitTestText(d.localPosition, _canvasSize());
                              if (t != null) _addOrEditText(t);
                            },
                            child: CustomPaint(
                              key: _canvasKey,
                              size: Size.infinite,
                              painter: _EditorPainter(
                                image: image,
                                quarterTurns: _quarterTurns,
                                flipH: _flipH,
                                sourceSize: _croppedSourceSize,
                                strokes: [
                                  ..._strokes,
                                  if (_activeStroke != null) _activeStroke!
                                ],
                                texts: _texts,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _buildToolbar(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: _tool == _EditorTool.draw
                    ? 'حالت جابه‌جایی متن'
                    : 'حالت نقاشی',
                icon: Icon(
                  _tool == _EditorTool.draw
                      ? Icons.brush
                      : Icons.pan_tool_outlined,
                  color: _tool == _EditorTool.draw
                      ? Colors.greenAccent
                      : Colors.white,
                ),
                onPressed: () => setState(() => _tool =
                    _tool == _EditorTool.draw
                        ? _EditorTool.move
                        : _EditorTool.draw),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _colors
                        .map((c) => GestureDetector(
                              onTap: () => setState(() {
                                _penColor = c;
                                _tool = _EditorTool.draw;
                              }),
                              child: Container(
                                width: 28,
                                height: 28,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _penColor == c
                                        ? Colors.blue
                                        : Colors.white30,
                                    width: _penColor == c ? 3 : 1,
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'پاک کردن همه',
                icon: const Icon(Icons.delete_outline, color: Colors.white70),
                onPressed:
                    (_strokes.isEmpty && _texts.isEmpty) ? null : _clearAll,
              ),
            ],
          ),
          Row(children: [
            const Text('ضخامت',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            Expanded(
              child: Slider(
                value: _penWidth,
                min: 2,
                max: 24,
                onChanged: (v) => setState(() => _penWidth = v),
              ),
            ),
            SizedBox(
              width: 26,
              height: 26,
              child: Center(
                child: Container(
                  width: _penWidth,
                  height: _penWidth,
                  decoration:
                      BoxDecoration(color: _penColor, shape: BoxShape.circle),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _cropChip(String label, double? ratio) {
    final selected = _aspectRatio == ratio;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label,
            style:
                TextStyle(color: selected ? Colors.white : Colors.white70)),
        selected: selected,
        selectedColor: Colors.blue,
        backgroundColor: Colors.white10,
        onSelected: (_) => _setAspect(ratio),
      ),
    );
  }
}

/// Paints the picture plus overlays. Everything is derived from the current
/// state, so a repaint costs no decoding or encoding.
class _EditorPainter extends CustomPainter {
  final ui.Image image;
  final int quarterTurns;
  final bool flipH;
  final Size sourceSize;
  final List<_DrawStroke> strokes;
  final List<_TextOverlay> texts;

  _EditorPainter({
    required this.image,
    required this.quarterTurns,
    required this.flipH,
    required this.sourceSize,
    required this.strokes,
    required this.texts,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (sourceSize.isEmpty || size.isEmpty) return;
    final scale = math.min(
        size.width / sourceSize.width, size.height / sourceSize.height);
    final drawn = Size(sourceSize.width * scale, sourceSize.height * scale);
    final origin = Offset(
        (size.width - drawn.width) / 2, (size.height - drawn.height) / 2);

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.clipRect(Rect.fromLTWH(0, 0, drawn.width, drawn.height));

    // Image with transforms.
    canvas.save();
    canvas.translate(drawn.width / 2, drawn.height / 2);
    if (flipH) canvas.scale(-1, 1);
    canvas.rotate(quarterTurns * math.pi / 2);
    final sideways = quarterTurns.isOdd;
    // Cover (never stretch) — must match _renderResult exactly, otherwise the
    // exported picture would not equal the preview.
    final boxW = sideways ? drawn.height : drawn.width;
    final boxH = sideways ? drawn.width : drawn.height;
    final cover = math.max(boxW / image.width, boxH / image.height);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromCenter(
        center: Offset.zero,
        width: image.width * cover,
        height: image.height * cover,
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    // Overlays in normalised space.
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth =
            stroke.width * math.min(drawn.width, drawn.height)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          Offset(stroke.points.first.dx * drawn.width,
              stroke.points.first.dy * drawn.height),
          paint.strokeWidth / 2,
          Paint()..color = stroke.color,
        );
        continue;
      }
      final path = Path()
        ..moveTo(stroke.points.first.dx * drawn.width,
            stroke.points.first.dy * drawn.height);
      for (var i = 1; i < stroke.points.length; i++) {
        path.lineTo(stroke.points[i].dx * drawn.width,
            stroke.points[i].dy * drawn.height);
      }
      canvas.drawPath(path, paint);
    }

    for (final t in texts) {
      final painter = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            color: t.color,
            fontSize: t.size * drawn.height,
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
          ),
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
      )..layout(maxWidth: drawn.width * 0.9);
      painter.paint(
        canvas,
        Offset(
          t.position.dx * drawn.width - painter.width / 2,
          t.position.dy * drawn.height - painter.height / 2,
        ),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EditorPainter old) =>
      old.image != image ||
      old.quarterTurns != quarterTurns ||
      old.flipH != flipH ||
      old.sourceSize != sourceSize ||
      old.strokes != strokes ||
      old.texts != texts ||
      old.strokes.length != strokes.length ||
      old.texts.length != texts.length;
}
