import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  bool _isRecording = false;
  DateTime? _startedAt;

  bool get isRecording => _isRecording;
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  Future<bool> startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return false;

    if (!await _recorder.hasPermission()) return false;

    final dir = await getTemporaryDirectory();
    _currentPath = p.join(
      dir.path,
      'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentPath!,
    );
    _isRecording = true;
    _startedAt = DateTime.now();
    return true;
  }

  Future<File?> stopRecording() async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    _startedAt = null;
    if (path != null && File(path).existsSync()) {
      return File(path);
    }
    return null;
  }

  Future<void> cancelRecording() async {
    if (_isRecording) {
      await _recorder.stop();
      _isRecording = false;
    }
    _startedAt = null;
    if (_currentPath != null) {
      final f = File(_currentPath!);
      if (await f.exists()) await f.delete();
    }
    _currentPath = null;
  }

  Future<void> dispose() async {
    await cancelRecording();
    await _recorder.dispose();
  }
}
