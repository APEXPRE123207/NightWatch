class RecordedEvent {
  final int? id;
  final int sessionId;
  final int eventNumber;
  final DateTime startTime;
  final DateTime endTime;
  final double durationSeconds;
  final double peakScore;
  final String clipPath;
  final String tag;
  final double confidence;
  final bool isFavorite;
  final String? note;

  const RecordedEvent({
    this.id,
    required this.sessionId,
    required this.eventNumber,
    required this.startTime,
    required this.endTime,
    required this.durationSeconds,
    required this.peakScore,
    required this.clipPath,
    this.tag = 'Unclassified',
    this.confidence = 1.0,
    this.isFavorite = false,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'event_number': eventNumber,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'duration_seconds': durationSeconds,
        'peak_score': peakScore,
        'clip_path': clipPath,
        'tag': tag,
        'confidence': confidence,
        'is_favorite': isFavorite ? 1 : 0,
        'note': note,
      };

  factory RecordedEvent.fromMap(Map<String, dynamic> map) => RecordedEvent(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        eventNumber: (map['event_number'] as int?) ?? 1,
        startTime: DateTime.parse(map['start_time'] as String),
        endTime: DateTime.parse(map['end_time'] as String),
        durationSeconds: (map['duration_seconds'] as num).toDouble(),
        peakScore: (map['peak_score'] as num).toDouble(),
        clipPath: map['clip_path'] as String,
        tag: (map['tag'] as String?) ?? 'Unclassified',
        confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
        isFavorite: (map['is_favorite'] as int?) == 1,
        note: map['note'] as String?,
      );

  RecordedEvent copyWith({
    int? id,
    int? sessionId,
    int? eventNumber,
    DateTime? startTime,
    DateTime? endTime,
    double? durationSeconds,
    double? peakScore,
    String? clipPath,
    String? tag,
    double? confidence,
    bool? isFavorite,
    String? note,
  }) =>
      RecordedEvent(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        eventNumber: eventNumber ?? this.eventNumber,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        peakScore: peakScore ?? this.peakScore,
        clipPath: clipPath ?? this.clipPath,
        tag: tag ?? this.tag,
        confidence: confidence ?? this.confidence,
        isFavorite: isFavorite ?? this.isFavorite,
        note: note ?? this.note,
      );
}
