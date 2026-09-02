import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:night_watch_flutter/ui/theme/app_theme.dart';

class WaveformView extends StatefulWidget {
  final String clipPath;
  final double playbackProgress; // 0.0 to 1.0
  final ValueChanged<double>? onSeek;

  const WaveformView({
    super.key,
    required this.clipPath,
    this.playbackProgress = 0.0,
    this.onSeek,
  });

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView> {
  List<double> _amplitudes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  @override
  void didUpdateWidget(covariant WaveformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clipPath != widget.clipPath) {
      _loadWaveform();
    }
  }

  Future<void> _loadWaveform() async {
    try {
      final file = File(widget.clipPath);
      if (!await file.exists()) {
        setState(() {
          _amplitudes = List.filled(60, 0.1);
          _isLoading = false;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      if (bytes.length <= 44) {
        setState(() {
          _amplitudes = List.filled(60, 0.1);
          _isLoading = false;
        });
        return;
      }

      // Read 16-bit PCM data after 44-byte header
      final pcmBytes = bytes.sublist(44);
      final int16Data = pcmBytes.buffer.asInt16List(pcmBytes.offsetInBytes, pcmBytes.lengthInBytes ~/ 2);

      const targetBars = 64;
      final step = math.max(1, int16Data.length ~/ targetBars);
      final peaks = <double>[];

      for (int i = 0; i < int16Data.length && peaks.length < targetBars; i += step) {
        double maxVal = 0.0;
        final end = math.min(i + step, int16Data.length);
        for (int j = i; j < end; j++) {
          final absVal = int16Data[j].abs() / 32768.0;
          if (absVal > maxVal) maxVal = absVal;
        }
        peaks.add(maxVal.clamp(0.05, 1.0));
      }

      if (mounted) {
        setState(() {
          _amplitudes = peaks;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _amplitudes = List.filled(60, 0.1);
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: NightWatchTheme.accentSpeech),
        ),
      );
    }

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final localX = details.localPosition.dx;
          final ratio = (localX / box.size.width).clamp(0.0, 1.0);
          widget.onSeek?.call(ratio);
        }
      },
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final localX = details.localPosition.dx;
          final ratio = (localX / box.size.width).clamp(0.0, 1.0);
          widget.onSeek?.call(ratio);
        }
      },
      child: CustomPaint(
        size: const Size(double.infinity, 90),
        painter: _WaveformPainter(
          amplitudes: _amplitudes,
          progress: widget.playbackProgress,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final double progress;

  _WaveformPainter({required this.amplitudes, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final barWidth = size.width / amplitudes.length;
    final centerY = size.height / 2;

    final playedPaint = Paint()
      ..color = NightWatchTheme.accentSpeech
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.0, barWidth * 0.6);

    final unplayedPaint = Paint()
      ..color = NightWatchTheme.surfaceBorder
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(2.0, barWidth * 0.6);

    final progressX = progress * size.width;

    for (int i = 0; i < amplitudes.length; i++) {
      final x = i * barWidth + barWidth / 2;
      final barHeight = amplitudes[i] * (size.height * 0.85);
      final paint = x <= progressX ? playedPaint : unplayedPaint;

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }

    // Playhead Line
    final playheadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(Offset(progressX, 0), Offset(progressX, size.height), playheadPaint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.amplitudes != amplitudes;
  }
}
