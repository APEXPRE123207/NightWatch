/// Night Watch — Configuration & Detection Constants
///
/// Ported from Python night_watch/config.py.
/// All tunable detection parameters live here.
abstract class NightWatchConfig {
  // ─── Audio Capture ────────────────────────────────────────────────────────
  static const int sampleRate = 16000; // 16 kHz
  static const int channels = 1; // Mono

  // ─── Framing ──────────────────────────────────────────────────────────────
  static const double frameDurationS = 1.0; // 1.0 s analysis window
  static const double hopDurationS = 0.5; // 0.5 s hop (50% overlap)
  static const int frameSize = 16000; // 16,000 samples
  static const int hopSize = 8000; // 8,000 samples

  // ─── Rolling Baseline ─────────────────────────────────────────────────────
  static const double baselineWindowS = 60.0; // 60s history
  static const int baselineMaxFrames = 120; // 60s / 0.5s = 120 frames

  // ─── Anomaly Score Weights ────────────────────────────────────────────────
  // Spec §3.4: Flux is weighted 2x — key discriminator for onset/transients.
  static const double wRms = 1.0;
  static const double wSpectralFlux = 2.0;
  static const double wSpectralCentroid = 0.5;
  static const double wZcr = 0.5;

  // ─── Minimum Standard Deviation Floors ────────────────────────────────────
  // Prevents tiny baseline stds in quiet rooms from inflating z-scores.
  static const double minStdRms = 0.001;
  static const double minStdSpectralFlux = 0.02;
  static const double minStdCentroidDelta = 150.0; // Hz
  static const double minStdZcr = 0.01;

  // ─── Trigger Thresholds ───────────────────────────────────────────────────
  static const double anomalyThreshold = 3.0; // Combined z-score threshold
  static const int triggerConsecutive = 2; // Consecutive frames to start event
  static const double cooldownS = 2.0; // Cooldown silence before ending
  static const int cooldownFrames = 4; // 2.0s / 0.5s = 4 frames

  // ─── Buffering ────────────────────────────────────────────────────────────
  static const double preBufferS = 5.0; // Pre-event circular buffer
  static const double postBufferS = 3.0; // Post-event audio appended
  static const double mergeGapS = 5.0; // Merge window between close events

  // ─── Display Scaling ──────────────────────────────────────────────────────
  static const double displayRmsMax = 0.25;
  static const double displayFluxMax = 1.0;
  static const double displayCentroidMax = 6000.0; // Hz
  static const double displayZcrMax = 0.5;
}
