import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:night_watch_flutter/core/config.dart';
import 'package:night_watch_flutter/core/detection/anomaly_detector.dart';
import 'package:night_watch_flutter/core/dsp/audio_features.dart';
import 'package:night_watch_flutter/core/dsp/feature_extractor.dart';
import 'package:night_watch_flutter/core/intelligence/event_classifier.dart';
import 'package:night_watch_flutter/core/recorder/event_recorder.dart';
import 'package:night_watch_flutter/models/event_model.dart';
import 'package:night_watch_flutter/models/session.dart';
import 'package:night_watch_flutter/services/audio_capture_service.dart';
import 'package:night_watch_flutter/services/database_service.dart';

/// Central state controller running the Night Watch acoustic pipeline.
class MonitoringController extends ChangeNotifier {
  static final MonitoringController _instance = MonitoringController._internal();
  factory MonitoringController() => _instance;
  MonitoringController._internal();

  final AudioCaptureService _audioCapture = AudioCaptureService();
  final DatabaseService _db = DatabaseService();

  late final FeatureExtractor _extractor;
  late final AnomalyDetector _detector;
  EventRecorder? _recorder;

  StreamSubscription<Float32List>? _chunkSub;
  Timer? _sessionTimer;

  // Pipeline state
  bool _isMonitoring = false;
  bool get isMonitoring => _isMonitoring;

  int? _currentSessionId;
  int? get currentSessionId => _currentSessionId;

  DateTime? _sessionStartTime;
  DateTime? get sessionStartTime => _sessionStartTime;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  // Real-time audio metrics for UI
  double _currentScore = 0.0;
  double get currentScore => _currentScore;

  double _currentRms = 0.0;
  double get currentRms => _currentRms;

  double _currentFlux = 0.0;
  double get currentFlux => _currentFlux;

  double _currentCentroid = 0.0;
  double get currentCentroid => _currentCentroid;

  double _currentZcr = 0.0;
  double get currentZcr => _currentZcr;

  double _zRms = 0.0;
  double get zRms => _zRms;

  double _zFlux = 0.0;
  double get zFlux => _zFlux;

  bool _isWarmingUp = true;
  bool get isWarmingUp => _isWarmingUp;

  int _baselineFrames = 0;
  int get baselineFrames => _baselineFrames;

  RecorderState _recorderState = RecorderState.idle;
  RecorderState get recorderState => _recorderState;

  final List<RecordedEvent> _sessionEvents = [];
  List<RecordedEvent> get sessionEvents => List.unmodifiable(_sessionEvents);

  // Overlapping frame buffer (16,000 samples = 1.0s)
  final Float32List _frameBuffer = Float32List(NightWatchConfig.frameSize);
  int _frameCount = 0;

  AudioFeatures? _lastFeatures;

  Future<void> init() async {
    _extractor = FeatureExtractor(
      sampleRate: NightWatchConfig.sampleRate,
      frameSize: NightWatchConfig.frameSize,
    );
    _detector = AnomalyDetector();
  }

  /// Start live acoustic monitoring session.
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    await init();
    _extractor.reset();
    _detector.reset();

    _frameBuffer.fillRange(0, _frameBuffer.length, 0.0);
    _frameCount = 0;
    _sessionEvents.clear();

    _sessionStartTime = DateTime.now();
    _elapsed = Duration.zero;

    // Create session in database
    _currentSessionId = await _db.createSession(startTime: _sessionStartTime);

    // Setup clip output directory for this session
    final appDir = await getApplicationDocumentsDirectory();
    final sessionClipDir = p.join(appDir.path, 'recordings', 'session_$_currentSessionId');
    final dir = Directory(sessionClipDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _recorder = EventRecorder(
      db: _db,
      sessionId: _currentSessionId!,
      outputDir: sessionClipDir,
    );

    // Start audio stream
    await _audioCapture.start();
    _isMonitoring = true;

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sessionStartTime != null) {
        _elapsed = DateTime.now().difference(_sessionStartTime!);
        notifyListeners();
      }
    });

    _chunkSub = _audioCapture.onAudioChunk.listen(_onChunkReceived);

    notifyListeners();
  }

  void _onChunkReceived(Float32List chunk) async {
    // 1. Shift buffer left by HOP_SIZE and copy new chunk to end
    _frameBuffer.setRange(
      0,
      NightWatchConfig.frameSize - NightWatchConfig.hopSize,
      _frameBuffer.sublist(NightWatchConfig.hopSize),
    );
    _frameBuffer.setRange(
      NightWatchConfig.frameSize - NightWatchConfig.hopSize,
      NightWatchConfig.frameSize,
      chunk,
    );

    _frameCount++;

    // First frame initializes previous spectrum for flux
    if (_frameCount < 2) {
      _extractor.extract(_frameBuffer);
      await _recorder?.processChunk(chunk: chunk, isAnomaly: false, score: 0.0);
      return;
    }

    // 2. Extract features from 1.0s window
    final features = _extractor.extract(_frameBuffer);
    _lastFeatures = features;

    // 3. Process with AnomalyDetector
    final anomalyResult = _detector.process(features);

    _currentScore = anomalyResult.score;
    _currentRms = features.rms;
    _currentFlux = features.spectralFlux;
    _currentCentroid = features.spectralCentroid;
    _currentZcr = features.zcr;
    _zRms = anomalyResult.zRms;
    _zFlux = anomalyResult.zFlux;
    _isWarmingUp = anomalyResult.warmingUp;
    _baselineFrames = anomalyResult.baselineFrames;

    // 4. Feed chunk and anomaly result to EventRecorder
    final finishedEvent = await _recorder?.processChunk(
      chunk: chunk,
      isAnomaly: anomalyResult.isAnomaly,
      score: anomalyResult.score,
    );

    _recorderState = _recorder?.state ?? RecorderState.idle;

    // 5. If an event finished recording, classify it (Phase 7) and log
    if (finishedEvent != null) {
      final classification = EventClassifier.classify(
        peakFeatures: _lastFeatures ?? features,
        peakScore: finishedEvent.peakScore,
        durationSeconds: finishedEvent.durationSeconds,
      );

      await _db.updateEventTag(finishedEvent.id!, classification.tag);
      final taggedEvent = finishedEvent.copyWith(
        tag: classification.tag,
        confidence: classification.confidence,
      );

      _sessionEvents.add(taggedEvent);
    }

    notifyListeners();
  }

  /// Stop monitoring and finalize session.
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    _sessionTimer?.cancel();
    _sessionTimer = null;

    await _chunkSub?.cancel();
    _chunkSub = null;

    await _audioCapture.stop();

    // Finalize any in-progress clip
    final lastEvent = await _recorder?.finalize();
    if (lastEvent != null && _lastFeatures != null) {
      final classification = EventClassifier.classify(
        peakFeatures: _lastFeatures!,
        peakScore: lastEvent.peakScore,
        durationSeconds: lastEvent.durationSeconds,
      );
      await _db.updateEventTag(lastEvent.id!, classification.tag);
      _sessionEvents.add(lastEvent.copyWith(tag: classification.tag));
    }

    if (_currentSessionId != null) {
      await _db.endSession(
        _currentSessionId!,
        endTime: DateTime.now(),
        durationSeconds: _elapsed.inSeconds,
      );
    }

    _isMonitoring = false;
    _recorderState = RecorderState.idle;
    _currentScore = 0.0;

    notifyListeners();
  }

  Future<List<NightSession>> getAllSessions() => _db.getAllSessions();
  Future<List<RecordedEvent>> getEventsForSession(int id) => _db.getEventsForSession(id);
  Future<void> updateEventTag(int eventId, String tag) => _db.updateEventTag(eventId, tag);
  Future<void> deleteSession(int id) => _db.deleteSession(id);
  Future<void> toggleFavorite(int eventId, bool isFav) => _db.toggleFavorite(eventId, isFav);
  Future<void> deleteEvent(int eventId) => _db.deleteEvent(eventId);
}
