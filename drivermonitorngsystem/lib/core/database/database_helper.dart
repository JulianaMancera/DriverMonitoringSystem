import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  //Database Initialization

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('driver_monitoring.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return await openDatabase(
      path, 
      version: 1, 
      onCreate: _createTables
    );
  }
  // TABLE 1 - sessions
  // It is for storing each monitoring session (one seesion = one drive)
  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        duration_sec INTEGER DEFAULT 0,
        alertness_avg REAL DEFAULT 0.0,
        safety_score REAL DEFAULT 0.0,
        notes TEXT
      )
    ''');
  // TABLE 2 - state_counts
  // Stores the total count of each driver state per session
    await db.execute('''
      CREATE TABLE state_counts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        neutral_count INTEGER DEFAULT 0,
        drowsy_count INTEGER DEFAULT 0,
        distracted_count INTEGER DEFAULT 0,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');
  // TABLE 3 - alert_events
  // Stores every alert triggered during a session
  // alert_type: 'DROWSY' or 'DISTRACTED'
  // alert_level: 1 (first ping), 2nd (second ping), 3rd (looping alarm) - this can be used to determine severity and also for analytics
    await db.execute('''
      CREATE TABLE alert_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        alert_type TEXT NOT NULL,
        alert_level INTEGER NOT NULL,
        triggered_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id)
      )
    ''');
  // TABLE 4 — system_logs
    // Stores the System Log entries shown in Monitoring Screen
    // log_type: 'INFO' (white), 'SUCCESS' (green), 'WARNING' (orange/red)
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

    // TABLE 5 — alertness_snapshots
    // Stores alertness % every few seconds for the Alertness History chart
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

  // ─────────────────────────────────────────────────────────────────────────
  // SESSIONS — CRUD
  // Used by: Monitoring Screen (insert/update), Dashboard, Analytics

  /// Call when driver presses Record — creates a new session
  Future<int> insertSession() async {
    final db = await database;
    return await db.insert('sessions', {
      'started_at': DateTime.now().toIso8601String(),
    });
  }

  /// Call when driver stops recording — updates session end time and scores
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
        'ended_at': DateTime.now().toIso8601String(),
        'duration_sec': durationSec,
        'alertness_avg': alertnessAvg,
        'safety_score': safetyScore,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Fetch all sessions (for History Screen)
  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final db = await database;
    return await db.query('sessions', orderBy: 'started_at DESC');
  }

  /// Fetch a single session by ID (for Report Screen)
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

  /// Total drive time in seconds — Dashboard card "Total Drive Time"
  /// [days] = 30 for last 30 days, null for all time
  Future<int> getTotalDriveTimeSec({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT SUM(duration_sec) as total FROM sessions WHERE $where',
      args,
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Average safety score — used to compute Dashboard Safety Score
  Future<double> getAvgSafetyScore({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT AVG(safety_score) as avg FROM sessions WHERE $where',
      args,
    );
    return (result.first['avg'] as double?) ?? 0.0;
  }

  /// Average alertness — Dashboard card "Avg Alertness"
  Future<double> getAvgAlertness({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT AVG(alertness_avg) as avg FROM sessions WHERE $where',
      args,
    );
    return (result.first['avg'] as double?) ?? 0.0;
  }

  /// Safety streak — Dashboard card "Safety Streak"
  /// Counts consecutive days ending today with zero alert_events
  Future<int> getSafetyStreakDays() async {
    final db = await database;
    int streak = 0;
    DateTime day = DateTime.now();

    for (int i = 0; i < 365; i++) {
      final dayStart = DateTime(day.year, day.month, day.day)
          .toIso8601String();
      final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59)
          .toIso8601String();

      final result = await db.rawQuery('''
        SELECT COUNT(*) as cnt FROM alert_events ae
        JOIN sessions s ON ae.session_id = s.id
        WHERE s.started_at >= ? AND s.started_at <= ?
      ''', [dayStart, dayEnd]);

      final count = (result.first['cnt'] as int?) ?? 0;
      if (count == 0) {
        streak++;
        day = day.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  /// Total session count — Analytics card "Total Sessions"
  Future<int> getTotalSessionCount({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM sessions WHERE $where',
      args,
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATE COUNTS — CRUD
  // Used by: Monitoring Screen (insert/update), Analytics

  /// Insert initial state_counts row when session starts
  Future<void> insertStateCount(int sessionId) async {
    final db = await database;
    await db.insert('state_counts', {
      'session_id': sessionId,
      'neutral_count': 0,
      'drowsy_count': 0,
      'distracted_count': 0,
    });
  }

  /// Increment a specific state count — call every time model outputs a state
  /// [state]: 'neutral', 'drowsy', or 'distracted'
  Future<void> incrementStateCount({
    required int sessionId,
    required String state,
  }) async {
    final db = await database;
    final column = '${state.toLowerCase()}_count';
    await db.rawUpdate('''
      UPDATE state_counts
      SET $column = $column + 1
      WHERE session_id = ?
    ''', [sessionId]);
  }

  /// Get state counts for a session (for Report Screen)
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

  // ─────────────────────────────────────────────────────────────────────────
  // ALERT EVENTS — CRUD
  // Used by: Monitoring Screen (insert), Dashboard, Analytics

  /// Insert an alert event — call when alert is triggered
  Future<void> insertAlertEvent({
    required int sessionId,
    required String alertType,   // 'DROWSY' or 'DISTRACTED'
    required int alertLevel,     // 1, 2, or 3
  }) async {
    final db = await database;
    await db.insert('alert_events', {
      'session_id': sessionId,
      'alert_type': alertType,
      'alert_level': alertLevel,
      'triggered_at': DateTime.now().toIso8601String(),
    });
  }

  /// Total alert count — Dashboard card "Alert Triggered" & Analytics
  Future<int> getTotalAlertCount({int? days, int? hours}) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> args = [];
    if (hours != null) {
      final since = DateTime.now()
          .subtract(Duration(hours: hours))
          .toIso8601String();
      where += ' AND triggered_at >= ?';
      args.add(since);
    } else if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      where += ' AND triggered_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM alert_events WHERE $where',
      args,
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Count alerts by type — Analytics cards "Drowsiness Events" / "Distraction Events"
  Future<int> getAlertCountByType({
    required String alertType,  // 'DROWSY' or 'DISTRACTED'
    int? days,
  }) async {
    final db = await database;
    String where = 'alert_type = ?';
    List<dynamic> args = [alertType];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      where += ' AND triggered_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM alert_events WHERE $where',
      args,
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Per-day alert counts grouped by type — Analytics "Drowsiness vs Distraction Trends"
  /// Returns list of {date, drowsy_count, distracted_count}
  Future<List<Map<String, dynamic>>> getDailyAlertTrends({int days = 7}) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
    return await db.rawQuery('''
      SELECT
        DATE(triggered_at) as date,
        SUM(CASE WHEN alert_type = 'DROWSY' THEN 1 ELSE 0 END) as drowsy_count,
        SUM(CASE WHEN alert_type = 'DISTRACTED' THEN 1 ELSE 0 END) as distracted_count
      FROM alert_events
      WHERE triggered_at >= ?
      GROUP BY DATE(triggered_at)
      ORDER BY date ASC
    ''', [since]);
  }

  /// Per-hour alert counts — Analytics "Hourly Alert Distribution"
  /// Returns list of {hour, count}
  Future<List<Map<String, dynamic>>> getHourlyAlertDistribution({int days = 7}) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String();
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

  /// Alerts for a specific session — Report Screen
  Future<List<Map<String, dynamic>>> getAlertsBySession(int sessionId) async {
    final db = await database;
    return await db.query(
      'alert_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'triggered_at ASC',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SYSTEM LOGS — CRUD
  // Used by: Monitoring Screen System Log section

  /// Insert a system log entry
  /// [logType]: 'INFO' (white), 'SUCCESS' (green), 'WARNING' (orange/red)
  Future<void> insertSystemLog({
    required int sessionId,
    required String message,
    required String logType,
  }) async {
    final db = await database;
    await db.insert('system_logs', {
      'session_id': sessionId,
      'log_time': DateTime.now().toIso8601String(),
      'message': message,
      'log_type': logType,
    });
  }

  /// Get all system logs for a session — Monitoring Screen System Log
  Future<List<Map<String, dynamic>>> getSystemLogs(int sessionId) async {
    final db = await database;
    return await db.query(
      'system_logs',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'log_time ASC',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ALERTNESS SNAPSHOTS — CRUD
  // Used by: Dashboard "Alertness History" chart

  /// Insert alertness snapshot — call every ~5 seconds during monitoring
  Future<void> insertAlertnesSnapshot({
    required int sessionId,
    required double alertnessPct,
  }) async {
    final db = await database;
    await db.insert('alertness_snapshots', {
      'session_id': sessionId,
      'recorded_at': DateTime.now().toIso8601String(),
      'alertness_pct': alertnessPct,
    });
  }

  /// Get alertness snapshots for a session — Dashboard Alertness History chart
  Future<List<Map<String, dynamic>>> getAlertnessSnapshots(int sessionId) async {
    final db = await database;
    return await db.query(
      'alertness_snapshots',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'recorded_at ASC',
    );
  }

  /// Get latest session's alertness snapshots — Dashboard live chart
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

  // ─────────────────────────────────────────────────────────────────────────
  // COMBINED QUERIES
  // Complex queries that combine multiple tables for screen data

  /// Get all dashboard summary data in one call
  /// Returns a map with all values needed for Dashboard Screen
  Future<Map<String, dynamic>> getDashboardSummary() async {
    final totalDriveSec = await getTotalDriveTimeSec(days: 30);
    final alertsLast24h = await getTotalAlertCount(hours: 24);
    final safetyStreak = await getSafetyStreakDays();
    final avgAlertness = await getAvgAlertness(days: 7);
    final safetyScore = await getAvgSafetyScore(days: 30);
    final snapshots = await getLatestSessionSnapshots();

    return {
      'total_drive_hrs': totalDriveSec / 3600,   // convert to hours
      'alerts_last_24h': alertsLast24h,
      'safety_streak_days': safetyStreak,
      'avg_alertness_pct': avgAlertness,
      'safety_score': safetyScore,
      'alertness_snapshots': snapshots,
    };
  }

  /// Get all analytics summary data in one call
  /// [days]: 7, 30, or null (all time)
  Future<Map<String, dynamic>> getAnalyticsSummary({int? days}) async {
    final totalSessions = await getTotalSessionCount(days: days);
    final totalAlerts = await getTotalAlertCount(days: days);
    final drowsinessEvents = await getAlertCountByType(
        alertType: 'DROWSY', days: days);
    final distractionEvents = await getAlertCountByType(
        alertType: 'DISTRACTED', days: days);
    final dailyTrends = await getDailyAlertTrends(days: days ?? 7);
    final hourlyDistribution = await getHourlyAlertDistribution(days: days ?? 7);

    return {
      'total_sessions': totalSessions,
      'total_alerts': totalAlerts,
      'drowsiness_events': drowsinessEvents,
      'distraction_events': distractionEvents,
      'daily_trends': dailyTrends,
      'hourly_distribution': hourlyDistribution,
    };
  }

  // UTILITY

  /// Close the database
  Future<void> close() async {
    final db = await database;
    db.close();
  }

  /// Delete all data — for testing/reset purposes only
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('alertness_snapshots');
    await db.delete('system_logs');
    await db.delete('alert_events');
    await db.delete('state_counts');
    await db.delete('sessions');
  }
  
}
