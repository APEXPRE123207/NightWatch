import 'dart:io';
import 'dart:typed_data';

/// Encodes Float32 audio samples into standard 16-bit PCM WAV files.
class WavEncoder {
  /// Encode Float32 audio samples [-1.0, 1.0] into a Uint8List WAV file byte buffer.
  static Uint8List encodeToWavBytes({
    required Float32List audio,
    int sampleRate = 16000,
    int channels = 1,
  }) {
    final numSamples = audio.length;
    final byteRate = sampleRate * channels * 2; // 16-bit = 2 bytes per sample
    final blockAlign = channels * 2;
    final dataSize = numSamples * 2;
    final totalSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);

    // RIFF chunk descriptor
    buffer.setUint8(0, 0x52); // 'R'
    buffer.setUint8(1, 0x49); // 'I'
    buffer.setUint8(2, 0x46); // 'F'
    buffer.setUint8(3, 0x46); // 'F'
    buffer.setUint32(4, totalSize, Endian.little);
    buffer.setUint8(8, 0x57);  // 'W'
    buffer.setUint8(9, 0x41);  // 'A'
    buffer.setUint8(10, 0x56); // 'V'
    buffer.setUint8(11, 0x45); // 'E'

    // fmt sub-chunk
    buffer.setUint8(12, 0x66); // 'f'
    buffer.setUint8(13, 0x6D); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    buffer.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    buffer.setUint16(22, channels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample (16-bit)

    // data sub-chunk
    buffer.setUint8(36, 0x64); // 'd'
    buffer.setUint8(37, 0x61); // 'a'
    buffer.setUint8(38, 0x74); // 't'
    buffer.setUint8(39, 0x61); // 'a'
    buffer.setUint32(40, dataSize, Endian.little);

    // Write PCM 16-bit samples
    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      // Clamp between -1.0 and 1.0
      double sample = audio[i];
      if (sample > 1.0) sample = 1.0;
      if (sample < -1.0) sample = -1.0;

      final int16Val = (sample * 32767.0).round().toInt();
      buffer.setInt16(offset, int16Val, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }

  /// Write Float32 audio samples directly to a .wav file.
  static Future<void> writeWavFile({
    required String filePath,
    required Float32List audio,
    int sampleRate = 16000,
    int channels = 1,
  }) async {
    final wavBytes = encodeToWavBytes(
      audio: audio,
      sampleRate: sampleRate,
      channels: channels,
    );
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(wavBytes, flush: true);
  }
}
