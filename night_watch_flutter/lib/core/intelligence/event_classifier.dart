import 'package:night_watch_flutter/core/dsp/audio_features.dart';

class ClassificationResult {
  final String tag;
  final double confidence;
  final String description;

  const ClassificationResult({
    required this.tag,
    required this.confidence,
    required this.description,
  });
}

/// Lightweight acoustic event classifier using spectral heuristics (Phase 7).
///
/// Tags events without sending audio to the cloud:
///   - Speech / Voice
///   - Movement / Bed Rustle
///   - Impact / Knock / Door
///   - Snoring / Heavy Breathing
///   - Ambient Acoustic Anomaly
class EventClassifier {
  static ClassificationResult classify({
    required AudioFeatures peakFeatures,
    required double peakScore,
    required double durationSeconds,
  }) {
    final rms = peakFeatures.rms;
    final flux = peakFeatures.spectralFlux;
    final centroid = peakFeatures.spectralCentroid;
    final zcr = peakFeatures.zcr;

    // 1. Speech / Talking
    // Human speech has harmonic formant structure -> moderate ZCR (0.04 - 0.22)
    // and prominent spectral flux (> 0.45) with centroid around 800Hz - 3500Hz
    if (zcr >= 0.04 && zcr <= 0.22 && flux >= 0.45 && centroid >= 800 && centroid <= 3500) {
      final conf = (0.75 + (flux - 0.45) * 0.3).clamp(0.6, 0.95);
      return ClassificationResult(
        tag: 'Speech / Voice',
        confidence: double.parse(conf.toStringAsFixed(2)),
        description: 'Vocal sounds or speech detected with formant characteristics',
      );
    }

    // 2. Impact / Knock / Slam / Door
    // Sharp transients with very high flux and high peak score, typically short duration
    if (peakScore >= 6.0 && flux >= 0.70 && durationSeconds <= 12.0) {
      final conf = (0.70 + (peakScore / 20.0) * 0.25).clamp(0.65, 0.95);
      return ClassificationResult(
        tag: 'Impact / Transient',
        confidence: double.parse(conf.toStringAsFixed(2)),
        description: 'Sharp impact, door slam, or sudden transient sound',
      );
    }

    // 3. Movement / Rustle / Blanket
    // Bed movement, sheets, or rolling over has low centroid and lower ZCR
    if (centroid < 1400 && zcr < 0.06 && flux < 0.6) {
      final conf = 0.72;
      return ClassificationResult(
        tag: 'Movement / Rustle',
        confidence: conf,
        description: 'Low-frequency mechanical sound, sheet rustling, or bed movement',
      );
    }

    // 4. Snoring / Periodic Breathing
    // Low centroid (< 900 Hz), very low ZCR (< 0.04), moderate energy
    if (centroid < 900 && zcr < 0.04 && rms > 0.005) {
      return const ClassificationResult(
        tag: 'Breathing / Snore',
        confidence: 0.70,
        description: 'Low-frequency respiratory sound or periodic breathing',
      );
    }

    // 5. General Anomaly
    return ClassificationResult(
      tag: 'Acoustic Anomaly',
      confidence: 0.60,
      description: 'Unusual acoustic event exceeding ambient room baseline',
    );
  }
}
