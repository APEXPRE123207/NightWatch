import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'package:night_watch_flutter/core/config.dart';

/// Captures live PCM 16-bit 16 kHz mono audio stream from microphone.
class AudioCaptureService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSub;

  final StreamController<Float32List> _chunkController =
      StreamController<Float32List>.broadcast();

  Stream<Float32List> get onAudioChunk => _chunkController.stream;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  // Buffer to accumulate incoming byte packets into exact HOP_SIZE (8000 samples)
  final List<double> _sampleAccumulator = [];

  Future<bool> hasPermission() async {
    return await _audioRecorder.hasPermission();
  }

  /// Start recording raw PCM stream at 16 kHz mono.
  Future<void> start() async {
    if (_isRecording) return;

    final hasPerm = await _audioRecorder.hasPermission();
    if (!hasPerm) {
      throw Exception('Microphone permission not granted');
    }

    _sampleAccumulator.clear();

    const recordConfig = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: NightWatchConfig.sampleRate,
      numChannels: NightWatchConfig.channels,
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
    );

    final stream = await _audioRecorder.startStream(recordConfig);
    _isRecording = true;

    _recordSub = stream.listen((Uint8List byteData) {
      _processRawBytes(byteData);
    }, onError: (err) {
      // Stream error handling
    });
  }

  void _processRawBytes(Uint8List byteData) {
    // Convert 16-bit PCM bytes (little endian) to normalized Float32 [-1.0, 1.0]
    final byteBuffer = byteData.buffer;
    final int16List = byteBuffer.asInt16List(byteData.offsetInBytes, byteData.lengthInBytes ~/ 2);

    for (int i = 0; i < int16List.length; i++) {
      final sample = int16List[i] / 32768.0;
      _sampleAccumulator.add(sample);
    }

    // When we have accumulated at least HOP_SIZE (8000 samples), emit a chunk
    while (_sampleAccumulator.length >= NightWatchConfig.hopSize) {
      final chunkSamples = _sampleAccumulator.sublist(0, NightWatchConfig.hopSize);
      _sampleAccumulator.removeRange(0, NightWatchConfig.hopSize);

      final floatList = Float32List.fromList(chunkSamples);
      _chunkController.add(floatList);
    }
  }

  /// Stop audio recording.
  Future<void> stop() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _recordSub?.cancel();
    _recordSub = null;
    await _audioRecorder.stop();
    _sampleAccumulator.clear();
  }

  Future<void> dispose() async {
    await stop();
    await _chunkController.close();
    await _audioRecorder.dispose();
  }
}
