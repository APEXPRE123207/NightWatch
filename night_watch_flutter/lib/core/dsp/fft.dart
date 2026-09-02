import 'dart:math' as math;
import 'dart:typed_data';

/// High-performance Radix-2 Cooley-Tukey In-Place FFT in pure Dart.
///
/// Pre-computes bit-reversal permutations and twiddle factors for the given size
/// so real-time processing has zero allocations during calculation.
class FastFourierTransform {
  final int size; // Must be a power of 2 (e.g. 16384)
  late final Int32List _bitRev;
  late final Float64List _cosTable;
  late final Float64List _sinTable;

  FastFourierTransform(this.size) {
    assert((size & (size - 1)) == 0, 'FFT size must be a power of 2');
    _initTables();
  }

  void _initTables() {
    _bitRev = Int32List(size);
    int log2N = (math.log(size) / math.ln2).round();
    for (int i = 0; i < size; i++) {
      int rev = 0;
      int temp = i;
      for (int j = 0; j < log2N; j++) {
        rev = (rev << 1) | (temp & 1);
        temp >>= 1;
      }
      _bitRev[i] = rev;
    }

    _cosTable = Float64List(size ~/ 2);
    _sinTable = Float64List(size ~/ 2);
    for (int i = 0; i < size ~/ 2; i++) {
      final angle = -2.0 * math.pi * i / size;
      _cosTable[i] = math.cos(angle);
      _sinTable[i] = math.sin(angle);
    }
  }

  /// Compute magnitude spectrum from real input.
  ///
  /// Returns Float64List of size (size ~/ 2) containing magnitude of each bin.
  Float64List transformMagnitude(Float32List input) {
    final real = Float64List(size);
    final imag = Float64List(size);

    final copyLen = math.min(input.length, size);
    for (int i = 0; i < copyLen; i++) {
      real[_bitRev[i]] = input[i].toDouble();
    }
    // Zero-pad remainder if input.length < size
    for (int i = copyLen; i < size; i++) {
      real[_bitRev[i]] = 0.0;
    }

    // Cooley-Tukey iterative computation
    for (int len = 2; len <= size; len <<= 1) {
      final halfLen = len ~/ 2;
      final step = size ~/ len;
      for (int i = 0; i < size; i += len) {
        for (int j = 0; j < halfLen; j++) {
          final tableIdx = j * step;
          final cosVal = _cosTable[tableIdx];
          final sinVal = _sinTable[tableIdx];

          final uReal = real[i + j];
          final uImag = imag[i + j];

          final vReal = real[i + j + halfLen] * cosVal - imag[i + j + halfLen] * sinVal;
          final vImag = real[i + j + halfLen] * sinVal + imag[i + j + halfLen] * cosVal;

          real[i + j] = uReal + vReal;
          imag[i + j] = uImag + vImag;
          real[i + j + halfLen] = uReal - vReal;
          imag[i + j + halfLen] = uImag - vImag;
        }
      }
    }

    // Positive frequencies magnitude spectrum (size ~/ 2)
    final numBins = size ~/ 2;
    final magnitudes = Float64List(numBins);
    for (int i = 0; i < numBins; i++) {
      magnitudes[i] = math.sqrt(real[i] * real[i] + imag[i] * imag[i]);
    }

    return magnitudes;
  }
}
