import 'dart:math' as math;

import 'package:night_watch_flutter/core/config.dart';
import 'package:night_watch_flutter/core/detection/rolling_baseline.dart';
import 'package:night_watch_flutter/core/dsp/audio_features.dart';

/// Result of evaluating a single audio frame against the ambient baseline.
class AnomalyResult {
  final bool isAnomaly;
  final double score;
  final double zRms;
  final double zFlux;
  final double zCentroid;
  final double zZcr;
  final bool warmingUp;
  final int baselineFrames;
  final AudioFeatures features;

  const AnomalyResult({
    required this.isAnomaly,
    required this.score,
    required this.zRms,
    required this.zFlux,
    required this.zCentroid,
    required this.zZcr,
    required this.warmingUp,
    required this.baselineFrames,
    required this.features,
  });

  @override
  String toString() =>
      'AnomalyResult(isAnomaly: $isAnomaly, score: ${score.toStringAsFixed(2)}, '
      'zFlux: ${zFlux.toStringAsFixed(2)}, zRms: ${zRms.toStringAsFixed(2)})';
}

/// Anomaly Detector computing one-sided z-scores against dynamic ambient baseline.
///
/// Ported from Python detector.py.
class AnomalyDetector {
  final RollingBaseline baseline;
  final double threshold;

  AnomalyDetector({
    RollingBaseline? baseline,
    this.threshold = NightWatchConfig.anomalyThreshold,
  }) : baseline = baseline ?? RollingBaseline();

  /// Process one frame of features and determine if it represents an anomaly.
  AnomalyResult process(AudioFeatures features) {
    final warmingUp = baseline.isWarmingUp;

    // If still warming up, populate baseline and return non-anomaly
    if (warmingUp) {
      baseline.add(features);
      return AnomalyResult(
        isAnomaly: false,
        score: 0.0,
        zRms: 0.0,
        zFlux: 0.0,
        zCentroid: 0.0,
        zZcr: 0.0,
        warmingUp: true,
        baselineFrames: baseline.count,
        features: features,
      );
    }

    final rmsStats = baseline.rmsStats;
    final fluxStats = baseline.fluxStats;
    final centroidStats = baseline.centroidStats;
    final zcrStats = baseline.zcrStats;

    // One-sided z-scores (we only care when sound increases above baseline)
    final zRms = math.max(0.0, (features.rms - rmsStats.mean) / rmsStats.std);
    final zFlux = math.max(0.0, (features.spectralFlux - fluxStats.mean) / fluxStats.std);
    final zCentroid =
        math.max(0.0, (features.spectralCentroid - centroidStats.mean) / centroidStats.std);
    final zZcr = math.max(0.0, (features.zcr - zcrStats.mean) / zcrStats.std);

    // Weighted composite anomaly score
    final score = NightWatchConfig.wSpectralFlux * zFlux +
        NightWatchConfig.wRms * zRms +
        NightWatchConfig.wSpectralCentroid * zCentroid +
        NightWatchConfig.wZcr * zZcr;

    final isAnomaly = score >= threshold;

    // Only update baseline with normal background sound
    if (!isAnomaly) {
      baseline.add(features);
    }

    return AnomalyResult(
      isAnomaly: isAnomaly,
      score: score,
      zRms: zRms,
      zFlux: zFlux,
      zCentroid: zCentroid,
      zZcr: zZcr,
      warmingUp: false,
      baselineFrames: baseline.count,
      features: features,
    );
  }

  void reset() {
    baseline.clear();
  }
}
