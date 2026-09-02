import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:night_watch_flutter/core/config.dart';
import 'package:night_watch_flutter/core/recorder/circular_buffer.dart';
import 'package:night_watch_flutter/core/recorder/wav_encoder.dart';
import 'package:night_watch_flutter/models/event_model.dart';
import 'package:night_watch_flutter/services/database_service.dart';

enum RecorderState {
  idle,
  recording,
  coolingDown,
  postBuffering,
  mergeWindow,
}

/// Event Recorder state machine managing pre-buffer, anomaly capture, cooldown,
/// post-buffering, event merging (Phase 4), and WAV encoding.
///
/// Ported from Python event_recorder.py.
class EventRecorder {
  final DatabaseService db;
  final int sessionId;
  final String outputDir;

  late final CircularAudioBuffer _preBuffer;

  RecorderState _state = RecorderState.idle;
  int _consecutiveAnomalies = 0;
  int _cooldownRemaining = 0;
  int _postRemaining = 0;
  int _mergeRemaining = 0;

  final List<Float32List> _eventAudio = [];
  DateTime? _eventStartTime;
  double _eventPeakScore = 0.0;
  int _eventCount = 0;

  final List<RecordedEvent> completedEvents = [];

  EventRecorder({
    required this.db,
    required this.sessionId,
    required this.outputDir,
  }) {
    final preSamples = (NightWatchConfig.preBufferS * NightWatchConfig.sampleRate).round();
    _preBuffer = CircularAudioBuffer(preSamples);
  }

  RecorderState get state => _state;
  int get eventCount => _eventCount;
  double get currentPeakScore => _eventPeakScore;

  /// Process one hop chunk of raw audio and detection results.
  Future<RecordedEvent?> processChunk({
    required Float32List chunk,
    required bool isAnomaly,
    required double score,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    RecordedEvent? finishedEvent;

    switch (_state) {
      case RecorderState.idle:
        _preBuffer.write(chunk);
        if (isAnomaly) {
          _consecutiveAnomalies++;
          if (_consecutiveAnomalies >= NightWatchConfig.triggerConsecutive) {
            _startEvent(now, score);
          }
        } else {
          _consecutiveAnomalies = 0;
        }
        break;

      case RecorderState.recording:
        _eventAudio.add(Float32List.fromList(chunk));
        if (score > _eventPeakScore) _eventPeakScore = score;
        if (!isAnomaly) {
          _cooldownRemaining = NightWatchConfig.cooldownFrames;
          _state = RecorderState.coolingDown;
        }
        break;

      case RecorderState.coolingDown:
        _eventAudio.add(Float32List.fromList(chunk));
        if (score > _eventPeakScore) _eventPeakScore = score;
        if (isAnomaly) {
          _state = RecorderState.recording;
          _cooldownRemaining = 0;
        } else {
          _cooldownRemaining--;
          if (_cooldownRemaining <= 0) {
            final postFrames =
                (NightWatchConfig.postBufferS / NightWatchConfig.hopDurationS).round();
            _postRemaining = postFrames;
            _state = RecorderState.postBuffering;
          }
        }
        break;

      case RecorderState.postBuffering:
        _eventAudio.add(Float32List.fromList(chunk));
        _postRemaining--;
        if (_postRemaining <= 0) {
          final mergeFrames =
              (NightWatchConfig.mergeGapS / NightWatchConfig.hopDurationS).round();
          _mergeRemaining = mergeFrames;
          _state = RecorderState.mergeWindow;
        }
        break;

      case RecorderState.mergeWindow:
        _eventAudio.add(Float32List.fromList(chunk));
        if (isAnomaly) {
          // New anomaly during merge window -> merge seamlessly into same event
          _state = RecorderState.recording;
          _mergeRemaining = 0;
          if (score > _eventPeakScore) _eventPeakScore = score;
        } else {
          _mergeRemaining--;
          if (_mergeRemaining <= 0) {
            // Merge window expired -> trim silence tail and finalize
            final mergeSamples =
                (NightWatchConfig.mergeGapS * NightWatchConfig.sampleRate).round();
            finishedEvent = await _endEvent(now, trimTailSamples: mergeSamples);
          }
        }
        break;
    }

    return finishedEvent;
  }

  void _startEvent(DateTime now, double score) {
    _eventStartTime = now;
    _eventPeakScore = score;
    _eventAudio.clear();

    final preAudio = _preBuffer.readAll();
    if (preAudio.isNotEmpty) {
      _eventAudio.add(preAudio);
    }

    _state = RecorderState.recording;
    _consecutiveAnomalies = 0;
  }

  Future<RecordedEvent> _endEvent(DateTime now, {int trimTailSamples = 0}) async {
    _eventCount++;

    // Concatenate all audio chunks
    int totalLen = 0;
    for (final c in _eventAudio) {
      totalLen += c.length;
    }

    Float32List fullAudio;
    if (totalLen > 0) {
      fullAudio = Float32List(totalLen);
      int offset = 0;
      for (final c in _eventAudio) {
        fullAudio.setRange(offset, offset + c.length, c);
        offset += c.length;
      }
    } else {
      fullAudio = Float32List(0);
    }

    // Trim merge window silence from tail if not merged
    if (trimTailSamples > 0 && fullAudio.length > trimTailSamples) {
      fullAudio = fullAudio.sublist(0, fullAudio.length - trimTailSamples);
    }

    final duration = fullAudio.length / NightWatchConfig.sampleRate;
    final filename = 'event_${_eventCount.toString().padLeft(4, '0')}.wav';
    final clipPath = p.join(outputDir, filename);

    // Save 16-bit WAV file
    await WavEncoder.writeWavFile(
      filePath: clipPath,
      audio: fullAudio,
      sampleRate: NightWatchConfig.sampleRate,
    );

    final start = _eventStartTime ?? now;
    final event = RecordedEvent(
      sessionId: sessionId,
      eventNumber: _eventCount,
      startTime: start,
      endTime: now,
      durationSeconds: double.parse(duration.toStringAsFixed(2)),
      peakScore: double.parse(_eventPeakScore.toStringAsFixed(2)),
      clipPath: clipPath,
    );

    final eventId = await db.insertEvent(event);
    final savedEvent = event.copyWith(id: eventId);
    completedEvents.add(savedEvent);

    // Reset state for next event
    _eventAudio.clear();
    _eventStartTime = null;
    _eventPeakScore = 0.0;
    _state = RecorderState.idle;
    _preBuffer.clear();

    return savedEvent;
  }

  /// Finalize in-progress event on session stop.
  Future<RecordedEvent?> finalize() async {
    if (_state != RecorderState.idle && _eventAudio.isNotEmpty) {
      return await _endEvent(DateTime.now());
    }
    return null;
  }
}
