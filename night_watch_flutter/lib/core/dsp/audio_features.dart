/// Holds the 4 acoustic features computed from one audio frame.
class AudioFeatures {
  final double rms;
  final double spectralFlux;
  final double spectralCentroid;
  final double zcr;
  final DateTime timestamp;

  const AudioFeatures({
    required this.rms,
    required this.spectralFlux,
    required this.spectralCentroid,
    required this.zcr,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        'rms': rms,
        'spectral_flux': spectralFlux,
        'spectral_centroid': spectralCentroid,
        'zcr': zcr,
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  String toString() =>
      'AudioFeatures(rms: ${rms.toStringAsFixed(5)}, '
      'flux: ${spectralFlux.toStringAsFixed(4)}, '
      'centroid: ${spectralCentroid.toStringAsFixed(0)} Hz, '
      'zcr: ${zcr.toStringAsFixed(4)})';
}
