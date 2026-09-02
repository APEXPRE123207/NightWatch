class NightSession {
  final int? id;
  final DateTime startTime;
  final DateTime? endTime;
  final int durationSeconds;
  final int eventCount;
  final String? note;

  const NightSession({
    this.id,
    required this.startTime,
    this.endTime,
    this.durationSeconds = 0,
    this.eventCount = 0,
    this.note,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime?.toIso8601String(),
        'duration_seconds': durationSeconds,
        'event_count': eventCount,
        'note': note,
      };

  factory NightSession.fromMap(Map<String, dynamic> map) => NightSession(
        id: map['id'] as int?,
        startTime: DateTime.parse(map['start_time'] as String),
        endTime: map['end_time'] != null ? DateTime.parse(map['end_time'] as String) : null,
        durationSeconds: (map['duration_seconds'] as int?) ?? 0,
        eventCount: (map['event_count'] as int?) ?? 0,
        note: map['note'] as String?,
      );

  NightSession copyWith({
    int? id,
    DateTime? startTime,
    DateTime? endTime,
    int? durationSeconds,
    int? eventCount,
    String? note,
  }) =>
      NightSession(
        id: id ?? this.id,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        eventCount: eventCount ?? this.eventCount,
        note: note ?? this.note,
      );
}
