import 'package:flutter/material.dart';
import 'package:night_watch_flutter/core/config.dart';
import 'package:night_watch_flutter/ui/theme/app_theme.dart';

class LiveMeterWidget extends StatelessWidget {
  final double score;
  final double rms;
  final double flux;
  final double centroid;
  final double zcr;
  final double zRms;
  final double zFlux;
  final bool isWarmingUp;
  final int baselineFrames;

  const LiveMeterWidget({
    super.key,
    required this.score,
    required this.rms,
    required this.flux,
    required this.centroid,
    required this.zcr,
    required this.zRms,
    required this.zFlux,
    required this.isWarmingUp,
    required this.baselineFrames,
  });

  @override
  Widget build(BuildContext context) {
    final isAnomaly = score >= NightWatchConfig.anomalyThreshold;
    final scoreRatio = (score / 10.0).clamp(0.0, 1.0);

    Color scoreColor = NightWatchTheme.accentNormal;
    if (score >= NightWatchConfig.anomalyThreshold) {
      scoreColor = NightWatchTheme.accentAnomaly;
    } else if (score >= 1.5) {
      scoreColor = NightWatchTheme.accentWarming;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: NightWatchTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAnomaly
              ? NightWatchTheme.accentAnomaly.withValues(alpha: 0.5)
              : NightWatchTheme.surfaceBorder,
          width: isAnomaly ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Anomaly Score & Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isWarmingUp ? NightWatchTheme.accentWarming : scoreColor,
                      boxShadow: [
                        BoxShadow(
                          color: (isWarmingUp ? NightWatchTheme.accentWarming : scoreColor)
                              .withValues(alpha: 0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isWarmingUp
                        ? 'WARMING UP ($baselineFrames/120)'
                        : (isAnomaly ? 'ANOMALY DETECTED' : 'NORMAL AMBIENT'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: isWarmingUp
                          ? NightWatchTheme.accentWarming
                          : (isAnomaly ? NightWatchTheme.accentAnomaly : NightWatchTheme.accentNormal),
                    ),
                  ),
                ],
              ),
              Text(
                'Score: ${score.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Anomaly Score Bar with Threshold Marker
          Stack(
            children: [
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: NightWatchTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: scoreRatio,
                  child: Container(
                    decoration: BoxDecoration(
                      color: scoreColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              // Threshold tick marker (3.0 on 0-10 scale = 30%)
              Positioned(
                left: MediaQuery.of(context).size.width * 0.3 * 0.82, // normalized
                top: 0,
                bottom: 0,
                child: Container(
                  width: 2,
                  color: Colors.white70,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          const Divider(color: NightWatchTheme.surfaceBorder, height: 1),
          const SizedBox(height: 14),

          // 4 Acoustic Features Grid
          Row(
            children: [
              Expanded(
                child: _FeatureTile(
                  label: 'RMS Energy',
                  value: rms.toStringAsFixed(5),
                  zScore: 'z=${zRms.toStringAsFixed(1)}',
                  ratio: (rms / NightWatchConfig.displayRmsMax).clamp(0.0, 1.0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FeatureTile(
                  label: 'Spec. Flux',
                  value: flux.toStringAsFixed(3),
                  zScore: 'z=${zFlux.toStringAsFixed(1)}',
                  ratio: (flux / NightWatchConfig.displayFluxMax).clamp(0.0, 1.0),
                  highlight: flux > 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _FeatureTile(
                  label: 'Centroid',
                  value: '${centroid.toStringAsFixed(0)} Hz',
                  ratio: (centroid / NightWatchConfig.displayCentroidMax).clamp(0.0, 1.0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FeatureTile(
                  label: 'ZCR',
                  value: zcr.toStringAsFixed(3),
                  ratio: (zcr / NightWatchConfig.displayZcrMax).clamp(0.0, 1.0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final String label;
  final String value;
  final String? zScore;
  final double ratio;
  final bool highlight;

  const _FeatureTile({
    required this.label,
    required this.value,
    this.zScore,
    required this.ratio,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: NightWatchTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: NightWatchTheme.textMuted),
              ),
              if (zScore != null)
                Text(
                  zScore!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: highlight ? NightWatchTheme.accentAnomaly : NightWatchTheme.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: NightWatchTheme.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 3,
              backgroundColor: NightWatchTheme.surfaceBorder,
              valueColor: AlwaysStoppedAnimation<Color>(
                highlight ? NightWatchTheme.accentAnomaly : NightWatchTheme.accentSpeech,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
