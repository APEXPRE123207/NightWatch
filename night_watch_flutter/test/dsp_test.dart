import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_watch_flutter/core/dsp/fft.dart';
import 'package:night_watch_flutter/core/dsp/feature_extractor.dart';

void main() {
  group('DSP & Feature Extraction Tests', () {
    test('FFT detects dominant sine wave frequency', () {
      const sampleRate = 16000;
      const fftSize = 1024;
      const freq = 1000.0; // 1000 Hz

      final input = Float32List(fftSize);
      for (int i = 0; i < fftSize; i++) {
        input[i] = math.sin(2 * math.pi * freq * i / sampleRate);
      }

      final fft = FastFourierTransform(fftSize);
      final magnitudes = fft.transformMagnitude(input);

      // Find peak bin
      int peakBin = 0;
      double maxMag = 0.0;
      for (int i = 0; i < magnitudes.length; i++) {
        if (magnitudes[i] > maxMag) {
          maxMag = magnitudes[i];
          peakBin = i;
        }
      }

      final detectedFreq = (peakBin * sampleRate) / fftSize;
      expect((detectedFreq - freq).abs(), lessThanOrEqualTo(sampleRate / fftSize));
    });

    test('RMS and ZCR calculation on synthetic signals', () {
      final extractor = FeatureExtractor(sampleRate: 16000, frameSize: 16000);

      // 1. DC signal (amplitude 0.5)
      final dc = Float32List(16000)..fillRange(0, 16000, 0.5);
      final dcFeatures = extractor.extract(dc);
      expect(dcFeatures.rms, closeTo(0.5, 0.001));
      expect(dcFeatures.zcr, equals(0.0));

      // 2. High frequency square wave (alternating +1, -1) -> maximum ZCR = 1.0
      final square = Float32List(16000);
      for (int i = 0; i < 16000; i++) {
        square[i] = (i % 2 == 0) ? 1.0 : -1.0;
      }
      final sqFeatures = extractor.extract(square);
      expect(sqFeatures.rms, closeTo(1.0, 0.001));
      expect(sqFeatures.zcr, equals(1.0));
    });

    test('Spectral flux is zero on static signal and high on onset', () {
      final extractor = FeatureExtractor(sampleRate: 16000, frameSize: 16000);

      final sine = Float32List(16000);
      for (int i = 0; i < 16000; i++) {
        sine[i] = 0.5 * math.sin(2 * math.pi * 440 * i / 16000);
      }

      // First frame sets baseline
      final f1 = extractor.extract(sine);
      expect(f1.spectralFlux, equals(0.0));

      // Second identical frame has 0 flux
      final f2 = extractor.extract(sine);
      expect(f2.spectralFlux, closeTo(0.0, 0.001));

      // Third frame with different frequency (onset/transient) has high flux
      final sineHigh = Float32List(16000);
      for (int i = 0; i < 16000; i++) {
        sineHigh[i] = 0.5 * math.sin(2 * math.pi * 2000 * i / 16000);
      }
      final f3 = extractor.extract(sineHigh);
      expect(f3.spectralFlux, greaterThan(0.5));
    });
  });
}
