import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../services/video_clip_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('bantay_drive.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return await openDatabase(
      path,
      version: 4,
      onCreate: _createTables,
      onUpgrade: _migrateDB,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at    TEXT NOT NULL,
        ended_at      TEXT,
        duration_sec  INTEGER DEFAULT 0,
        alertness_avg REAL DEFAULT 0.0,
        safety_score  REAL DEFAULT 0.0,
        notes         TEXT,
        trip_label    TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE state_counts (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id       INTEGER NOT NULL,
        neutral_count    INTEGER DEFAULT 0,
        drowsy_count     INTEGER DEFAULT 0,
        distracted_count INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE alert_events (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id   INTEGER NOT NULL,
        alert_type   TEXT NOT NULL,
        alert_level  INTEGER NOT NULL,
        triggered_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE system_logs (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        log_time   TEXT NOT NULL,
        message    TEXT NOT NULL,
        log_type   TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE alertness_snapshots (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id    INTEGER NOT NULL,
        recorded_at   TEXT NOT NULL,
        alertness_pct REAL NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE video_clips (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id   INTEGER NOT NULL,
        file_path    TEXT NOT NULL,
        alert_types  TEXT NOT NULL DEFAULT '',
        created_at   TEXT NOT NULL,
        duration_sec INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_sessions_started ON sessions(started_at)');
    await db.execute(
        'CREATE INDEX idx_alerts_triggered ON alert_events(triggered_at)');
  }

  Future<void> _migrateDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE sessions ADD COLUMN trip_label TEXT");
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
            'CREATE INDEX idx_sessions_started ON sessions(started_at)');
      } catch (_) {}
      try {
        await db.execute(
            'CREATE INDEX idx_alerts_triggered ON alert_events(triggered_at)');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS video_clips (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id   INTEGER NOT NULL,
            file_path    TEXT NOT NULL,
            alert_types  TEXT NOT NULL DEFAULT '',
            created_at   TEXT NOT NULL,
            duration_sec INTEGER DEFAULT 0,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');
      } catch (_) {}
    }
  }

  // Returns an ISO-8601 UTC timestamp [days] ago.
  String _sinceIso(int days) =>
      DateTime.now().subtract(Duration(days: days)).toUtc().toIso8601String();

  // ── SESSIONS ──────────────────────────────────────────────────────────────

  Future<int> insertSession() async {
    final db = await database;
    return await db.insert('sessions', {
      'started_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> endSession({
    required int sessionId,
    required int durationSec,
    required double alertnessAvg,
    required double safetyScore,
  }) async {
    final db = await database;
    await db.update(
      'sessions',
      {
        'ended_at':      DateTime.now().toUtc().toIso8601String(),
        'duration_sec':  durationSec,
        'alertness_avg': alertnessAvg,
        'safety_score':  safetyScore.clamp(0.0, 100.0),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final db = await database;
    return await db.query('sessions', orderBy: 'started_at DESC');
  }

  Future<Map<String, dynamic>?> getSessionById(int sessionId) async {
    final db = await database;
    final result = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> getTotalDriveTimeSec({int? days}) async {
    final db = await database;
    final where = 'ended_at IS NOT NULL'
        '${days != null ? ' AND started_at >= ?' : ''}';
    final args = days != null ? [_sinceIso(days)] : <dynamic>[];
    final result = await db.rawQuery(
        'SELECT SUM(duration_sec) as total FROM sessions WHERE $where', args);
    return (result.first['total'] as int?) ?? 0;
  }

  // Returns 100.0 (perfect) when no sessions exist yet.
  Future<double> getAvgSafetyScore({int? days}) async {
    final db = await database;
    final where = 'ended_at IS NOT NULL'
        '${days != null ? ' AND started_at >= ?' : ''}';
    final args = days != null ? [_sinceIso(days)] : <dynamic>[];
    final result = await db.rawQuery(
        'SELECT AVG(safety_score) as avg FROM sessions WHERE $where', args);
    return (result.first['avg'] as double?) ?? 100.0;
  }

  Future<double> getAvgAlertness({int? days}) async {
    final db = await database;
    final where = 'ended_at IS NOT NULL'
        '${days != null ? ' AND started_at >= ?' : ''}';
    final args = days != null ? [_sinceIso(days)] : <dynamic>[];
    final result = await db.rawQuery(
        'SELECT AVG(alertness_avg) as avg FROM sessions WHERE $where', args);
    return (result.first['avg'] as double?) ?? 100.0;
  }

  // Returns 0 if no sessions exist (no driving history = no streak).
  Future<int> getSafetyStreakDays() async {
    final db = await database;
    final sessionCheck = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM sessions WHERE ended_at IS NOT NULL',
    );
    if ((sessionCheck.first['cnt'] as int?) == 0) return 0;

    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 365))
        .toIso8601String();

    final result = await db.rawQuery('''
      SELECT DISTINCT DATE(s.started_at) as day
      FROM alert_events ae
      JOIN sessions s ON ae.session_id = s.id
      WHERE s.started_at >= ?
      ORDER BY day DESC
    ''', [since]);

    final alertDays = result.map((r) => r['day'] as String).toSet();

    int streak = 0;
    DateTime day = DateTime.now().toUtc();
    for (int i = 0; i < 365; i++) {
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      if (alertDays.contains(key)) break;
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<int> getTotalSessionCount({int? days}) async {
    final db = await database;
    final where = 'ended_at IS NOT NULL'
        '${days != null ? ' AND started_at >= ?' : ''}';
    final args = days != null ? [_sinceIso(days)] : <dynamic>[];
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM sessions WHERE $where', args);
    return (result.first['cnt'] as int?) ?? 0;
  }

  // ── STATE COUNTS ──────────────────────────────────────────────────────────

  Future<void> insertStateCount(int sessionId) async {
    final db = await database;
    await db.insert('state_counts', {
      'session_id':       sessionId,
      'neutral_count':    0,
      'drowsy_count':     0,
      'distracted_count': 0,
    });
  }

  Future<void> incrementStateCount({
    required int sessionId,
    required String state,
  }) async {
    const validStates = {'neutral', 'drowsy', 'distracted'};
    final normalizedState = state.toLowerCase();
    if (!validStates.contains(normalizedState)) return;

    final db = await database;
    final column = '${normalizedState}_count';
    await db.rawUpdate('''
      UPDATE state_counts
      SET $column = $column + 1
      WHERE session_id = ?
    ''', [sessionId]);
  }

  Future<Map<String, dynamic>?> getStateCounts(int sessionId) async {
    final db = await database;
    final result = await db.query(
      'state_counts',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  // ── ALERT EVENTS ──────────────────────────────────────────────────────────

  Future<void> insertAlertEvent({
    required int sessionId,
    required String alertType,
    required int alertLevel,
  }) async {
    final db = await database;
    await db.insert('alert_events', {
      'session_id':   sessionId,
      'alert_type':   alertType.toUpperCase(),
      'alert_level':  alertLevel,
      'triggered_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> getTotalAlertCount({int? days, int? hours}) async {
    final db = await database;
    String where = '1=1';
    final args = <dynamic>[];
    if (hours != null) {
      where += ' AND triggered_at >= ?';
      args.add(DateTime.now().subtract(Duration(hours: hours)).toUtc().toIso8601String());
    } else if (days != null) {
      where += ' AND triggered_at >= ?';
      args.add(_sinceIso(days));
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM alert_events WHERE $where', args);
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<int> getAlertCountByType({
    required String alertType,
    int? days,
  }) async {
    final db = await database;
    String where = 'alert_type = ?';
    final args = <dynamic>[alertType.toUpperCase()];
    if (days != null) {
      where += ' AND triggered_at >= ?';
      args.add(_sinceIso(days));
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM alert_events WHERE $where', args);
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getDailyAlertTrends({int? days}) async {
    final db = await database;
    if (days != null) {
      return await db.rawQuery('''
        SELECT
          DATE(datetime(triggered_at, 'localtime')) as date,
          SUM(CASE WHEN alert_type = 'DROWSY'     THEN 1 ELSE 0 END) as drowsy_count,
          SUM(CASE WHEN alert_type = 'DISTRACTED' THEN 1 ELSE 0 END) as distracted_count
        FROM alert_events
        WHERE triggered_at >= ?
        GROUP BY DATE(datetime(triggered_at, 'localtime'))
        ORDER BY date ASC
      ''', [_sinceIso(days)]);
    } else {
      return await db.rawQuery('''
        SELECT
          DATE(datetime(triggered_at, 'localtime')) as date,
          SUM(CASE WHEN alert_type = 'DROWSY'     THEN 1 ELSE 0 END) as drowsy_count,
          SUM(CASE WHEN alert_type = 'DISTRACTED' THEN 1 ELSE 0 END) as distracted_count
        FROM alert_events
        GROUP BY DATE(datetime(triggered_at, 'localtime'))
        ORDER BY date ASC
      ''');
    }
  }

  Future<List<Map<String, dynamic>>> getHourlyAlertDistribution({
    int? days,
  }) async {
    final db = await database;
    if (days != null) {
      return await db.rawQuery('''
        SELECT
          CAST(strftime('%H', datetime(triggered_at, 'localtime')) AS INTEGER) as hour,
          COUNT(*) as count
        FROM alert_events
        WHERE triggered_at >= ?
        GROUP BY hour
        ORDER BY hour ASC
      ''', [_sinceIso(days)]);
    } else {
      return await db.rawQuery('''
        SELECT
          CAST(strftime('%H', datetime(triggered_at, 'localtime')) AS INTEGER) as hour,
          COUNT(*) as count
        FROM alert_events
        GROUP BY hour
        ORDER BY hour ASC
      ''');
    }
  }

  Future<List<Map<String, dynamic>>> getAlertsBySession(int sessionId) async {
    final db = await database;
    return await db.query(
      'alert_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'triggered_at ASC',
    );
  }

  // ── SYSTEM LOGS ───────────────────────────────────────────────────────────

  Future<void> insertSystemLog({
    required int sessionId,
    required String message,
    required String logType,
  }) async {
    final db = await database;
    await db.insert('system_logs', {
      'session_id': sessionId,
      'log_time':   DateTime.now().toUtc().toIso8601String(),
      'message':    message,
      'log_type':   logType.toUpperCase(),
    });
  }

  Future<List<Map<String, dynamic>>> getSystemLogs(int sessionId) async {
    final db = await database;
    return await db.query(
      'system_logs',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'log_time ASC',
    );
  }

  // ── ALERTNESS SNAPSHOTS ───────────────────────────────────────────────────

  Future<void> insertAlertnessSnapshot({
    required int sessionId,
    required double alertnessPct,
  }) async {
    final db = await database;
    await db.insert('alertness_snapshots', {
      'session_id':    sessionId,
      'recorded_at':   DateTime.now().toUtc().toIso8601String(),
      'alertness_pct': alertnessPct.clamp(0.0, 100.0),
    });
  }

  Future<List<Map<String, dynamic>>> getAlertnessSnapshots(
    int sessionId,
  ) async {
    final db = await database;
    return await db.query(
      'alertness_snapshots',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'recorded_at ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getLatestSessionSnapshots() async {
    final db = await database;
    final latest = await db.query(
      'sessions',
      orderBy: 'started_at DESC',
      limit: 1,
    );
    if (latest.isEmpty) return [];
    final sessionId = latest.first['id'] as int;
    return await getAlertnessSnapshots(sessionId);
  }

  Future<List<Map<String, dynamic>>> getDailySafetyScores({
    int days = 30,
  }) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT
        DATE(started_at)  as day,
        AVG(safety_score) as avg_score,
        COUNT(*)          as session_count
      FROM sessions
      WHERE started_at >= ? AND ended_at IS NOT NULL
      GROUP BY DATE(started_at)
      ORDER BY day ASC
    ''', [_sinceIso(days)]);
  }

  // ── COMBINED QUERIES ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _getLastTwoSessionScores() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT safety_score FROM sessions
      WHERE ended_at IS NOT NULL
      ORDER BY started_at DESC
      LIMIT 2
    ''');
  }

  Future<Map<String, dynamic>> getDashboardSummary() async {
    final results = await Future.wait([
      getTotalDriveTimeSec(days: 30),   // [0]
      getTotalAlertCount(hours: 24),    // [1]
      getSafetyStreakDays(),             // [2]
      getAvgAlertness(days: 7),         // [3]
      getAvgSafetyScore(days: 30),      // [4]
      getLatestSessionSnapshots(),      // [5]
      getDailySafetyScores(days: 30),   // [6]
      _getLastTwoSessionScores(),       // [7]
    ]);

    final twoScores = results[7] as List<Map<String, dynamic>>;

    return {
      'total_drive_hrs':     (results[0] as int) / 3600,
      'alerts_last_24h':     results[1] as int,
      'safety_streak_days':  results[2] as int,
      'avg_alertness_pct':   results[3] as double,
      'safety_score':        results[4] as double,
      'alertness_snapshots': results[5] as List<Map<String, dynamic>>,
      'daily_safety_scores': results[6] as List<Map<String, dynamic>>,
      'last_session_score':  twoScores.isNotEmpty ? twoScores[0]['safety_score'] as double? : null,
      'prev_session_score':  twoScores.length > 1 ? twoScores[1]['safety_score'] as double? : null,
    };
  }

  Future<Map<String, dynamic>> getAnalyticsSummary({int? days}) async {
    final results = await Future.wait([
      getTotalSessionCount(days: days),                          // [0]
      getTotalAlertCount(days: days),                            // [1]
      getAlertCountByType(alertType: 'DROWSY', days: days),     // [2]
      getAlertCountByType(alertType: 'DISTRACTED', days: days), // [3]
      getDailyAlertTrends(days: days),                          // [4]
      getHourlyAlertDistribution(days: days),                   // [5]
      getAvgSafetyScore(days: days),                            // [6]
    ]);

    return {
      'total_sessions':      results[0] as int,
      'total_alerts':        results[1] as int,
      'drowsiness_events':   results[2] as int,
      'distraction_events':  results[3] as int,
      'daily_trends':        results[4] as List<Map<String, dynamic>>,
      'hourly_distribution': results[5] as List<Map<String, dynamic>>,
      'avg_safety_score':    results[6] as double,
    };
  }

  Future<Map<String, dynamic>> getDayAlertBreakdown(String date) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT
        SUM(CASE WHEN alert_type='DROWSY'     AND alert_level=1 THEN 1 ELSE 0 END) AS l1_drowsy,
        SUM(CASE WHEN alert_type='DROWSY'     AND alert_level=2 THEN 1 ELSE 0 END) AS l2_drowsy,
        SUM(CASE WHEN alert_type='DROWSY'     AND alert_level=3 THEN 1 ELSE 0 END) AS l3_drowsy,
        SUM(CASE WHEN alert_type='DISTRACTED' AND alert_level=1 THEN 1 ELSE 0 END) AS l1_distracted,
        SUM(CASE WHEN alert_type='DISTRACTED' AND alert_level=2 THEN 1 ELSE 0 END) AS l2_distracted,
        SUM(CASE WHEN alert_type='DISTRACTED' AND alert_level=3 THEN 1 ELSE 0 END) AS l3_distracted
      FROM alert_events
      WHERE DATE(datetime(triggered_at, 'localtime')) = ?
    ''', [date]);
    if (rows.isEmpty) return {};
    final r = rows.first;
    return {
      'l1_drowsy':     (r['l1_drowsy']     as int?) ?? 0,
      'l2_drowsy':     (r['l2_drowsy']     as int?) ?? 0,
      'l3_drowsy':     (r['l3_drowsy']     as int?) ?? 0,
      'l1_distracted': (r['l1_distracted'] as int?) ?? 0,
      'l2_distracted': (r['l2_distracted'] as int?) ?? 0,
      'l3_distracted': (r['l3_distracted'] as int?) ?? 0,
    };
  }

  // ── VIDEO CLIPS ───────────────────────────────────────────────────────────

  Future<int> insertVideoClip({
    required int sessionId,
    required String filePath,
    required String alertTypes,
    int durationSec = 0,
  }) async {
    final db = await database;
    return await db.insert('video_clips', {
      'session_id':   sessionId,
      'file_path':    filePath,
      'alert_types':  alertTypes,
      'created_at':   DateTime.now().toUtc().toIso8601String(),
      'duration_sec': durationSec,
    });
  }

  Future<List<Map<String, dynamic>>> getAllVideoClips() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT vc.*, s.started_at AS session_started_at
      FROM video_clips vc
      JOIN sessions s ON vc.session_id = s.id
      ORDER BY vc.created_at DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getVideoClipsBySession(
    int sessionId,
  ) async {
    final db = await database;
    return await db.query(
      'video_clips',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
  }

  Future<void> deleteVideoClip(int id) async {
    final db = await database;
    await db.delete('video_clips', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getAllVideoClipPaths() async {
    final db = await database;
    final rows = await db.query('video_clips', columns: ['file_path']);
    return rows.map((r) => r['file_path'] as String).toList();
  }

  Future<List<String>> getVideoClipPathsOlderThan(int days) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT vc.file_path
      FROM video_clips vc
      JOIN sessions s ON vc.session_id = s.id
      WHERE s.started_at < ?
    ''', [_sinceIso(days)]);
    return rows.map((r) => r['file_path'] as String).toList();
  }

  // ── UTILITY ───────────────────────────────────────────────────────────────

  Future<void> deleteSessionsOlderThan(int days) async {
    final db     = await database;
    final cutoff = _sinceIso(days);

    final rows = await db.rawQuery(
      "SELECT id FROM sessions WHERE started_at < ?", [cutoff]);
    if (rows.isEmpty) return;

    final ids          = rows.map((r) => r['id'] as int).toList();
    final placeholders = ids.map((_) => '?').join(',');

    final clipRows = await db.rawQuery(
      "SELECT file_path FROM video_clips WHERE session_id IN ($placeholders)",
      ids,
    );
    final clipPaths = clipRows.map((r) => r['file_path'] as String).toList();

    await db.transaction((txn) async {
      await txn.rawDelete(
        "DELETE FROM video_clips WHERE session_id IN ($placeholders)", ids);
      await txn.rawDelete(
        "DELETE FROM alertness_snapshots WHERE session_id IN ($placeholders)", ids);
      await txn.rawDelete(
        "DELETE FROM system_logs WHERE session_id IN ($placeholders)", ids);
      await txn.rawDelete(
        "DELETE FROM alert_events WHERE session_id IN ($placeholders)", ids);
      await txn.rawDelete(
        "DELETE FROM state_counts WHERE session_id IN ($placeholders)", ids);
      await txn.rawDelete(
        "DELETE FROM sessions WHERE id IN ($placeholders)", ids);
    });

    for (final path in clipPaths) {
      try {
        await VideoClipService.deleteFile(path);
      } catch (e) {
        debugPrint('[DB] Failed to delete clip file $path: $e');
      }
    }
  }

  Future<Map<int, int>> getAllSessionAlertCounts() async {
    final db   = await database;
    final rows = await db.rawQuery(
      "SELECT session_id, COUNT(*) as cnt FROM alert_events GROUP BY session_id",
    );
    return {
      for (final r in rows)
        (r['session_id'] as int): (r['cnt'] as int),
    };
  }

  Future<void> clearAllData() async {
    final db = await database;
    final paths = await getAllVideoClipPaths();
    await db.transaction((txn) async {
      await txn.delete('video_clips');
      await txn.delete('alertness_snapshots');
      await txn.delete('system_logs');
      await txn.delete('alert_events');
      await txn.delete('state_counts');
      await txn.delete('sessions');
    });
    for (final path in paths) {
      try {
        await VideoClipService.deleteFile(path);
      } catch (e) {
        debugPrint('[DB] Failed to delete clip file $path: $e');
      }
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
