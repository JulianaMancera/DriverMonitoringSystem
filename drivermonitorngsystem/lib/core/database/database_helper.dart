// ─────────────────────────────────────────────────────────────────────────────
// database_helper.dart
//
// PURPOSE:
//   The single source of truth for ALL local data in Bantay Drive.
//   Uses SQLite (via sqflite) with 5 tables at schema version 2.
//
// TABLES:
//   • sessions            — one row per drive session
//   • state_counts        — neutral/drowsy/distracted frame counts per session
//   • alert_events        — every alert fired (type, level, timestamp)
//   • system_logs         — INFO/SUCCESS/WARNING log entries per session
//   • alertness_snapshots — 5-second alertness % readings per session
//
// HOW IT CONNECTS TO THE AI MODEL (DMS-HybridNet):
//   The model outputs one of 3 main states per frame:
//     NEUTRAL / DROWSY / DISTRACTED
//   monitor_screen.dart calls:
//     • incrementStateCount()    — on every classified frame
//     • insertAlertEvent()       — when alert level 1/2/3 is triggered
//     • insertAlertnessSnapshot()— every 5 seconds
//     • insertSystemLog()        — for INFO/WARNING events
//     • endSession()             — when recording stops (saves final score)
//
// CALLED BY:
//   • monitor_screen.dart  — writes session data in real time
//   • dashboard_screen.dart — reads summary stats + chart data
//   • analytics_screen.dart — reads trend + distribution data
//   • history_screen.dart   — reads session list + detail data
//   • settings_screen.dart  — calls deleteSessionsOlderThan() + clearAllData()
// ─────────────────────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // ── DATABASE INITIALIZATION ───────────────────────────────────────────────

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
    // Sessions — one row = one drive session
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

    // State counts — how many frames were NEUTRAL / DROWSY / DISTRACTED
    // per session. Written by monitor_screen via incrementStateCount().
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

    // Alert events — every L1/L2/L3 alert fired during a session.
    // alert_type  : 'DROWSY' or 'DISTRACTED'
    // alert_level : 1, 2, or 3
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

    // System logs — INFO / SUCCESS / WARNING entries shown in session detail
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

    // Alertness snapshots — recorded every 5 seconds during a session.
    // Used to draw the alertness chart in the history session detail sheet.
    await db.execute('''
      CREATE TABLE alertness_snapshots (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id    INTEGER NOT NULL,
        recorded_at   TEXT NOT NULL,
        alertness_pct REAL NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _migrateDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Schema v2 added trip_label to sessions.
      // Using try/catch because some devices may have already added this column
      // manually during development.
      try {
        await db.execute("ALTER TABLE sessions ADD COLUMN trip_label TEXT");
      } catch (_) {}
    }
  }

  // ── SESSIONS — CRUD ───────────────────────────────────────────────────────

  /// Called by monitor_screen when recording STARTS.
  /// Returns the new session ID used for all subsequent writes.
  Future<int> insertSession() async {
    final db = await database;
    return await db.insert('sessions', {
      'started_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Called by monitor_screen when recording STOPS.
  /// Saves the final computed safety score and alertness average.
  ///
  /// Safety score formula (computed in monitor_screen):
  ///   score = 100 - (drowsy_frames + distracted_frames) / total_frames * 100
  ///   clamped to [0, 100]
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

  /// Called by history_screen to show the full session list.
  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final db = await database;
    return await db.query('sessions', orderBy: 'started_at DESC');
  }

  /// Called by history_screen session detail sheet.
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

  /// Total drive time in seconds — Dashboard "Total Drive Time" card.
  Future<int> getTotalDriveTimeSec({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toUtc()
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

  /// Average safety score — Dashboard Safety Score ring.
  /// Returns 100.0 (perfect score) when no sessions exist yet — a fresh
  /// install should show a perfect score, not zero.
  Future<double> getAvgSafetyScore({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toUtc()
          .toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT AVG(safety_score) as avg FROM sessions WHERE $where',
      args,
    );
    return (result.first['avg'] as double?) ?? 100.0;
  }

  /// Average alertness — Dashboard "Avg Alertness" card.
  /// Returns 100.0 when no sessions (same logic as safety score).
  Future<double> getAvgAlertness({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toUtc()
          .toIso8601String();
      where += ' AND started_at >= ?';
      args.add(since);
    }
    final result = await db.rawQuery(
      'SELECT AVG(alertness_avg) as avg FROM sessions WHERE $where',
      args,
    );
    return (result.first['avg'] as double?) ?? 100.0;
  }

  /// Safety streak — Dashboard "Safety Streak" card.
  /// Counts consecutive days with NO alert events, going backwards from today.
  /// Returns 0 if no sessions exist yet (no driving history = no streak).
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

  /// Total completed session count — Analytics summary card.
  Future<int> getTotalSessionCount({int? days}) async {
    final db = await database;
    String where = 'ended_at IS NOT NULL';
    List<dynamic> args = [];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toUtc()
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

  // ── STATE COUNTS — CRUD ───────────────────────────────────────────────────

  /// Called by monitor_screen immediately after insertSession().
  /// Creates the initial zero-count row for the new session.
  Future<void> insertStateCount(int sessionId) async {
    final db = await database;
    await db.insert('state_counts', {
      'session_id':       sessionId,
      'neutral_count':    0,
      'drowsy_count':     0,
      'distracted_count': 0,
    });
  }

  /// Called by monitor_screen on EVERY classified frame from DMS-HybridNet.
  /// state must be 'neutral', 'drowsy', or 'distracted' (case-insensitive).
  ///
  /// Model output → state mapping:
  ///   Class 0 (safe_driving)      → neutral
  ///   Classes 1,2,10 (drowsy)     → drowsy
  ///   Classes 3-9 (distracted)    → distracted
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

  /// Called by history_screen session detail sheet to show state breakdown bar.
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

  // ── ALERT EVENTS — CRUD ───────────────────────────────────────────────────

  /// Called by monitor_screen when an alert threshold is crossed.
  /// alertType  : 'DROWSY' or 'DISTRACTED'
  /// alertLevel : 1 (banner), 2 (persistent), 3 (full-screen alarm)
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

  /// Total alert count — Dashboard "Alerts (last 24h)" card and Analytics.
  /// Pass hours:24 for dashboard, days:N for analytics.
  Future<int> getTotalAlertCount({int? days, int? hours}) async {
    final db = await database;
    String where = '1=1';
    List<dynamic> args = [];
    if (hours != null) {
      final since = DateTime.now()
          .subtract(Duration(hours: hours))
          .toUtc()
          .toIso8601String();
      where += ' AND triggered_at >= ?';
      args.add(since);
    } else if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toUtc()
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

  /// Alert count by type — Analytics "Drowsiness Events" and
  /// "Distraction Events" summary cards.
  Future<int> getAlertCountByType({
    required String alertType,
    int? days,
  }) async {
    final db = await database;
    String where = 'alert_type = ?';
    List<dynamic> args = [alertType.toUpperCase()];
    if (days != null) {
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toUtc()
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

  /// Daily drowsy vs distracted counts — Analytics line chart.
  /// Returns one row per day with drowsy_count and distracted_count.
  Future<List<Map<String, dynamic>>> getDailyAlertTrends({
    int days = 7,
  }) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toUtc()
        .toIso8601String();
    return await db.rawQuery('''
      SELECT
        DATE(triggered_at) as date,
        SUM(CASE WHEN alert_type = 'DROWSY'     THEN 1 ELSE 0 END) as drowsy_count,
        SUM(CASE WHEN alert_type = 'DISTRACTED' THEN 1 ELSE 0 END) as distracted_count
      FROM alert_events
      WHERE triggered_at >= ?
      GROUP BY DATE(triggered_at)
      ORDER BY date ASC
    ''', [since]);
  }

  /// Hourly alert distribution — Analytics bar chart (all 24 hours).
  /// Returns one row per hour that had at least one alert.
  Future<List<Map<String, dynamic>>> getHourlyAlertDistribution({
    int days = 7,
  }) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toUtc()
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

  /// All alerts for one session — History session detail sheet.
  Future<List<Map<String, dynamic>>> getAlertsBySession(
    int sessionId,
  ) async {
    final db = await database;
    return await db.query(
      'alert_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'triggered_at ASC',
    );
  }

  // ── SYSTEM LOGS — CRUD ────────────────────────────────────────────────────

  /// Called by monitor_screen for INFO/SUCCESS/WARNING events.
  /// logType: 'INFO', 'SUCCESS', or 'WARNING'
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

  /// All logs for one session — History session detail sheet.
  Future<List<Map<String, dynamic>>> getSystemLogs(int sessionId) async {
    final db = await database;
    return await db.query(
      'system_logs',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'log_time ASC',
    );
  }

  // ── ALERTNESS SNAPSHOTS — CRUD ────────────────────────────────────────────

  /// Called by monitor_screen every 5 seconds during a session.
  /// alertnessPct is derived from the model's neutral confidence score (0–100).
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

  /// All snapshots for one session — History session detail alertness chart.
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

  /// Snapshots for the most recent session — Dashboard live chart.
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

  /// Per-day average safety score — Dashboard "Safety Score History" chart.
  /// Returns one row per calendar day with avg_score and session_count.
  Future<List<Map<String, dynamic>>> getDailySafetyScores({
    int days = 30,
  }) async {
    final db = await database;
    final since = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .toIso8601String();
    return await db.rawQuery('''
      SELECT
        DATE(started_at)  as day,
        AVG(safety_score) as avg_score,
        COUNT(*)          as session_count
      FROM sessions
      WHERE started_at >= ? AND ended_at IS NOT NULL
      GROUP BY DATE(started_at)
      ORDER BY day ASC
    ''', [since]);
  }

  // ── COMBINED QUERIES ──────────────────────────────────────────────────────

  /// All data needed by dashboard_screen in one parallel fetch.
  /// Called by dashboard_screen on init and every 30 seconds.
  Future<Map<String, dynamic>> getDashboardSummary() async {
    final results = await Future.wait([
      getTotalDriveTimeSec(days: 30),      // index 0
      getTotalAlertCount(hours: 24),        // index 1
      getSafetyStreakDays(),                // index 2
      getAvgAlertness(days: 7),            // index 3
      getAvgSafetyScore(days: 30),         // index 4
      getLatestSessionSnapshots(),          // index 5
      getDailySafetyScores(days: 30),      // index 6
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

  /// All data needed by analytics_screen in one parallel fetch.
  /// days = null means "All Time".
  Future<Map<String, dynamic>> getAnalyticsSummary({int? days}) async {
    final effectiveDays = days ?? 7;
    final results = await Future.wait([
      getTotalSessionCount(days: days),                          // index 0
      getTotalAlertCount(days: days),                            // index 1
      getAlertCountByType(alertType: 'DROWSY', days: days),     // index 2
      getAlertCountByType(alertType: 'DISTRACTED', days: days), // index 3
      getDailyAlertTrends(days: effectiveDays),                  // index 4
      getHourlyAlertDistribution(days: effectiveDays),           // index 5
      getAvgSafetyScore(days: days),                             // index 6
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

  // ── UTILITY ───────────────────────────────────────────────────────────────

  /// Called by settings_screen when user changes retention period.
  /// Deletes sessions AND all related rows (cascade via transaction).
  Future<void> deleteSessionsOlderThan(int days) async {
    final db     = await database;
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: days))
        .toIso8601String();

    final rows = await db.rawQuery(
      "SELECT id FROM sessions WHERE started_at < ?",
      [cutoff],
    );
    if (rows.isEmpty) return;

    final ids          = rows.map((r) => r['id'] as int).toList();
    final placeholders = ids.map((_) => '?').join(',');

    await db.transaction((txn) async {
      await txn.rawDelete(
        "DELETE FROM alertness_snapshots WHERE session_id IN ($placeholders)",
        ids,
      );
      await txn.rawDelete(
        "DELETE FROM system_logs WHERE session_id IN ($placeholders)",
        ids,
      );
      await txn.rawDelete(
        "DELETE FROM alert_events WHERE session_id IN ($placeholders)",
        ids,
      );
      await txn.rawDelete(
        "DELETE FROM state_counts WHERE session_id IN ($placeholders)",
        ids,
      );
      await txn.rawDelete(
        "DELETE FROM sessions WHERE id IN ($placeholders)",
        ids,
      );
    });
  }

  /// Alert count per session — used by history_screen to show alert badge.
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

  /// Called by settings_screen "Clear All History" button.
  /// Wipes ALL data from ALL tables.
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

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}