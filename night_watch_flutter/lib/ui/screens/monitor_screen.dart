import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:night_watch_flutter/core/recorder/event_recorder.dart';
import 'package:night_watch_flutter/services/background_service.dart';
import 'package:night_watch_flutter/services/monitoring_controller.dart';
import 'package:night_watch_flutter/ui/screens/event_detail_screen.dart';
import 'package:night_watch_flutter/ui/theme/app_theme.dart';
import 'package:night_watch_flutter/ui/widgets/event_card.dart';
import 'package:night_watch_flutter/ui/widgets/live_meter.dart';
import 'package:night_watch_flutter/ui/widgets/night_clock.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  final MonitoringController _controller = MonitoringController();
  bool _isDimmed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _toggleMonitoring() async {
    if (_controller.isMonitoring) {
      await _controller.stopMonitoring();
      await BackgroundServiceManager.stopForegroundService();
    } else {
      // Request mic & notification permissions
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required for Night Watch.')),
          );
        }
        return;
      }

      await BackgroundServiceManager.startForegroundService();
      await _controller.startMonitoring();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMonitoring = _controller.isMonitoring;
    final recorderState = _controller.recorderState;

    String statusText = 'READY';
    Color statusColor = NightWatchTheme.textMuted;
    IconData statusIcon = Icons.nightlight_round;

    if (isMonitoring) {
      switch (recorderState) {
        case RecorderState.idle:
          statusText = _controller.isWarmingUp ? 'WARMING UP' : 'MONITORING';
          statusColor = _controller.isWarmingUp
              ? NightWatchTheme.accentWarming
              : NightWatchTheme.accentNormal;
          statusIcon = Icons.graphic_eq_rounded;
          break;
        case RecorderState.recording:
        case RecorderState.coolingDown:
        case RecorderState.postBuffering:
          statusText = '● RECORDING EVENT';
          statusColor = NightWatchTheme.accentAnomaly;
          statusIcon = Icons.fiber_manual_record_rounded;
          break;
        case RecorderState.mergeWindow:
          statusText = '⏳ MERGE WINDOW';
          statusColor = NightWatchTheme.accentMerge;
          statusIcon = Icons.hourglass_top_rounded;
          break;
      }
    }

    return Scaffold(
      backgroundColor: _isDimmed ? Colors.black : NightWatchTheme.background,
      appBar: AppBar(
        title: const Text('🌙 NIGHT WATCH'),
        actions: [
          IconButton(
            icon: Icon(
              _isDimmed ? Icons.brightness_medium_rounded : Icons.brightness_2_outlined,
              color: NightWatchTheme.textSecondary,
            ),
            tooltip: 'Dim Screen (AMOLED Night Mode)',
            onPressed: () => setState(() => _isDimmed = !_isDimmed),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            // Night Clock
            NightClockWidget(isDimmed: _isDimmed),

            const SizedBox(height: 20),

            // Live Status Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, color: statusColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: statusColor,
                    ),
                  ),
                  if (isMonitoring) ...[
                    const SizedBox(width: 10),
                    Text(
                      '•  ${_formatDuration(_controller.elapsed)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor.withValues(alpha: 0.8),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Live Meter
            if (isMonitoring && !_isDimmed) ...[
              LiveMeterWidget(
                score: _controller.currentScore,
                rms: _controller.currentRms,
                flux: _controller.currentFlux,
                centroid: _controller.currentCentroid,
                zcr: _controller.currentZcr,
                zRms: _controller.zRms,
                zFlux: _controller.zFlux,
                isWarmingUp: _controller.isWarmingUp,
                baselineFrames: _controller.baselineFrames,
              ),
              const SizedBox(height: 24),
            ],

            // Main Action Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _toggleMonitoring,
                icon: Icon(
                  isMonitoring ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  size: 26,
                  color: isMonitoring ? Colors.white : Colors.black,
                ),
                label: Text(
                  isMonitoring ? 'STOP MONITORING' : 'START OVERNIGHT WATCH',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isMonitoring ? Colors.white : Colors.black,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isMonitoring ? NightWatchTheme.accentAnomaly : NightWatchTheme.accentNormal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Recent Events of Current Session
            if (_controller.sessionEvents.isNotEmpty && !_isDimmed) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recorded Events (${_controller.sessionEvents.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: NightWatchTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _controller.sessionEvents.length,
                itemBuilder: (context, index) {
                  // Show in reverse chronological order
                  final event = _controller.sessionEvents[_controller.sessionEvents.length - 1 - index];
                  return EventCard(
                    event: event,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EventDetailScreen(event: event),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours.toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
