import 'package:flutter_test/flutter_test.dart';
import 'package:night_watch_flutter/core/config.dart';
import 'package:night_watch_flutter/core/detection/anomaly_detector.dart';
import 'package:night_watch_flutter/core/detection/rolling_baseline.dart';
import 'package:night_watch_flutter/core/dsp/audio_features.dart';

void main() {
  group('Baseline & Anomaly Detection Tests', () {
    test('Rolling baseline respects capacity and standard deviation floors', () {
      final baseline = RollingBaseline(maxFrames: 5);

      // Add identical frames (variance = 0)
      for (int i = 0; i < 5; i++) {
        baseline.add(AudioFeatures(
          rms: 0.001,
          spectralFlux: 0.1,
          spectralCentroid: 1000.0,
          zcr: 0.05,
          timestamp: DateTime.now(),
        ));
      }

      expect(baseline.count, equals(5));

      // Std should be at least min floor
      expect(baseline.rmsStats.std, greaterThanOrEqualTo(NightWatchConfig.minStdRms));
      expect(baseline.fluxStats.std, greaterThanOrEqualTo(NightWatchConfig.minStdSpectralFlux));
      expect(baseline.centroidStats.std, greaterThanOrEqualTo(NightWatchConfig.minStdCentroidDelta));
      expect(baseline.zcrStats.std, greaterThanOrEqualTo(NightWatchConfig.minStdZcr));
    });

    test('Anomaly detector flags sudden sound spike after warmup', () {
      final detector = AnomalyDetector();

      // Warm up with quiet room baseline (15 frames)
      for (int i = 0; i < 15; i++) {
        final result = detector.process(AudioFeatures(
          rms: 0.0005,
          spectralFlux: 0.1,
          spectralCentroid: 1200.0,
          zcr: 0.05,
          timestamp: DateTime.now(),
        ));
        if (i < 10) {
          expect(result.warmingUp, isTrue);
        } else {
          expect(result.warmingUp, isFalse);
          expect(result.isAnomaly, isFalse);
        }
      }

      // Loud sudden talking or impact sound (high RMS and high flux)
      final loudResult = detector.process(AudioFeatures(
        rms: 0.05, // 100x baseline
        spectralFlux: 0.8, // 8x baseline
        spectralCentroid: 2500.0,
        zcr: 0.15,
        timestamp: DateTime.now(),
      ));

      expect(loudResult.isAnomaly, isTrue);
      expect(loudResult.score, greaterThan(NightWatchConfig.anomalyThreshold));
    });
  });
}
