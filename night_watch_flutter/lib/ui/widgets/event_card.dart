import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:night_watch_flutter/models/event_model.dart';
import 'package:night_watch_flutter/ui/theme/app_theme.dart';

class EventCard extends StatelessWidget {
  final RecordedEvent event;
  final VoidCallback onTap;
  final ValueChanged<bool>? onFavoriteToggle;

  const EventCard({
    super.key,
    required this.event,
    required this.onTap,
    this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('hh:mm:ss a').format(event.startTime);
    final isHigh = event.peakScore >= 8.0;

    // Tag Color & Icon
    Color tagColor = NightWatchTheme.accentSpeech;
    IconData tagIcon = Icons.graphic_eq_rounded;

    switch (event.tag) {
      case 'Speech / Voice':
        tagColor = NightWatchTheme.accentSpeech;
        tagIcon = Icons.record_voice_over_rounded;
        break;
      case 'Movement / Rustle':
        tagColor = NightWatchTheme.accentMovement;
        tagIcon = Icons.bed_rounded;
        break;
      case 'Impact / Transient':
        tagColor = NightWatchTheme.accentAnomaly;
        tagIcon = Icons.warning_amber_rounded;
        break;
      case 'Breathing / Snore':
        tagColor = NightWatchTheme.accentWarming;
        tagIcon = Icons.air_rounded;
        break;
      default:
        tagColor = NightWatchTheme.accentNormal;
        tagIcon = Icons.volume_up_rounded;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Event Number Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tagColor.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Icon(tagIcon, color: tagColor, size: 22),
                ),
              ),

              const SizedBox(width: 14),

              // Info Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Event #${event.eventNumber}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: NightWatchTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isHigh ? NightWatchTheme.accentAnomaly : NightWatchTheme.accentWarming)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'peak ${event.peakScore.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isHigh ? NightWatchTheme.accentAnomaly : NightWatchTheme.accentWarming,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$timeStr  •  ${event.durationSeconds.toStringAsFixed(1)}s',
                      style: const TextStyle(
                        fontSize: 12,
                        color: NightWatchTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: NightWatchTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        event.tag,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tagColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Actions: Favorite & Play Arrow
              IconButton(
                icon: Icon(
                  event.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: event.isFavorite ? Colors.amber : NightWatchTheme.textMuted,
                  size: 22,
                ),
                onPressed: () => onFavoriteToggle?.call(!event.isFavorite),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: NightWatchTheme.textMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
