import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:night_watch_flutter/models/event_model.dart';
import 'package:night_watch_flutter/services/monitoring_controller.dart';
import 'package:night_watch_flutter/ui/theme/app_theme.dart';
import 'package:night_watch_flutter/ui/widgets/waveform_view.dart';

class EventDetailScreen extends StatefulWidget {
  final RecordedEvent event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  final AudioPlayer _player = AudioPlayer();
  late RecordedEvent _event;

  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _initAudio();
  }

  Future<void> _initAudio() async {
    _duration = Duration(milliseconds: (_event.durationSeconds * 1000).round());

    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });

    await _player.setSourceDeviceFile(_event.clipPath);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.resume();
    }
  }

  void _onSeek(double ratio) {
    if (_duration > Duration.zero) {
      final targetMs = (_duration.inMilliseconds * ratio).round();
      _player.seek(Duration(milliseconds: targetMs));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final startTimeStr = DateFormat('hh:mm:ss a • EEE, MMM d').format(_event.startTime);

    return Scaffold(
      appBar: AppBar(
        title: Text('Event #${_event.eventNumber}'),
        actions: [
          IconButton(
            icon: Icon(
              _event.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: _event.isFavorite ? Colors.amber : NightWatchTheme.textMuted,
            ),
            onPressed: () async {
              final newFav = !_event.isFavorite;
              await MonitoringController().toggleFavorite(_event.id!, newFav);
              setState(() {
                _event = _event.copyWith(isFavorite: newFav);
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: NightWatchTheme.accentAnomaly),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Info Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: NightWatchTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NightWatchTheme.surfaceBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        startTimeStr,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: NightWatchTheme.textPrimary,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: NightWatchTheme.accentSpeech.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _event.tag,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: NightWatchTheme.accentSpeech,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatBadge(
                        label: 'Duration',
                        value: '${_event.durationSeconds.toStringAsFixed(1)}s',
                        icon: Icons.timer_outlined,
                      ),
                      const SizedBox(width: 12),
                      _StatBadge(
                        label: 'Peak Score',
                        value: _event.peakScore.toStringAsFixed(1),
                        icon: Icons.bolt_rounded,
                        color: _event.peakScore >= 8.0
                            ? NightWatchTheme.accentAnomaly
                            : NightWatchTheme.accentWarming,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Waveform & Visualizer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: NightWatchTheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: NightWatchTheme.surfaceBorder),
              ),
              child: Column(
                children: [
                  WaveformView(
                    clipPath: _event.clipPath,
                    playbackProgress: progress,
                    onSeek: _onSeek,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: const TextStyle(
                          fontSize: 13,
                          color: NightWatchTheme.textSecondary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: const TextStyle(
                          fontSize: 13,
                          color: NightWatchTheme.textMuted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Playback Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_5_rounded, size: 28),
                        color: NightWatchTheme.textSecondary,
                        onPressed: () {
                          final newPos = _position - const Duration(seconds: 5);
                          _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
                        },
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _togglePlayPause,
                        style: ElevatedButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(18),
                          backgroundColor: NightWatchTheme.accentSpeech,
                        ),
                        child: Icon(
                          _playerState == PlayerState.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 32,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.forward_5_rounded, size: 28),
                        color: NightWatchTheme.textSecondary,
                        onPressed: () {
                          final newPos = _position + const Duration(seconds: 5);
                          _player.seek(newPos > _duration ? _duration : newPos);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Tag Editor Section
            const Text(
              'Classification Tag',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: NightWatchTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'Speech / Voice',
                'Movement / Rustle',
                'Impact / Transient',
                'Breathing / Snore',
                'Acoustic Anomaly',
              ].map((t) {
                final isSelected = _event.tag == t;
                return ChoiceChip(
                  label: Text(t),
                  selected: isSelected,
                  selectedColor: NightWatchTheme.accentSpeech.withValues(alpha: 0.2),
                  backgroundColor: NightWatchTheme.surface,
                  labelStyle: TextStyle(
                    color: isSelected ? NightWatchTheme.accentSpeech : NightWatchTheme.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (selected) async {
                    if (selected) {
                      await MonitoringController().updateEventTag(_event.id!, t);
                      setState(() {
                        _event = _event.copyWith(tag: t);
                      });
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NightWatchTheme.surface,
        title: const Text('Delete Event Recording?'),
        content: const Text('This will delete the audio file and database record permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: NightWatchTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await MonitoringController().deleteEvent(_event.id!);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: NightWatchTheme.accentAnomaly)),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const _StatBadge({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? NightWatchTheme.textPrimary;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: NightWatchTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: c),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: NightWatchTheme.textMuted)),
                Text(
                  value,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
