import 'package:sqflite/sqflite.dart';
import '../models/mo_milestone.dart';
import '../models/mo_mt_task.dart';

/// Data-access service for the db_Milestones table.
///
/// Current database schema (as created in EPMS):
///   milestone_type  TEXT NOT NULL
///   milestone_date  TEXT NOT NULL   (YYYY-MM-DD)
///   milestone_phy_chapters  TEXT NOT NULL
///   milestone_chem_chapters TEXT NOT NULL
///   milestone_bio_chapters  TEXT NOT NULL
///   milestone_timestamp     TEXT NOT NULL
///
/// Primary key: (milestone_date, milestone_type).
/// The service deliberately uses the actual live table/column names above.
/// No model class is required; screens consume Map<String, Object?> rows.
class MilestoneCalendarSvc {
  MilestoneCalendarSvc(this._db);

  final Database _db;

  static const String table = 'db_Milestones';

  static const String colType = 'milestone_type';
  static const String colDate = 'milestone_date';
  static const String colPhy = 'milestone_phy_chapters';
  static const String colPhyTaskCreated = 'milestone_phy_task_created';
  static const String colChem = 'milestone_chem_chapters';
  static const String colChemTaskCreated = 'milestone_chem_task_created';
  static const String colBio = 'milestone_bio_chapters';
  static const String colBioTaskCreated = 'milestone_bio_task_created';
  static const String colCommonTaskCreated = 'milestone_common_tasks_created';

  Future<List<Map<String, Object?>>> getUpcomingMilestonesForWidget(
    DateTime fromDate,
  ) async {
    // Get the next available/upcoming milestone
    // starting from the supplied date.

    final milestones = await getNextSundayMilestonesWithNames();
    return milestones;
  }

  // ----------------------------------------------------------
  // Find the upcoming sunday having Milestone
  // ----------------------------------------------------------
  Future<int> getNextAvailableMilestoneTaskCount() async {
    final today = DateTime.now();

    final daysUntilSunday = DateTime.sunday - today.weekday == 0
        ? 7
        : DateTime.sunday - today.weekday;

    final upcomingSunday = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: daysUntilSunday));

    // ----------------------------------------------------------
    // Find the first future milestone date having
    // PENDING or STARTED milestone tasks.
    // ----------------------------------------------------------

    final rows = await _db.rawQuery(
      '''
    SELECT  date(TaskDueDate) AS MilestoneDate, COUNT(*) AS TaskCount
    FROM db_TaskLogWeekEnd 
     WHERE TaskID LIKE 'MT_%'
      AND UPPER(TaskStatus) IN ('PENDING', 'STARTED')
      AND date(TaskDueDate) >= date(?)
    GROUP BY date(TaskDueDate) ORDER BY date(TaskDueDate) ASC LIMIT 1
    ''',
      [upcomingSunday.toIso8601String()],
    );

    // ----------------------------------------------------------
    // No future milestone tasks
    // ----------------------------------------------------------
    if (rows.isEmpty) {
      return 0;
    }

    // ----------------------------------------------------------
    // Return count for the first available milestone date
    // ----------------------------------------------------------
    final count = rows.first['TaskCount'];
    if (count is int) {
      return count;
    }
    if (count is num) {
      return count.toInt();
    }
    return int.tryParse(count?.toString() ?? '') ?? 0;
  }

  // Returns counts of in-progress milestone tasks for the dashboard.
  // Only milestone tasks due from today through the upcoming Sunday
  // (inclusive) are counted.
  // Included statuses: PENDING & STARTED
  // Excluded statuses:  COMPLETED & CANCELLED_NOT_REQUIRED
  // Returns:
  // {
  //   'total': total pending + started milestone tasks,
  //   'pending': pending milestone tasks,
  //   'started': started milestone tasks,
  // }
  Future<Map<String, int>> getUpcomingMilestoneTaskCounts() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Existing helper returns the next Sunday.
    final upcomingSunday = nextSunday(today);
    final rows = await _db.query(
      'db_TaskLogWeekEnd',
      columns: const ['TaskStatus'],
      where: '''
      TaskID LIKE ?
      AND TaskDueDate >= ?
      AND TaskDueDate <= ?
      AND TaskStatus IN (?, ?)
    ''',
      whereArgs: [
        'MT_%',
        formatDate(today),
        formatDate(upcomingSunday),
        'PENDING',
        'STARTED',
      ],
    );

    var pendingCount = 0;
    var startedCount = 0;

    for (final row in rows) {
      final status = row['TaskStatus']?.toString().trim().toUpperCase();

      if (status == 'PENDING') {
        pendingCount++;
      } else if (status == 'STARTED') {
        startedCount++;
      }
    }

    return {
      'total': pendingCount + startedCount,
      'pending': pendingCount,
      'started': startedCount,
    };
  }

  Future<bool> tasksCreationRequired() async {
    final upcomingSunday = _upcomingSunday();

    final rows = await _db.query(
      'db_Milestones',
      where: 'milestone_date = ?',
      whereArgs: [upcomingSunday],
      limit: 1,
    );

    // No milestone record for this Sunday.
    // This means the Sunday is available for a PMT milestone.
    if (rows.isEmpty) {
      return true;
    }

    final row = rows.first;

    // ------------------------------------------------------------
    // PHYSICS
    // ------------------------------------------------------------
    final phyChapters = row['milestone_phy_chapters']?.toString().trim() ?? '';

    final phyTaskCreated = _toBool(row['milestone_phy_task_created']);

    if (phyChapters.isNotEmpty && !phyTaskCreated) {
      return true;
    }

    // ------------------------------------------------------------
    // CHEMISTRY
    // ------------------------------------------------------------
    final chemChapters =
        row['milestone_chem_chapters']?.toString().trim() ?? '';

    final chemTaskCreated = _toBool(row['milestone_chem_task_created']);

    if (chemChapters.isNotEmpty && !chemTaskCreated) {
      return true;
    }

    // ------------------------------------------------------------
    // BIOLOGY
    // ------------------------------------------------------------
    final bioChapters = row['milestone_bio_chapters']?.toString().trim() ?? '';

    final bioTaskCreated = _toBool(row['milestone_bio_task_created']);

    if (bioChapters.isNotEmpty && !bioTaskCreated) {
      return true;
    }

    // All subjects that have scope have their tasks created.
    return false;
  }

  String _upcomingSunday() {
    final today = DateTime.now();

    final daysUntilSunday = DateTime.sunday - today.weekday;

    final days = daysUntilSunday <= 0 ? daysUntilSunday + 7 : daysUntilSunday;

    final sunday = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(Duration(days: days));

    return '${sunday.year.toString().padLeft(4, '0')}-'
        '${sunday.month.toString().padLeft(2, '0')}-'
        '${sunday.day.toString().padLeft(2, '0')}';
  }

  bool _toBool(Object? value) {
    if (value is int) {
      return value == 1;
    }

    final text = value?.toString().trim().toLowerCase();

    return text == '1' || text == 'true' || text == 'yes';
  }

  Future<List<Map<String, Object?>>> getAllOpenMTasks() async {
    final rows = await _db.rawQuery('''
    SELECT
      t.*,
      m.milestone_type AS MilestoneType
    FROM db_TaskLogWeekEnd t
    INNER JOIN db_Milestones m
      ON date(t.TaskDueDate) = date(m.milestone_date)
    WHERE t.TaskID LIKE 'MT_%'
      AND UPPER(t.TaskStatus) NOT IN (
        'COMPLETED',
        'CANCELLED',
        'CANCELLED / NOT REQUIRED'
      )
    ORDER BY
      date(t.TaskDueDate) DESC,
      t.TaskID ASC
  ''');

    return rows;
  }

  MtTask? mtTaskFromRow(Map<String, Object?> row) {
    final id = row['TaskID']?.toString().trim();
    final description = row['TaskDescription']?.toString() ?? '';
    final dueText = row['TaskDueDate']?.toString();

    if (id == null || id.isEmpty || dueText == null || dueText.isEmpty) {
      return null;
    }

    final dueDate = DateTime.tryParse(dueText);

    if (dueDate == null) {
      return null;
    }

    final parts = id.split('_');

    final subject = parts.length >= 4 ? parts[3].trim().toUpperCase() : '';

    final statusText =
        (row['TaskStatus']?.toString() ?? 'PENDING').toUpperCase();

    final status = switch (statusText) {
      'IN_PROGRESS' || 'STARTED' => MtTaskStatus.started,
      'COMPLETED' => MtTaskStatus.completed,
      'CANCELLED' ||
      'CANCELLED / NOT REQUIRED' =>
        MtTaskStatus.cancelledNotRequired,
      _ => MtTaskStatus.pending,
    };

    return MtTask(
      id: id,
      title: description,
      subject: subject,
      dueDate: dueDate,
      status: status,
    );
  }

  Future<bool> areUpcomingMilestoneTasksPending() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final rows = await _db.rawQuery(
      '''
    SELECT
      milestone_date,
      milestone_phy_task_created,
      milestone_chem_task_created,
      milestone_bio_task_created
    FROM db_Milestones
    WHERE date(milestone_date) >= date(?)
    ORDER BY date(milestone_date) ASC
    LIMIT 1
    ''',
      [today.toIso8601String()],
    );

    if (rows.isEmpty) {
      return false;
    }

    final row = rows.first;
    final physicsCreated =
        (row['milestone_phy_task_created'] as num?)?.toInt() ?? 0;

    final chemistryCreated =
        (row['milestone_chem_task_created'] as num?)?.toInt() ?? 0;

    final biologyCreated =
        (row['milestone_bio_task_created'] as num?)?.toInt() ?? 0;

    return physicsCreated == 0 || chemistryCreated == 0 || biologyCreated == 0;
  }

  /// Returns all milestone tasks whose due date falls within
  /// the current Monday-Sunday week.
  ///

  Future<List<Map<String, Object?>>> getThisWeekMTasks() async {
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final startOfWeek = today.subtract(
      Duration(days: today.weekday - DateTime.monday),
    );

    final endOfWeek = startOfWeek.add(const Duration(days: 6));

    return _db.query(
      'db_TaskLogWeekEnd',
      where: '''
      TaskID LIKE ?
      AND TaskDueDate >= ?
      AND TaskDueDate <= ?
    ''',
      whereArgs: ['MT_%', formatDate(startOfWeek), formatDate(endOfWeek)],
      orderBy: 'TaskDueDate ASC',
    );
  }

  // Returns all milestone tasks regardless of status.
  Future<List<Map<String, Object?>>> getAllMTasks() async {
    return _db.query(
      'db_TaskLogWeekEnd',
      where: 'TaskID LIKE ?',
      whereArgs: ['MT_%'],
      orderBy: 'TaskDueDate ASC',
    );
  }

  /// Returns milestone tasks filtered by task status.
  ///
  /// [status] should match the value stored in db_TaskLogWeekEnd.
  ///
  /// Examples:
  ///   getMTasksByStatus('PENDING')
  ///   getMTasksByStatus('STARTED')
  ///   getMTasksByStatus('COMPLETED')
  Future<List<Map<String, Object?>>> getMTasksByStatus(String status) async {
    final normalizedStatus = status.trim().toUpperCase();

    if (normalizedStatus.isEmpty) {
      return const [];
    }

    return _db.query(
      'db_TaskLogWeekEnd',
      where: '''
      TaskID LIKE ?
      AND TaskStatus = ?
    ''',
      whereArgs: ['MT_%', normalizedStatus],
      orderBy: 'TaskDueDate ASC',
    );
  }

  Future<void> markCommonTasksCreated({
    required String milestoneType,
    required DateTime date,
  }) async {
    await _db.update(
      table,
      {colCommonTaskCreated: 1},
      where: '$colType = ? AND $colDate = ?',
      whereArgs: [milestoneType.trim(), formatDate(date)],
    );
  }

  Future<Map<String, Object?>?> getMilestone({
    required String milestoneType,
    required DateTime date,
  }) async {
    final rows = await _db.query(
      table,
      where: '$colType = ? AND $colDate = ?',
      whereArgs: [milestoneType.trim(), formatDate(date)],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> getAnyMilestoneForDate(DateTime date) async {
    final rows = await _db.query(
      table,
      where: '$colDate = ?',
      whereArgs: [formatDate(date)],
      orderBy: '$colType ASC',
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> getMilestonesForDate(DateTime date) {
    return _db.query(
      table,
      where: '$colDate = ?',
      whereArgs: [formatDate(date)],
      orderBy: '$colType ASC',
    );
  }

  Future<List<Map<String, Object?>>> getUpcomingMilestones({
    DateTime? from,
    int? limit,
  }) {
    final start = formatDate(from ?? DateTime.now());
    return _db.query(
      table,
      where: '$colDate >= ?',
      whereArgs: [start],
      orderBy: '$colDate ASC, $colType ASC',
      limit: limit,
    );
  }

  Future<bool> hasMilestoneOnDate(DateTime date) async {
    final rows = await getMilestonesForDate(date);
    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> getMilestonesInRange({
    required DateTime from,
    required DateTime to,
  }) {
    return _db.query(
      table,
      where: '$colDate >= ? AND $colDate <= ?',
      whereArgs: [formatDate(from), formatDate(to)],
      orderBy: '$colDate ASC, $colType ASC',
    );
  }

  Future<Set<String>> getOccupiedMilestoneDates({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await getMilestonesInRange(from: from, to: to);

    return rows
        .map((row) => row[colDate]?.toString())
        .whereType<String>()
        .where((date) => date.isNotEmpty)
        .toSet();
  }

  /// Returns the next available milestone for the dashboard widget.
  ///
  /// Starts from [from] date. If [from] is not supplied, today's date
  /// is used.
  ///
  /// Returns null when there is no upcoming milestone.
  Future<Milestone?> getUpcomingMilestoneForWidget({DateTime? from}) async {
    final startDate = formatDate(from ?? DateTime.now());
    final rows = await _db.query(
      table,
      where: '$colDate >= ?',
      whereArgs: [startDate],
      orderBy: '$colDate ASC, $colType ASC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Milestone.fromMap(rows.first);
  }

  Future<List<Map<String, Object?>>> getNextSundayMilestones() {
    return getMilestonesForDate(nextSunday(DateTime.now()));
  }

  /// Returns upcoming milestone rows enriched with chapter names from
  /// db_SyllabusMaster. The original database columns remain unchanged.
  Future<List<Map<String, Object?>>> getUpcomingMilestonesWithNames({
    DateTime? from,
    int? limit,
  }) async {
    final rows = await getUpcomingMilestones(from: from, limit: limit);
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final copy = <String, Object?>{...row};
      copy['scope'] = await resolveScope(row);
      result.add(copy);
    }
    return result;
  }

  Future<List<Map<String, Object?>>> getNextSundayMilestonesWithNames() async {
    final rows = await getMilestonesForDate(nextSunday(DateTime.now()));
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      final copy = <String, Object?>{...row};
      copy['scope'] = await resolveScope(row);
      result.add(copy);
    }
    return result;
  }

  /// Inserts a new milestone or updates the scope for the same
  /// (milestone_type, milestone_date) key.
  Future<void> saveMilestone({
    required String milestoneType,
    required DateTime date,
    required String phyChapters,
    required String chemChapters,
    required String bioChapters,
  }) async {
    final type = milestoneType.trim();

    if (type.isEmpty) {
      throw ArgumentError('Milestone type is required.');
    }

    if (!isMilestoneSunday(date)) {
      throw ArgumentError('Milestone date must be a Sunday.');
    }

    final formattedDate = formatDate(date);

    // Check whether this milestone already exists.
    final existing = await getMilestone(milestoneType: type, date: date);

    if (existing == null) {
      // NEW milestone:
      // task-created flags start at 0.
      await _db.insert(table, {
        colType: type,
        colDate: formattedDate,
        colPhy: normalizeCodes(phyChapters),
        colPhyTaskCreated: 0,
        colChem: normalizeCodes(chemChapters),
        colChemTaskCreated: 0,
        colBio: normalizeCodes(bioChapters),
        colBioTaskCreated: 0,
        'milestone_timestamp': DateTime.now().toIso8601String(),
      });
    } else {
      // EXISTING milestone:
      // update the chapter scope but PRESERVE task-created flags.
      await _db.update(
        table,
        {
          colPhy: normalizeCodes(phyChapters),
          colChem: normalizeCodes(chemChapters),
          colBio: normalizeCodes(bioChapters),
          'milestone_timestamp': DateTime.now().toIso8601String(),
        },
        where: '$colType = ? AND $colDate = ?',
        whereArgs: [type, formattedDate],
      );
    }
  }

  Future<void> markPhyTasksCreated({
    required String milestoneType,
    required DateTime date,
  }) async {
    await _db.update(
      table,
      {colPhyTaskCreated: 1},
      where: '$colType = ? AND $colDate = ?',
      whereArgs: [milestoneType.trim(), formatDate(date)],
    );
  }

  Future<void> markChemTasksCreated({
    required String milestoneType,
    required DateTime date,
  }) async {
    await _db.update(
      table,
      {colChemTaskCreated: 1},
      where: '$colType = ? AND $colDate = ?',
      whereArgs: [milestoneType.trim(), formatDate(date)],
    );
  }

  Future<void> markBioTasksCreated({
    required String milestoneType,
    required DateTime date,
  }) async {
    await _db.update(
      table,
      {colBioTaskCreated: 1},
      where: '$colType = ? AND $colDate = ?',
      whereArgs: [milestoneType.trim(), formatDate(date)],
    );
  }

  Future<void> updateMilestoneScope({
    required String milestoneType,
    required DateTime date,
    required String phyChapters,
    required String chemChapters,
    required String bioChapters,
  }) {
    return saveMilestone(
      milestoneType: milestoneType,
      date: date,
      phyChapters: phyChapters,
      chemChapters: chemChapters,
      bioChapters: bioChapters,
    );
  }

  Future<void> deleteMilestone({
    required String milestoneType,
    required DateTime date,
  }) async {
    await _db.delete(
      table,
      where: '$colType = ? AND $colDate = ?',
      whereArgs: [milestoneType.trim(), formatDate(date)],
    );
  }

  /// Resolves the comma-separated chapter codes in one milestone row into
  /// display-friendly subject/chapter information from db_SyllabusMaster.
  Future<Map<String, List<Map<String, Object?>>>> resolveScope(
    Map<String, Object?> milestone,
  ) async {
    final result = <String, List<Map<String, Object?>>>{
      'Phy': [],
      'Chem': [],
      'Bio': [],
    };

    await _resolveSubjectScope(
      result,
      subjectKey: 'Phy',
      subjectCodes: const ['PHY', 'PHYSICS', 'PHY'],
      rawCodes: milestone[colPhy]?.toString(),
    );
    await _resolveSubjectScope(
      result,
      subjectKey: 'Chem',
      subjectCodes: const ['CHEM', 'CHEMISTRY', 'CHEM'],
      rawCodes: milestone[colChem]?.toString(),
    );
    await _resolveSubjectScope(
      result,
      subjectKey: 'Bio',
      subjectCodes: const ['BIO', 'BIOLOGY'],
      rawCodes: milestone[colBio]?.toString(),
    );

    return result;
  }

  Future<void> _resolveSubjectScope(
    Map<String, List<Map<String, Object?>>> result, {
    required String subjectKey,
    required List<String> subjectCodes,
    required String? rawCodes,
  }) async {
    final codes = splitCodes(rawCodes);
    if (codes.isEmpty) return;

    final rows = <Map<String, Object?>>[];
    for (final chapterCode in codes) {
      Map<String, Object?>? found;
      for (final subjectCode in subjectCodes) {
        final matches = await _db.query(
          'db_SyllabusMaster',
          where: 'UPPER(subject_code) = ? AND UPPER(chapter_code) = ?',
          whereArgs: [subjectCode.toUpperCase(), chapterCode.toUpperCase()],
          limit: 1,
        );
        if (matches.isNotEmpty) {
          found = matches.first;
          break;
        }
      }

      found ??= {'chapter_code': chapterCode, 'chapter_name': chapterCode};
      rows.add(found);
    }

    result[subjectKey] = rows;
  }

  static List<String> splitCodes(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String normalizeCodes(String value) {
    return splitCodes(value).join(',');
  }

  static String formatDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  /// UI display format for every milestone date.
  ///
  /// Database storage remains YYYY-MM-DD. Milestone dates are Sunday-only,
  /// so the displayed value is always: Sunday, DD-MMM-YYYY.
  static String formatDisplayDate(DateTime date) {
    if (date.weekday != DateTime.sunday) {
      return 'Invalid milestone date';
    }

    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return 'Sunday, ${date.day.toString().padLeft(2, '0')}-'
        '${months[date.month - 1]}-${date.year}';
  }

  static bool isMilestoneSunday(DateTime date) =>
      date.weekday == DateTime.sunday;

  static DateTime parseDate(String value) {
    return DateTime.parse(value);
  }

  static DateTime nextSunday(DateTime from) {
    final day = DateTime(from.year, from.month, from.day);
    final delta = DateTime.sunday - day.weekday;
    return day.add(Duration(days: delta == 0 ? 7 : delta));
  }
}
