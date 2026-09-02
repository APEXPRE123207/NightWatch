import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:night_watch_flutter/models/event_model.dart';
import 'package:night_watch_flutter/models/session.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'night_watch.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start_time TEXT NOT NULL,
            end_time TEXT,
            duration_seconds INTEGER DEFAULT 0,
            event_count INTEGER DEFAULT 0,
            note TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            event_number INTEGER NOT NULL,
            start_time TEXT NOT NULL,
            end_time TEXT NOT NULL,
            duration_seconds REAL NOT NULL,
            peak_score REAL NOT NULL,
            clip_path TEXT NOT NULL,
            tag TEXT DEFAULT 'Unclassified',
            confidence REAL DEFAULT 1.0,
            is_favorite INTEGER DEFAULT 0,
            note TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('CREATE INDEX idx_events_session ON events(session_id)');
        await db.execute('CREATE INDEX idx_events_time ON events(start_time)');
      },
    );
  }

  // ─── Sessions ─────────────────────────────────────────────────────────────

  Future<int> createSession({DateTime? startTime}) async {
    final db = await database;
    final session = NightSession(startTime: startTime ?? DateTime.now());
    return await db.insert('sessions', session.toMap());
  }

  Future<void> endSession(int sessionId, {DateTime? endTime, int? durationSeconds}) async {
    final db = await database;
    final end = endTime ?? DateTime.now();
    final events = await getEventsForSession(sessionId);
    await db.update(
      'sessions',
      {
        'end_time': end.toIso8601String(),
        'duration_seconds': durationSeconds ?? 0,
        'event_count': events.length,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<NightSession>> getAllSessions() async {
    final db = await database;
    final maps = await db.query('sessions', orderBy: 'start_time DESC');
    return maps.map((m) => NightSession.fromMap(m)).toList();
  }

  Future<NightSession?> getSession(int id) async {
    final db = await database;
    final maps = await db.query('sessions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (maps.isEmpty) return null;
    return NightSession.fromMap(maps.first);
  }

  Future<void> deleteSession(int sessionId) async {
    final db = await database;
    final events = await getEventsForSession(sessionId);
    for (final e in events) {
      try {
        final file = File(e.clipPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    await db.delete('events', where: 'session_id = ?', whereArgs: [sessionId]);
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  // ─── Events ───────────────────────────────────────────────────────────────

  Future<int> insertEvent(RecordedEvent event) async {
    final db = await database;
    final eventId = await db.insert('events', event.toMap());
    // Increment session event count
    await db.rawUpdate('''
      UPDATE sessions 
      SET event_count = (SELECT COUNT(*) FROM events WHERE session_id = ?) 
      WHERE id = ?
    ''', [event.sessionId, event.sessionId]);
    return eventId;
  }

  Future<List<RecordedEvent>> getEventsForSession(int sessionId) async {
    final db = await database;
    final maps = await db.query(
      'events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'event_number ASC',
    );
    return maps.map((m) => RecordedEvent.fromMap(m)).toList();
  }

  Future<List<RecordedEvent>> getAllEvents() async {
    final db = await database;
    final maps = await db.query('events', orderBy: 'start_time DESC');
    return maps.map((m) => RecordedEvent.fromMap(m)).toList();
  }

  Future<void> updateEventTag(int eventId, String tag) async {
    final db = await database;
    await db.update('events', {'tag': tag}, where: 'id = ?', whereArgs: [eventId]);
  }

  Future<void> toggleFavorite(int eventId, bool isFavorite) async {
    final db = await database;
    await db.update(
      'events',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [eventId],
    );
  }

  Future<void> deleteEvent(int eventId) async {
    final db = await database;
    final maps = await db.query('events', where: 'id = ?', whereArgs: [eventId], limit: 1);
    if (maps.isNotEmpty) {
      final clipPath = maps.first['clip_path'] as String?;
      if (clipPath != null) {
        try {
          final file = File(clipPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
    await db.delete('events', where: 'id = ?', whereArgs: [eventId]);
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
