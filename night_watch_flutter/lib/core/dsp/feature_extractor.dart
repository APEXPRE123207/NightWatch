import 'dart:math' as math;
import 'dart:typed_data';

import 'package:night_watch_flutter/core/dsp/audio_features.dart';
import 'package:night_watch_flutter/core/dsp/fft.dart';

/// Extracts 4 acoustic features from each audio frame:
///   1. RMS Energy
///   2. Spectral Flux
///   3. Spectral Centroid
///   4. Zero-Crossing Rate (ZCR)
///
/// Ported exactly from Python feature_extractor.py.
class FeatureExtractor {
  final int sampleRate;
  late final int _fftSize;
  late final FastFourierTransform _fft;
  late final Float64List _hannWindow;
  late final Float64List _frequencies;

  Float64List? _prevNormalizedSpectrum;

  FeatureExtractor({this.sampleRate = 16000, int frameSize = 16000}) {
    // Find next power of 2 for FFT
    int size = 1;
    while (size < frameSize) {
      size <<= 1;
    }
    _fftSize = size; // e.g. 16384 for 16000 frameSize
    _fft = FastFourierTransform(_fftSize);

    // Precompute Hann window
    _hannWindow = Float64List(frameSize);
    for (int i = 0; i < frameSize; i++) {
      _hannWindow[i] = 0.5 * (1.0 - math.cos(2.0 * math.pi * i / (frameSize - 1)));
    }

    // Precompute frequency bin center frequencies
    final numBins = _fftSize ~/ 2;
    _frequencies = Float64List(numBins);
    for (int i = 0; i < numBins; i++) {
      _frequencies[i] = (i * sampleRate) / _fftSize;
    }
  }

  /// Extract features from a 1.0s audio frame (16,000 float32 samples).
  AudioFeatures extract(Float32List frame, {DateTime? timestamp}) {
    timestamp ??= DateTime.now();

    final rms = _computeRms(frame);
    final zcr = _computeZcr(frame);

    // Apply Hann window and compute FFT
    final windowed = Float32List(frame.length);
    for (int i = 0; i < frame.length; i++) {
      windowed[i] = (frame[i] * _hannWindow[i]).toDouble();
    }

    final rawMagnitudes = _fft.transformMagnitude(windowed);

    final spectralCentroid = _computeCentroid(rawMagnitudes);
    final spectralFlux = _computeFlux(rawMagnitudes);

    return AudioFeatures(
      rms: rms,
      spectralFlux: spectralFlux,
      spectralCentroid: spectralCentroid,
      zcr: zcr,
      timestamp: timestamp,
    );
  }

  void reset() {
    _prevNormalizedSpectrum = null;
  }

  // ─── RMS Energy ───────────────────────────────────────────────────────────

  double _computeRms(Float32List frame) {
    if (frame.isEmpty) return 0.0;
    double sumSq = 0.0;
    for (int i = 0; i < frame.length; i++) {
      sumSq += frame[i] * frame[i];
    }
    return math.sqrt(sumSq / frame.length);
  }

  // ─── Zero-Crossing Rate ───────────────────────────────────────────────────

  double _computeZcr(Float32List frame) {
    if (frame.length < 2) return 0.0;
    int crossings = 0;
    for (int i = 1; i < frame.length; i++) {
      final sPrev = frame[i - 1] >= 0;
      final sCurr = frame[i] >= 0;
      if (sPrev != sCurr) {
        crossings++;
      }
    }
    return crossings / (frame.length - 1);
  }

  // ─── Spectral Centroid ────────────────────────────────────────────────────

  double _computeCentroid(Float64List magnitudes) {
    double weightedSum = 0.0;
    double totalEnergy = 0.0;

    for (int i = 0; i < magnitudes.length; i++) {
      final mag = magnitudes[i];
      weightedSum += _frequencies[i] * mag;
      totalEnergy += mag;
    }

    if (totalEnergy < 1e-10) return 0.0;
    return weightedSum / totalEnergy;
  }

  // ─── Spectral Flux ────────────────────────────────────────────────────────

  double _computeFlux(Float64List magnitudes) {
    // 1. Normalize current magnitude spectrum by L2 norm
    double normSq = 0.0;
    for (int i = 0; i < magnitudes.length; i++) {
      normSq += magnitudes[i] * magnitudes[i];
    }
    final norm = math.sqrt(normSq);

    final normalized = Float64List(magnitudes.length);
    if (norm > 1e-10) {
      for (int i = 0; i < magnitudes.length; i++) {
        normalized[i] = magnitudes[i] / norm;
      }
    }

    // 2. On first frame, baseline flux is 0.0
    if (_prevNormalizedSpectrum == null) {
      _prevNormalizedSpectrum = normalized;
      return 0.0;
    }

    // 3. Compute Euclidean distance between normalized spectra
    double diffSumSq = 0.0;
    for (int i = 0; i < magnitudes.length; i++) {
      final diff = normalized[i] - _prevNormalizedSpectrum![i];
      diffSumSq += diff * diff;
    }

    _prevNormalizedSpectrum = normalized;
    return math.sqrt(diffSumSq);
  }
}
