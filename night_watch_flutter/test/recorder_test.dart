import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_watch_flutter/core/recorder/circular_buffer.dart';
import 'package:night_watch_flutter/core/recorder/wav_encoder.dart';

void main() {
  group('Recorder & Buffering Tests', () {
    test('CircularAudioBuffer wraps and maintains chronological order', () {
      final buffer = CircularAudioBuffer(5);

      // Write [1, 2, 3]
      buffer.write(Float32List.fromList([1.0, 2.0, 3.0]));
      expect(buffer.readAll(), equals(Float32List.fromList([1.0, 2.0, 3.0])));

      // Write [4, 5, 6] (overflows 5 capacity, should keep [2, 3, 4, 5, 6])
      buffer.write(Float32List.fromList([4.0, 5.0, 6.0]));
      expect(buffer.length, equals(5));
      expect(buffer.readAll(), equals(Float32List.fromList([2.0, 3.0, 4.0, 5.0, 6.0])));
    });

    test('WavEncoder produces valid 16-bit PCM WAV header and data', () {
      final samples = Float32List.fromList([0.0, 0.5, -0.5, 1.0, -1.0]);
      final wavBytes = WavEncoder.encodeToWavBytes(
        audio: samples,
        sampleRate: 16000,
        channels: 1,
      );

      // RIFF header length = 44 + (5 samples * 2 bytes) = 54 bytes
      expect(wavBytes.length, equals(44 + 10));

      final data = ByteData.view(wavBytes.buffer);

      // Check 'RIFF' signature
      expect(String.fromCharCodes(wavBytes.sublist(0, 4)), equals('RIFF'));
      // Check 'WAVE' format
      expect(String.fromCharCodes(wavBytes.sublist(8, 12)), equals('WAVE'));
      // Check 'fmt ' chunk
      expect(String.fromCharCodes(wavBytes.sublist(12, 16)), equals('fmt '));

      // AudioFormat == 1 (PCM)
      expect(data.getUint16(20, Endian.little), equals(1));
      // Channels == 1
      expect(data.getUint16(22, Endian.little), equals(1));
      // SampleRate == 16000
      expect(data.getUint32(24, Endian.little), equals(16000));
      // BitsPerSample == 16
      expect(data.getUint16(34, Endian.little), equals(16));

      // Check 'data' subchunk
      expect(String.fromCharCodes(wavBytes.sublist(36, 40)), equals('data'));
      // Data size == 10 bytes
      expect(data.getUint32(40, Endian.little), equals(10));

      // Check sample clamping & scaling
      // 0.0 -> 0
      expect(data.getInt16(44, Endian.little), equals(0));
      // 0.5 -> ~16384
      expect(data.getInt16(46, Endian.little), closeTo(16384, 10));
      // -0.5 -> ~-16384
      expect(data.getInt16(48, Endian.little), closeTo(-16384, 10));
      // 1.0 -> 32767
      expect(data.getInt16(50, Endian.little), equals(32767));
      // -1.0 -> -32767
      expect(data.getInt16(52, Endian.little), equals(-32767));
    });
  });
}
