import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:night_watch_flutter/ui/theme/app_theme.dart';

class NightClockWidget extends StatefulWidget {
  final bool isDimmed;

  const NightClockWidget({super.key, this.isDimmed = false});

  @override
  State<NightClockWidget> createState() => _NightClockWidgetState();
}

class _NightClockWidgetState extends State<NightClockWidget> {
  late Timer _timer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('hh:mm').format(_now);
    final amPm = DateFormat('a').format(_now);
    final dateStr = DateFormat('EEE, MMM d').format(_now);

    final opacity = widget.isDimmed ? 0.35 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w200,
                  letterSpacing: -1.5,
                  color: NightWatchTheme.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                amPm,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: NightWatchTheme.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: NightWatchTheme.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
