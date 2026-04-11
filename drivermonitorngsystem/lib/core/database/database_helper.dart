import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // DATABASE INITIALIZATION
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
      version: 2,
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
        notes         TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE state_counts (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id       INTEGER NOT NULL,
        neutral_count    INTEGER DEFAULT 0,
        drowsy_count     INTEGER DEFAULT 0,
        distracted_count INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE alert_events (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id   INTEGER NOT NULL,
        alert_type   TEXT NOT NULL,
        alert_level  INTEGER NOT NULL,
        triggered_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE system_logs (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        log_time   TEXT NOT NULL,
        message    TEXT NOT NULL,
        log_type   TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE alertness_snapshots (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id    INTEGER NOT NULL,
        recorded_at   TEXT NOT NULL,
        alertness_pct REAL NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');
  }

  Future<void> _migrateDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE sessions ADD COLUMN trip_label TEXT");
    }
  }

  // SESSIONS — CRUD
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
        'ended_at':     DateTime.now().toUtc().toIso8601String(),
        'duration_sec': durationSec,
        'alertness_avg': alertnessAvg,
        'safety_score': safetyScore,
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
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT SUM(duration_sec) as total FROM sessions WHERE $where', args,
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Average safety score — Dashboard Safety Score
  /// ✅ FIX: returns 100.0 (not 0.0) when no sessions exist yet.
  ///    A driver with no history has a perfect score by default.
  Future<double> getAvgSafetyScore({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT AVG(safety_score) as avg FROM sessions WHERE $where', args,
    );
    // ✅ FIX was here: was ?? 0.0 — caused score to show 0 on fresh install
    return (result.first['avg'] as double?) ?? 100.0;
  }

  /// Average alertness — Dashboard card "Avg Alertness"
  /// ✅ Returns 100.0 when no sessions — same logic as safety score.
  Future<double> getAvgAlertness({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT AVG(alertness_avg) as avg FROM sessions WHERE $where', args,
    );
    return (result.first['avg'] as double?) ?? 100.0;
  }

  Future<int> getSafetyStreakDays() async {
    final db = await database;
    final sessionCheck = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM sessions WHERE ended_at IS NOT NULL',
    );
    final sessionCount = (sessionCheck.first['cnt'] as int?) ?? 0;
    if (sessionCount == 0) return 0;

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
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM sessions WHERE $where', args,
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  // STATE COUNTS — CRUD
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

  // ALERT EVENTS — CRUD
  Future<void> insertAlertEvent({
    required int sessionId,
    required String alertType,
    required int alertLevel,
  }) async {
    final db = await database;
    await db.insert('alert_events', {
      'session_id':   sessionId,
      'alert_type':   alertType,
      'alert_level':  alertLevel,
      'triggered_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<int> getTotalAlertCount({int? days, int? hours}) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> args = [];
    if (hours != null) {
      final since = DateTime.now().subtract(Duration(hours: hours)).toIso8601String();
      where += ' AND triggered_at >= ?';
      args.add(since);
    } else if (days != null) {
      final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
      where += ' AND triggered_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM alert_events WHERE $where', args,
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<int> getAlertCountByType({
    required String alertType,
    int? days,
  }) async {
    final db = await database;
    String where = 'alert_type = ?';
    List<dynamic> args = [alertType];
    if (days != null) {
      final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
      where += ' AND triggered_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM alert_events WHERE $where', args,
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getDailyAlertTrends({int days = 7}) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return await db.rawQuery('''
      SELECT
        DATE(triggered_at) as date,
        SUM(CASE WHEN alert_type = 'DROWSY'      THEN 1 ELSE 0 END) as drowsy_count,
        SUM(CASE WHEN alert_type = 'DISTRACTED'  THEN 1 ELSE 0 END) as distracted_count
      FROM alert_events
      WHERE triggered_at >= ?
      GROUP BY DATE(triggered_at)
      ORDER BY date ASC
    ''', [since]);
  }

  Future<List<Map<String, dynamic>>> getHourlyAlertDistribution({int days = 7}) async {
    final db = await database;
    final since = DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return await db.rawQuery('''
      SELECT
        CAST(strftime('%H', triggered_at) AS INTEGER) as hour,
        COUNT(*) as count
      FROM alert_events
      WHERE triggered_at >= ?
      GROUP BY hour
      ORDER BY hour ASC
    ''', [since]);
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

  // SYSTEM LOGS — CRUD
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
      'log_type':   logType,
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

  // ALERTNESS SNAPSHOTS — CRUD
  Future<void> insertAlertnessSnapshot({
    required int sessionId,
    required double alertnessPct,
  }) async {
    final db = await database;
    await db.insert('alertness_snapshots', {
      'session_id':    sessionId,
      'recorded_at':   DateTime.now().toUtc().toIso8601String(),
      'alertness_pct': alertnessPct,
    });
  }

  Future<List<Map<String, dynamic>>> getAlertnessSnapshots(int sessionId) async {
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
    final latest = await db.query('sessions', orderBy: 'started_at DESC', limit: 1);
    if (latest.isEmpty) return [];
    final sessionId = latest.first['id'] as int;
    return await getAlertnessSnapshots(sessionId);
  }

  /// Per-day average safety score — Dashboard "Safety Score History" chart.
  /// ✅ Returns ALL completed sessions grouped by calendar day.
  ///    Dashboard uses this to draw the live line chart.
  Future<List<Map<String, dynamic>>> getDailySafetyScores({int days = 30}) async {
    final db = await database;
    final since = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .toIso8601String();
    return await db.rawQuery('''
      SELECT
        DATE(started_at) as day,
        AVG(safety_score)   as avg_score,
        COUNT(*)            as session_count
      FROM sessions
      WHERE started_at >= ? AND ended_at IS NOT NULL
      GROUP BY DATE(started_at)
      ORDER BY day ASC
    ''', [since]);
  }

  // COMBINED QUERIES
  Future<Map<String, dynamic>> getDashboardSummary() async {
    final results = await Future.wait([
      getTotalDriveTimeSec(days: 30),
      getTotalAlertCount(hours: 24),
      getSafetyStreakDays(),
      getAvgAlertness(days: 7),
      getAvgSafetyScore(days: 30),
      getLatestSessionSnapshots(),
      getDailySafetyScores(days: 30),
    ]);

    return {
      'total_drive_hrs':     (results[0] as int) / 3600,
      'alerts_last_24h':     results[1] as int,
      'safety_streak_days':  results[2] as int,
      'avg_alertness_pct':   results[3] as double,
      'safety_score':        results[4] as double,
      'alertness_snapshots': results[5] as List<Map<String, dynamic>>,
      'daily_safety_scores': results[6] as List<Map<String, dynamic>>,
    };
  }

  Future<Map<String, dynamic>> getAnalyticsSummary({int? days}) async {
    final effectiveDays = days ?? 7;
    final results = await Future.wait([
      getTotalSessionCount(days: days),
      getTotalAlertCount(days: days),
      getAlertCountByType(alertType: 'DROWSY',      days: days),
      getAlertCountByType(alertType: 'DISTRACTED',  days: days),
      getDailyAlertTrends(days: effectiveDays),
      getHourlyAlertDistribution(days: effectiveDays),
      getAvgSafetyScore(days: days),
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

  // UTILITY
  Future<void> close() async {
    final db = await database;
    db.close();
  }

  Future<void> deleteSessionsOlderThan(int days) async {
    final db     = await database;
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .toIso8601String();

    final rows = await db.rawQuery(
      "SELECT id FROM sessions WHERE started_at < ?", [cutoff],
    );
    if (rows.isEmpty) return;

    final ids          = rows.map((r) => r['id'] as int).toList();
    final placeholders = ids.map((_) => '?').join(',');

    await db.transaction((txn) async {
      await txn.rawDelete("DELETE FROM alertness_snapshots WHERE session_id IN ($placeholders)", ids);
      await txn.rawDelete("DELETE FROM system_logs        WHERE session_id IN ($placeholders)", ids);
      await txn.rawDelete("DELETE FROM alert_events       WHERE session_id IN ($placeholders)", ids);
      await txn.rawDelete("DELETE FROM state_counts       WHERE session_id IN ($placeholders)", ids);
      await txn.rawDelete("DELETE FROM sessions           WHERE id         IN ($placeholders)", ids);
    });
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
    await db.transaction((txn) async {
      await txn.delete('alertness_snapshots');
      await txn.delete('system_logs');
      await txn.delete('alert_events');
      await txn.delete('state_counts');
      await txn.delete('sessions');
    });
  }
}