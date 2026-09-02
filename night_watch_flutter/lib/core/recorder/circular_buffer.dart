import 'dart:math' as math;
import 'dart:typed_data';

/// Circular in-memory ring buffer holding recent raw audio samples (Float32).
///
/// Ported from Python audio_buffer.py.
class CircularAudioBuffer {
  final int capacity;
  late final Float32List _buffer;
  int _writePos = 0;
  int _count = 0;

  CircularAudioBuffer(this.capacity) {
    _buffer = Float32List(capacity);
  }

  int get length => _count;
  bool get isFull => _count >= capacity;

  /// Write new audio samples into the circular buffer.
  void write(Float32List chunk) {
    final n = chunk.length;
    if (n >= capacity) {
      // Chunk is larger than buffer: keep only the most recent 'capacity' samples
      _buffer.setRange(0, capacity, chunk, n - capacity);
      _writePos = 0;
      _count = capacity;
      return;
    }

    final spaceToEnd = capacity - _writePos;
    if (n <= spaceToEnd) {
      _buffer.setRange(_writePos, _writePos + n, chunk);
      _writePos = (_writePos + n) % capacity;
    } else {
      _buffer.setRange(_writePos, capacity, chunk.sublist(0, spaceToEnd));
      final remainder = n - spaceToEnd;
      _buffer.setRange(0, remainder, chunk.sublist(spaceToEnd));
      _writePos = remainder;
    }

    _count = math.min(capacity, _count + n);
  }

  /// Read all accumulated samples in chronological order.
  Float32List readAll() {
    if (_count == 0) return Float32List(0);

    final result = Float32List(_count);
    if (_count < capacity) {
      result.setRange(0, _count, _buffer.sublist(0, _count));
    } else {
      final tailLen = capacity - _writePos;
      result.setRange(0, tailLen, _buffer.sublist(_writePos));
      if (_writePos > 0) {
        result.setRange(tailLen, _count, _buffer.sublist(0, _writePos));
      }
    }
    return result;
  }

  void clear() {
    _writePos = 0;
    _count = 0;
  }
}
