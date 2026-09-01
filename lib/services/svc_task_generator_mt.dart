import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Milestone Task Generator
///
/// Creates milestone tasks from:
///
///   db_Milestones
///        ↓
///   db_Milestones_TC_Rules
///        ↓
///   db_SubjectTasks
///        ↓
///   db_SubjectTaskActivities
///        ↓
///   db_Activities
///
/// FINAL TASK CREATION RULES
///
/// 1. PHY_CMT_FSR
///    - ONE task for Physics
///    - ONE activity-status record for that task
///    - Every chapter in milestone scope becomes an individual
///      true/false entry in the same ActivityStatusJSON.
///
/// 2. CHE_CMT_FSR
///    - ONE task for Chemistry
///    - ONE activity-status record for that task
///    - Every chapter in milestone scope becomes an individual
///      true/false entry in the same ActivityStatusJSON.
///
/// 3. BIO_CMT_FSR
///    - ONE task for Biology
///    - ONE activity-status record for that task
///    - Every chapter in milestone scope becomes an individual
///      true/false entry in the same ActivityStatusJSON.
///
/// 4. PCB_CMT_TEST
///    - ONE task
///    - Uses all existing activities from:
///        db_SubjectTaskActivities
///        db_Activities
///
/// No database schema change is required.
class MtTaskGenerator {
  MtTaskGenerator({required Database db, DateTime Function()? now})
      : _db = db,
        _now = now ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;

  // ===========================================================================
  // TABLES
  // ===========================================================================

  static const String _milestoneTable = 'db_Milestones';

  static const String _ruleTable = 'db_Milestones_TC_Rules';

  static const String _subjectTaskTable = 'db_SubjectTasks';

  static const String _subjectTaskActivityTable = 'db_SubjectTaskActivities';

  static const String _activityTable = 'db_Activities';

  static const String _syllabusTable = 'db_SyllabusMaster';

  static const String _taskLogTable = 'db_TaskLogWeekEnd';

  static const String _taskActivityStatusTable = 'db_TaskActivityStatus';

  // ===========================================================================
  // MILESTONE COLUMNS
  // ===========================================================================

  static const String _milestoneDateColumn = 'milestone_date';

  static const String _milestoneTypeColumn = 'milestone_type';

  static const String _phyColumn = 'milestone_phy_chapters';

  static const String _chemColumn = 'milestone_chem_chapters';

  static const String _bioColumn = 'milestone_bio_chapters';

  static const String _phyTaskCreatedColumn = 'milestone_phy_task_created';

  static const String _chemTaskCreatedColumn = 'milestone_chem_task_created';

  static const String _bioTaskCreatedColumn = 'milestone_bio_task_created';

  static const String _commonTasksCreatedColumn =
      'milestone_common_tasks_created';

  // ===========================================================================
  // RULE COLUMNS
  // ===========================================================================

  static const String _ruleIdColumn = 'MT_Rule_ID';

  static const String _ruleActiveColumn = 'MT_Rule_IsActive';

  static const String _ruleTypeColumn = 'MT_Type';

  static const String _ruleSubjectColumn = 'MT_Subject_Code';

  static const String _ruleDescriptionColumn = 'MT_Rule_Description';

  // ===========================================================================
  // SUBJECT TASK COLUMNS
  // ===========================================================================

  static const String _subjectTaskIdColumn = 'SubjectTaskID';

  static const String _subjectTaskNameColumn = 'SubjectTaskName';

  static const String _subjectTaskActiveColumn = 'SubjectTaskIsActive';

  static const String _subjectTaskDurationColumn = 'SubjectTaskDurationMinutes';

  // ===========================================================================
  // PUBLIC METHOD
  // ===========================================================================

  Future<Map<String, int>> generateMilestoneTasks({
    required String mtType,
    DateTime? milestoneDate,
  }) async {
    final date = _dateOnly(milestoneDate ?? _now());

    final normalizedType = mtType.trim().toUpperCase();

    if (normalizedType.isEmpty) {
      throw ArgumentError('MT Type cannot be empty.');
    }

    if (date.weekday != DateTime.sunday) {
      throw ArgumentError(
        'Milestone task generation requires a Sunday milestone date.',
      );
    }

    final milestone = await _getMilestone(date, normalizedType);

    if (milestone == null) {
      return const {'PHY': 0, 'CHEM': 0, 'BIO': 0, 'PCB': 0};
    }

    final results = <String, int>{'PHY': 0, 'CHEM': 0, 'BIO': 0, 'PCB': 0};

    // =========================================================================
    // PHYSICS
    // =========================================================================

    results['PHY'] = await _processSubject(
      milestone: milestone,
      subjectCode: 'PHY',
      mtType: normalizedType,
    );

    // =========================================================================
    // CHEMISTRY
    // =========================================================================

    results['CHEM'] = await _processSubject(
      milestone: milestone,
      subjectCode: 'CHEM',
      mtType: normalizedType,
    );

    // =========================================================================
    // BIOLOGY
    // =========================================================================

    results['BIO'] = await _processSubject(
      milestone: milestone,
      subjectCode: 'BIO',
      mtType: normalizedType,
    );

    // =========================================================================
    // PCB COMMON TASK
    // =========================================================================

    results['PCB'] = await _processCommonTasks(
      milestone: milestone,
      milestoneDate: date,
      mtType: normalizedType,
    );

    return results;
  }

  // ===========================================================================
  // SUBJECT PROCESSING
  // ===========================================================================

  Future<int> _processSubject({
    required Map<String, Object?> milestone,
    required String subjectCode,
    required String mtType,
  }) async {
    final chapters = _milestoneScope(milestone, subjectCode);

    if (chapters.isEmpty) {
      return 0;
    }

    final rules = await _getRulesForSubject(subjectCode, mtType);

    if (rules.isEmpty) {
      return 0;
    }

    var taskCount = 0;

    for (final rule in rules) {
      final ruleSubjectCode = _string(rule[_ruleSubjectColumn]);

      final ruleType = _string(rule[_ruleTypeColumn]);

      if (ruleSubjectCode == null || ruleType == null) {
        continue;
      }

      final partialKey = '${ruleSubjectCode}_'
          '${ruleType}_';

      final subjectTasks = await _getSubjectTasksByPartialKey(partialKey);

      if (subjectTasks.isEmpty) {
        continue;
      }

      for (final subjectTask in subjectTasks) {
        final subjectTaskId = _string(subjectTask[_subjectTaskIdColumn]);

        if (subjectTaskId == null) {
          continue;
        }

        // =====================================================================
        // SYLLABUS REVISION TASK
        //
        // One task for the complete subject scope.
        //
        // Example:
        //
        // PHY_CMT_FSR
        //
        // becomes:
        //
        // ONE task
        //
        // ActivityStatusJSON:
        //
        // {
        //   "Physics - Chapter 1": false,
        //   "Physics - Chapter 2": false,
        //   "Physics - Chapter 3": false
        // }
        // =====================================================================

        if (_isSyllabusRevisionTask(subjectTask, rule)) {
          final created = await _createSyllabusRevisionTask(
            subjectTask: subjectTask,
            rule: rule,
            milestoneDate: _parseMilestoneDate(milestone),
            subjectCode: subjectCode,
            chapterCodes: chapters,
          );

          if (created) {
            taskCount++;
          }

          continue;
        }

        // =====================================================================
        // NORMAL SUBJECT MILESTONE TASK
        // =====================================================================

        final created = await _createTaskFromSubjectTask(
          subjectTask: subjectTask,
          rule: rule,
          milestoneDate: _parseMilestoneDate(milestone),
        );

        if (created) {
          taskCount++;
        }
      }
    }

    if (taskCount > 0) {
      await _markSubjectTasksCreated(
        subjectCode: subjectCode,
        milestone: milestone,
      );
    }

    return taskCount;
  }

  // ===========================================================================
  // SYLLABUS REVISION DETECTION
  // ===========================================================================

  bool _isSyllabusRevisionTask(
    Map<String, Object?> subjectTask,
    Map<String, Object?> rule,
  ) {
    final subjectTaskId =
        _string(subjectTask[_subjectTaskIdColumn])?.toUpperCase() ?? '';

    final subjectTaskName =
        _string(subjectTask[_subjectTaskNameColumn])?.toUpperCase() ?? '';

    final ruleDescription =
        _string(rule[_ruleDescriptionColumn])?.toUpperCase() ?? '';

    return subjectTaskId.contains('FSR') ||
        subjectTaskId.contains('SYLLABUS') ||
        subjectTaskId.contains('REVISION') ||
        subjectTaskName.contains('SYLLABUS') ||
        subjectTaskName.contains('REVISION') ||
        ruleDescription.contains('SYLLABUS');
  }

  // ===========================================================================
  // CREATE ONE SUBJECT SYLLABUS REVISION TASK
  // ===========================================================================

  Future<bool> _createSyllabusRevisionTask({
    required Map<String, Object?> subjectTask,
    required Map<String, Object?> rule,
    required DateTime milestoneDate,
    required String subjectCode,
    required List<String> chapterCodes,
  }) async {
    final subjectTaskId = _string(subjectTask[_subjectTaskIdColumn]);

    if (subjectTaskId == null) {
      return false;
    }

    if (chapterCodes.isEmpty) {
      return false;
    }

    final ruleId = _string(rule[_ruleIdColumn]) ?? '0';

    // =========================================================================
    // ONE TASK ID ONLY
    // =========================================================================

    final taskId = _buildTaskId(
      milestoneDate: milestoneDate,
      ruleId: ruleId,
      subjectTaskId: subjectTaskId,
    );

    final taskDescription =
        _string(subjectTask[_subjectTaskNameColumn]) ?? subjectTaskId;

    // =========================================================================
    // Build chapter activity JSON.
    //
    // Every chapter becomes an individual activity-like entry,
    // but all entries belong to ONE task and ONE status record.
    // =========================================================================

    final activityStatus = <String, bool>{};

    for (final chapterCode in chapterCodes) {
      final chapter = await _getChapterInfo(
        subjectCode: subjectCode,
        chapterCode: chapterCode,
      );

      final chapterName = _string(chapter?['chapter_name']);

      final displayName = chapterName ?? chapterCode;

      activityStatus[displayName] = false;
    }

    if (activityStatus.isEmpty) {
      return false;
    }

    // =========================================================================
    // Duration
    // =========================================================================

    final activities = await _getActivitiesForSubjectTask(subjectTaskId);

    final duration = _taskDuration(subjectTask, activities);

    // =========================================================================
    // ONE TASK + ONE ACTIVITY STATUS RECORD
    // =========================================================================

    return _createTaskWithActivityJson(
      taskId: taskId,
      taskDescription: taskDescription,
      dueDate: milestoneDate,
      durationMinutes: duration,
      activityStatus: activityStatus,
    );
  }

  // ===========================================================================
  // CREATE TASK WITH CUSTOM ACTIVITY JSON
  // ===========================================================================

  Future<bool> _createTaskWithActivityJson({
    required String taskId,
    required String taskDescription,
    required DateTime dueDate,
    required int durationMinutes,
    required Map<String, bool> activityStatus,
  }) async {
    // =========================================================================
    // TASK
    // =========================================================================

    final existingTask = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [taskId],
      limit: 1,
    );

    if (existingTask.isEmpty) {
      await _db.insert(
          _taskLogTable,
          <String, Object?>{
            'TaskID': taskId,
            'TaskDescription': taskDescription,
            'TaskDueDate': _formatDate(dueDate),
            'TaskStartTime': null,
            'TaskDurationMinutes': durationMinutes,
            'TaskCalendarEventID': null,
            'TaskReminderMinutes': null,
            'TaskStatus': 'PENDING',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // =========================================================================
    // ONE ACTIVITY STATUS RECORD
    // =========================================================================

    final existingStatus = await _db.query(
      _taskActivityStatusTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [taskId],
      limit: 1,
    );

    if (existingStatus.isEmpty) {
      await _db.insert(
          _taskActivityStatusTable,
          <String, Object?>{
            'TaskID': taskId,
            'ActivityStatusJSON': jsonEncode(activityStatus),
            'TaskActivityUpdatedDate': _now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    return true;
  }

  // ===========================================================================
  // CHAPTER LOOKUP
  // ===========================================================================

  Future<Map<String, Object?>?> _getChapterInfo({
    required String subjectCode,
    required String chapterCode,
  }) async {
    final normalizedSubject = _normalizeSubjectCode(subjectCode);

    final subjectCandidates = switch (normalizedSubject) {
      'PHY' => const ['PHY', 'PHYSICS'],
      'CHEM' => const ['CHEM', 'CHEMISTRY'],
      'BIO' => const ['BIO', 'BIOLOGY'],
      _ => <String>[],
    };

    for (final candidate in subjectCandidates) {
      final rows = await _db.query(
        _syllabusTable,
        where: 'UPPER(subject_code) = ? '
            'AND UPPER(chapter_code) = ?',
        whereArgs: [candidate.toUpperCase(), chapterCode.toUpperCase()],
        limit: 1,
      );

      if (rows.isNotEmpty) {
        return rows.first;
      }
    }

    return null;
  }

  // ===========================================================================
  // PCB COMMON TASK
  // ===========================================================================

  Future<int> _processCommonTasks({
    required Map<String, Object?> milestone,
    required DateTime milestoneDate,
    required String mtType,
  }) async {
    final pcbSubjectTaskId = 'PCB_${mtType}_TEST';

    final subjectTask = await _getSubjectTaskById(pcbSubjectTaskId);

    if (subjectTask == null) {
      return 0;
    }

    final activities = await _getActivitiesForSubjectTask(pcbSubjectTaskId);

    if (activities.isEmpty) {
      return 0;
    }

    final taskDescription =
        _string(subjectTask[_subjectTaskNameColumn]) ?? pcbSubjectTaskId;

    final duration = _taskDuration(subjectTask, activities);

    final taskId = _buildTaskId(
      milestoneDate: milestoneDate,
      ruleId: 'PCB',
      subjectTaskId: pcbSubjectTaskId,
    );

    final result = await _createTaskAndActivityStatus(
      taskId: taskId,
      taskDescription: taskDescription,
      dueDate: milestoneDate,
      durationMinutes: duration,
      activities: activities,
    );

    if (result) {
      await _markCommonTasksCreated(milestone: milestone);

      return 1;
    }

    return 0;
  }

  // ===========================================================================
  // NORMAL SUBJECT TASK
  // ===========================================================================

  Future<bool> _createTaskFromSubjectTask({
    required Map<String, Object?> subjectTask,
    required Map<String, Object?> rule,
    required DateTime milestoneDate,
  }) async {
    final subjectTaskId = _string(subjectTask[_subjectTaskIdColumn]);

    if (subjectTaskId == null) {
      return false;
    }

    final subjectTaskName =
        _string(subjectTask[_subjectTaskNameColumn]) ?? subjectTaskId;

    final ruleId = _string(rule[_ruleIdColumn]) ?? '0';

    final activities = await _getActivitiesForSubjectTask(subjectTaskId);

    if (activities.isEmpty) {
      return false;
    }

    final duration = _taskDuration(subjectTask, activities);

    final taskId = _buildTaskId(
      milestoneDate: milestoneDate,
      ruleId: ruleId,
      subjectTaskId: subjectTaskId,
    );

    return _createTaskAndActivityStatus(
      taskId: taskId,
      taskDescription: subjectTaskName,
      dueDate: milestoneDate,
      durationMinutes: duration,
      activities: activities,
    );
  }

  // ===========================================================================
  // NORMAL TASK + EXISTING ACTIVITIES
  // ===========================================================================

  Future<bool> _createTaskAndActivityStatus({
    required String taskId,
    required String taskDescription,
    required DateTime dueDate,
    required int durationMinutes,
    required List<Map<String, Object?>> activities,
  }) async {
    // =========================================================================
    // TASK
    // =========================================================================

    final existingTask = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [taskId],
      limit: 1,
    );

    if (existingTask.isEmpty) {
      await _db.insert(
          _taskLogTable,
          <String, Object?>{
            'TaskID': taskId,
            'TaskDescription': taskDescription,
            'TaskDueDate': _formatDate(dueDate),
            'TaskStartTime': null,
            'TaskDurationMinutes': durationMinutes,
            'TaskCalendarEventID': null,
            'TaskReminderMinutes': null,
            'TaskStatus': 'PENDING',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // =========================================================================
    // EXISTING ACTIVITIES
    // =========================================================================

    final activityStatus = <String, bool>{};

    for (final activity in activities) {
      final activityId = _string(activity['ActivityID']);

      if (activityId == null) {
        continue;
      }

      activityStatus[activityId] = false;
    }

    if (activityStatus.isEmpty) {
      return false;
    }

    // =========================================================================
    // ONE STATUS RECORD
    // =========================================================================

    final existingStatus = await _db.query(
      _taskActivityStatusTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [taskId],
      limit: 1,
    );

    if (existingStatus.isEmpty) {
      await _db.insert(
          _taskActivityStatusTable,
          <String, Object?>{
            'TaskID': taskId,
            'ActivityStatusJSON': jsonEncode(activityStatus),
            'TaskActivityUpdatedDate': _now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    return true;
  }

  // ===========================================================================
  // RULE LOOKUP
  // ===========================================================================

  Future<List<Map<String, Object?>>> _getRulesForSubject(
    String subjectCode,
    String mtType,
  ) async {
    final normalizedSubject = _normalizeSubjectCode(subjectCode);

    final normalizedType = mtType.trim().toUpperCase();

    final rows = await _db.query(
      _ruleTable,
      where: '$_ruleActiveColumn = ? '
          'AND $_ruleTypeColumn = ?',
      whereArgs: [1, normalizedType],
      orderBy: '$_ruleIdColumn ASC',
    );

    final result = <Map<String, Object?>>[];

    for (final row in rows) {
      final ruleSubject = _string(row[_ruleSubjectColumn])?.toUpperCase();

      final normalizedRuleSubject =
          ruleSubject == null ? null : _normalizeSubjectCode(ruleSubject);

      if (normalizedRuleSubject == normalizedSubject) {
        result.add(row);
      }
    }

    return result;
  }

  // ===========================================================================
  // SUBJECT TASK LOOKUP
  // ===========================================================================

  Future<List<Map<String, Object?>>> _getSubjectTasksByPartialKey(
    String partialKey,
  ) async {
    return _db.query(
      _subjectTaskTable,
      where: '$_subjectTaskIdColumn LIKE ? '
          'AND $_subjectTaskActiveColumn = ?',
      whereArgs: ['$partialKey%', 'Yes'],
      orderBy: '$_subjectTaskIdColumn ASC',
    );
  }

  // ===========================================================================
  // SUBJECT TASK BY ID
  // ===========================================================================

  Future<Map<String, Object?>?> _getSubjectTaskById(
    String subjectTaskId,
  ) async {
    final rows = await _db.query(
      _subjectTaskTable,
      where: '$_subjectTaskIdColumn = ? '
          'AND $_subjectTaskActiveColumn = ?',
      whereArgs: [subjectTaskId, 'Yes'],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  // ===========================================================================
  // ACTIVITIES
  // ===========================================================================

  Future<List<Map<String, Object?>>> _getActivitiesForSubjectTask(
    String subjectTaskId,
  ) async {
    final links = await _db.query(
      _subjectTaskActivityTable,
      where: 'SubjectTaskID = ?',
      whereArgs: [subjectTaskId],
      orderBy: 'ActivitySequence ASC',
    );

    if (links.isEmpty) {
      return const [];
    }

    final result = <Map<String, Object?>>[];

    for (final link in links) {
      final activityId = _string(link['ActivityID']);

      if (activityId == null) {
        continue;
      }

      final activityRows = await _db.query(
        _activityTable,
        where: 'ActivityID = ? '
            'AND IsActive = ?',
        whereArgs: [activityId, 'Yes'],
        limit: 1,
      );

      if (activityRows.isEmpty) {
        continue;
      }

      result.add(<String, Object?>{...link, ...activityRows.first});
    }

    return result;
  }

  // ===========================================================================
  // DURATION
  // ===========================================================================

  int _taskDuration(
    Map<String, Object?> subjectTask,
    List<Map<String, Object?>> activities,
  ) {
    final configured = _int(subjectTask[_subjectTaskDurationColumn]);

    if (configured != null) {
      return configured;
    }

    return activities.fold<int>(
      0,
      (sum, row) => sum + (_int(row['ActivityDurationMinutes']) ?? 0),
    );
  }

  // ===========================================================================
  // MILESTONE LOOKUP
  // ===========================================================================

  Future<Map<String, Object?>?> _getMilestone(
    DateTime date,
    String mtType,
  ) async {
    final rows = await _db.query(
      _milestoneTable,
      where: '$_milestoneTypeColumn = ? '
          'AND $_milestoneDateColumn = ?',
      whereArgs: [mtType.trim().toUpperCase(), _formatDate(date)],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  // ===========================================================================
  // MILESTONE CHAPTER SCOPE
  // ===========================================================================

  List<String> _milestoneScope(
    Map<String, Object?> milestone,
    String subjectCode,
  ) {
    final normalizedSubject = _normalizeSubjectCode(subjectCode);

    final column = switch (normalizedSubject) {
      'PHY' => _phyColumn,
      'CHEM' => _chemColumn,
      'BIO' => _bioColumn,
      _ => null,
    };

    if (column == null) {
      return const [];
    }

    return _splitCodes(milestone[column]?.toString());
  }

  // ===========================================================================
  // MARK SUBJECT TASKS CREATED
  // ===========================================================================

  Future<void> _markSubjectTasksCreated({
    required String subjectCode,
    required Map<String, Object?> milestone,
  }) async {
    final normalizedSubject = _normalizeSubjectCode(subjectCode);

    final column = switch (normalizedSubject) {
      'PHY' => _phyTaskCreatedColumn,
      'CHEM' => _chemTaskCreatedColumn,
      'BIO' => _bioTaskCreatedColumn,
      _ => null,
    };

    if (column == null) {
      return;
    }

    await _db.update(
      _milestoneTable,
      {column: 1},
      where: '$_milestoneTypeColumn = ? '
          'AND $_milestoneDateColumn = ?',
      whereArgs: [
        milestone[_milestoneTypeColumn],
        milestone[_milestoneDateColumn],
      ],
    );
  }

  // ===========================================================================
  // MARK COMMON TASKS CREATED
  // ===========================================================================

  Future<void> _markCommonTasksCreated({
    required Map<String, Object?> milestone,
  }) async {
    await _db.update(
      _milestoneTable,
      {_commonTasksCreatedColumn: 1},
      where: '$_milestoneTypeColumn = ? '
          'AND $_milestoneDateColumn = ?',
      whereArgs: [
        milestone[_milestoneTypeColumn],
        milestone[_milestoneDateColumn],
      ],
    );
  }

  // ===========================================================================
  // TASK ID
  // ===========================================================================

  String _buildTaskId({
    required DateTime milestoneDate,
    required String ruleId,
    required String subjectTaskId,
  }) {
    final compactDate = _compactDate(milestoneDate);

    return 'MT_${compactDate}_'
        '${ruleId}_'
        '$subjectTaskId';
  }

  // ===========================================================================
  // SUBJECT NORMALIZATION
  // ===========================================================================

  String _normalizeSubjectCode(String value) {
    final code = value.trim().toUpperCase();

    switch (code) {
      case 'PHYSICS':
      case 'PHY':
        return 'PHY';

      case 'CHEMISTRY':
      case 'CHEM':
      case 'CHE':
      case 'BHEM':
        return 'CHEM';

      case 'BIOLOGY':
      case 'BIO':
        return 'BIO';

      case 'PCB':
        return 'PCB';

      default:
        return code;
    }
  }

  // ===========================================================================
  // DATE HELPERS
  // ===========================================================================

  DateTime _parseMilestoneDate(Map<String, Object?> milestone) {
    final value = _string(milestone[_milestoneDateColumn]);

    if (value == null) {
      throw StateError('Milestone date is missing.');
    }

    return DateTime.parse(value);
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  static String _compactDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ===========================================================================
  // GENERIC HELPERS
  // ===========================================================================

  static List<String> _splitCodes(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const [];
    }

    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }
}
