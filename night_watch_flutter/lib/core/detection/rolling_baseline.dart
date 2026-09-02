import 'dart:collection';
import 'dart:math' as math;

import 'package:night_watch_flutter/core/config.dart';
import 'package:night_watch_flutter/core/dsp/audio_features.dart';

/// Rolling statistics for a single scalar feature with standard deviation floor.
class FeatureStats {
  final double mean;
  final double std;
  final int count;

  const FeatureStats({required this.mean, required this.std, required this.count});

  @override
  String toString() => 'μ=${mean.toStringAsFixed(4)}, σ=${std.toStringAsFixed(4)} (N=$count)';
}

/// Rolling baseline maintaining a FIFO buffer of recent non-anomalous frames.
///
/// Ported from Python baseline.py.
class RollingBaseline {
  final int maxFrames;
  final DoubleLinkedQueue<AudioFeatures> _history = DoubleLinkedQueue();

  RollingBaseline({this.maxFrames = NightWatchConfig.baselineMaxFrames});

  int get count => _history.length;
  bool get isWarmingUp => count < 10;

  void add(AudioFeatures features) {
    _history.addLast(features);
    while (_history.length > maxFrames) {
      _history.removeFirst();
    }
  }

  void clear() {
    _history.clear();
  }

  /// Compute mean and standard deviation for RMS.
  FeatureStats get rmsStats => _computeStats((f) => f.rms, NightWatchConfig.minStdRms);

  /// Compute mean and standard deviation for Spectral Flux.
  FeatureStats get fluxStats =>
      _computeStats((f) => f.spectralFlux, NightWatchConfig.minStdSpectralFlux);

  /// Compute mean and standard deviation for Spectral Centroid.
  FeatureStats get centroidStats =>
      _computeStats((f) => f.spectralCentroid, NightWatchConfig.minStdCentroidDelta);

  /// Compute mean and standard deviation for Zero-Crossing Rate.
  FeatureStats get zcrStats => _computeStats((f) => f.zcr, NightWatchConfig.minStdZcr);

  FeatureStats _computeStats(double Function(AudioFeatures) getter, double minStdFloor) {
    if (_history.isEmpty) {
      return FeatureStats(mean: 0.0, std: minStdFloor, count: 0);
    }

    double sum = 0.0;
    for (final item in _history) {
      sum += getter(item);
    }
    final mean = sum / _history.length;

    if (_history.length < 2) {
      return FeatureStats(mean: mean, std: minStdFloor, count: _history.length);
    }

    double sumSqDiff = 0.0;
    for (final item in _history) {
      final diff = getter(item) - mean;
      sumSqDiff += diff * diff;
    }
    final variance = sumSqDiff / (_history.length - 1);
    final rawStd = math.sqrt(variance);
    final std = math.max(rawStd, minStdFloor);

    return FeatureStats(mean: mean, std: std, count: _history.length);
  }
}
