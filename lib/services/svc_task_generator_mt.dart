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
/// PARENT TASK
///
/// The existing db_TaskLogWeekEnd generation is intentionally preserved.
///
/// SUBTASK TRACKING
///
/// The old db_TaskActivityStatus / ActivityStatusJSON system has been
/// completely retired.
///
/// db_SubTasksMT is now the authoritative subtask tracking table.
///
/// FSR:
///   - ONE parent task in db_TaskLogWeekEnd
///   - ONE db_SubTasksMT row per milestone chapter
///
/// Normal PHY/CHEM/BIO activity task:
///   - ONE parent task in db_TaskLogWeekEnd
///   - ONE db_SubTasksMT row per existing activity
///
/// PCB:
///   - ONE parent task in db_TaskLogWeekEnd
///   - ONE db_SubTasksMT row per existing PCB activity
///
/// IMPORTANT:
///
/// The existing SubjectTask -> SubjectTaskActivities -> Activities
/// relationship is NOT changed.
class MtTaskGenerator {
  MtTaskGenerator({
    required Database db,
    DateTime Function()? now,
  })  : _db = db,
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

  static const String _subTaskLogTable = 'db_SubTasksMT';

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

    // =========================================================================
    // EXISTING WEEKEND/SUNDAY RULE
    // =========================================================================

    if (date.weekday != DateTime.sunday) {
      throw ArgumentError(
        'Milestone task generation requires a Sunday milestone date.',
      );
    }

    // =========================================================================
    // EXISTING MILESTONE LOOKUP
    // =========================================================================

    final milestone = await _getMilestone(
      date,
      normalizedType,
    );

    if (milestone == null) {
      return const {
        'PHY': 0,
        'CHEM': 0,
        'BIO': 0,
        'PCB': 0,
      };
    }

    final results = <String, int>{
      'PHY': 0,
      'CHEM': 0,
      'BIO': 0,
      'PCB': 0,
    };

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
    // =========================================================================
    // EXISTING MILESTONE SUBJECT SCOPE
    // =========================================================================

    final chapters = _milestoneScope(
      milestone,
      subjectCode,
    );

    // =========================================================================
    // EXISTING RULE LOOKUP
    //
    // IMPORTANT:
    // We do this even when chapters are empty so that an existing FSR parent
    // task can still be reconciled and its old chapters can be cancelled.
    // =========================================================================

    final rules = await _getRulesForSubject(
      subjectCode,
      mtType,
    );

    if (rules.isEmpty) {
      return 0;
    }

    var subTaskCount = 0;

    for (final rule in rules) {
      final ruleSubjectCode = _string(rule[_ruleSubjectColumn]);

      final ruleType = _string(rule[_ruleTypeColumn]);

      if (ruleSubjectCode == null || ruleType == null) {
        continue;
      }

      // =========================================================================
      // EXISTING PARTIAL KEY LOGIC
      // =========================================================================

      final partialKey = '${ruleSubjectCode}_' '${ruleType}_';

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
        // =====================================================================

        if (_isSyllabusRevisionTask(
          subjectTask,
          rule,
        )) {
          final createdCount = await _createSyllabusRevisionTask(
            subjectTask: subjectTask,
            rule: rule,
            milestoneDate: _parseMilestoneDate(milestone),
            subjectCode: subjectCode,
            chapterCodes: chapters,
          );

          subTaskCount += createdCount;

          continue;
        }

        // =====================================================================
        // NORMAL SUBJECT MILESTONE TASK
        // =====================================================================

        final createdCount = await _createTaskFromSubjectTask(
          subjectTask: subjectTask,
          rule: rule,
          milestoneDate: _parseMilestoneDate(milestone),
        );

        subTaskCount += createdCount;
      }
    }

    // =========================================================================
    // EXISTING MILESTONE CREATED FLAG BEHAVIOR
    // =========================================================================

    if (subTaskCount > 0) {
      await _markSubjectTasksCreated(
        subjectCode: subjectCode,
        milestone: milestone,
      );
    }

    return subTaskCount;
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

  Future<int> _createSyllabusRevisionTask({
    required Map<String, Object?> subjectTask,
    required Map<String, Object?> rule,
    required DateTime milestoneDate,
    required String subjectCode,
    required List<String> chapterCodes,
  }) async {
    final subjectTaskId = _string(subjectTask[_subjectTaskIdColumn]);

    if (subjectTaskId == null) {
      return 0;
    }

    final ruleId = _string(rule[_ruleIdColumn]) ?? '0';

    // =========================================================================
    // SAME TASK ID LOGIC AS OLD GENERATOR
    // =========================================================================

    final taskId = _buildTaskId(
      milestoneDate: milestoneDate,
      ruleId: ruleId,
      subjectTaskId: subjectTaskId,
    );

    final taskDescription =
        _string(subjectTask[_subjectTaskNameColumn]) ?? subjectTaskId;

    // =========================================================================
    // EXISTING ACTIVITIES
    //
    // Used for parent task duration exactly as before.
    // =========================================================================

    final activities = await _getActivitiesForSubjectTask(subjectTaskId);

    final duration = _taskDuration(subjectTask, activities);

    // =========================================================================
    // CREATE PARENT TASK
    // =========================================================================

    await _ensureParentTask(
      taskId: taskId,
      taskDescription: taskDescription,
      dueDate: milestoneDate,
      durationMinutes: duration,
    );

    // =========================================================================
    // RECONCILE FSR CHAPTER SCOPE
    // =========================================================================
    //
    // This is the new behavior.
    //
    // The milestone chapter list is the authoritative current scope.
    //
    // New chapter:
    //     INSERT PENDING
    //
    // Existing PENDING:
    //     NO ACTION
    //
    // Existing CANCELLED:
    //     RESTORE PENDING
    //
    // Removed chapter:
    //     CANCEL
    //
    // Nothing is deleted.
    // =========================================================================

    return _reconcileSyllabusRevisionSubTasks(
      taskId: taskId,
      subjectCode: subjectCode,
      chapterCodes: chapterCodes,
      durationMinutes: duration,
    );
  }

  // ===========================================================================
  // FSR SUBTASK RECONCILIATION
  // ===========================================================================

  Future<int> _reconcileSyllabusRevisionSubTasks({
    required String taskId,
    required String subjectCode,
    required List<String> chapterCodes,
    required int durationMinutes,
  }) async {
    final normalizedSubject = _normalizeSubjectCode(subjectCode);

    final currentScope = <String>{
      for (final code in chapterCodes)
        if (code.trim().isNotEmpty) code.trim(),
    };

    // =========================================================================
    // READ ALL EXISTING FSR SUBTASKS FOR THIS PARENT
    // =========================================================================

    final existingRows = await _db.query(
      _subTaskLogTable,
      where: 'SubTaskID = ? '
          'AND SubTaskSubjectCode = ?',
      whereArgs: [
        taskId,
        normalizedSubject,
      ],
    );

    var createdCount = 0;

    // =========================================================================
    // CURRENT SCOPE
    // =========================================================================
    //
    // For every chapter currently selected:
    //
    //   missing       -> INSERT
    //   PENDING       -> NO ACTION
    //   CANCELLED     -> RESTORE PENDING
    //
    // =========================================================================

    for (final chapterCode in currentScope) {
      Map<String, Object?>? existing;

      for (final row in existingRows) {
        final rowChapter = _string(row['SubTaskChapterCode']);

        if (rowChapter == chapterCode) {
          existing = row;
          break;
        }
      }

      // -----------------------------------------------------------------------
      // NEW CHAPTER
      // -----------------------------------------------------------------------

      if (existing == null) {
        final chapter = await _getChapterInfo(
          subjectCode: subjectCode,
          chapterCode: chapterCode,
        );

        final chapterName = _string(chapter?['chapter_name']);

        final subTaskDescription = 'Revise : $chapterCode - '
            '${chapterName ?? chapterCode}';

        final created = await _insertSubTaskIfMissing(
          subTaskId: taskId,
          subjectCode: subjectCode,
          chapterCode: chapterCode,
          description: subTaskDescription,
          durationMinutes: durationMinutes,
        );

        if (created) {
          createdCount++;
        }

        continue;
      }

      // -----------------------------------------------------------------------
      // EXISTING CANCELLED CHAPTER
      // -----------------------------------------------------------------------

      final status = _string(existing['SubTaskStatus'])?.toUpperCase();

      if (status == 'CANCELLED') {
        await _setSubTaskStatus(
          subTaskId: taskId,
          subjectCode: normalizedSubject,
          chapterCode: chapterCode,
          status: 'PENDING',
        );
      }

      // PENDING -> no action.
    }

    // =========================================================================
    // CHAPTERS NO LONGER IN CURRENT SCOPE
    // =========================================================================
    //
    // Existing PENDING chapter no longer selected:
    //     CANCELLED
    //
    // Existing CANCELLED chapter:
    //     NO ACTION
    //
    // =========================================================================

    for (final row in existingRows) {
      final chapterCode = _string(row['SubTaskChapterCode']);

      if (chapterCode == null) {
        continue;
      }

      if (currentScope.contains(chapterCode)) {
        continue;
      }

      final status = _string(row['SubTaskStatus'])?.toUpperCase();

      if (status == 'PENDING') {
        await _setSubTaskStatus(
          subTaskId: taskId,
          subjectCode: normalizedSubject,
          chapterCode: chapterCode,
          status: 'CANCELLED',
        );
      }
    }

    // =========================================================================
    // PARENT TASK STATUS
    // =========================================================================

    await _reconcileParentTaskStatus(
      taskId: taskId,
    );

    return createdCount;
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
      'CHEM' => const ['CHEM', 'CHEMISTRY', 'CHE'],
      'BIO' => const ['BIO', 'BIOLOGY'],
      _ => <String>[],
    };

    print('==========================================================');
    print('FSR CHAPTER LOOKUP');
    print('Subject received : $subjectCode');
    print('Normalized       : $normalizedSubject');
    print('Chapter received : $chapterCode');
    print('==========================================================');

    for (final candidate in subjectCandidates) {
      print(
        'Trying db_SyllabusMaster: '
        'subject_code=$candidate, chapter_code=$chapterCode',
      );

      final rows = await _db.query(
        _syllabusTable,
        columns: const [
          'subject_code',
          'chapter_code',
          'chapter_name',
        ],
        where: 'UPPER(subject_code) = ? '
            'AND chapter_code = ?',
        whereArgs: [
          candidate.toUpperCase(),
          chapterCode.trim(),
        ],
        limit: 1,
      );

      print('Rows returned: ${rows.length}');

      if (rows.isNotEmpty) {
        print('FOUND SYLLABUS ROW:');
        print(rows.first);
        print(
          'chapter_name = ${rows.first['chapter_name']}',
        );
        print('==========================================================');

        return rows.first;
      }
    }

    print('!!! CHAPTER NOT FOUND !!!');
    print(
      'Could not find subject=$subjectCode '
      'chapter=$chapterCode in db_SyllabusMaster',
    );
    print('==========================================================');

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
    // =========================================================================
    // EXACT SAME PCB SUBJECT TASK ID LOGIC
    // =========================================================================

    final pcbSubjectTaskId = 'PCB_${mtType}_TEST';

    final subjectTask = await _getSubjectTaskById(pcbSubjectTaskId);

    if (subjectTask == null) {
      return 0;
    }

    // =========================================================================
    // EXACT SAME ACTIVITY LOOKUP
    // =========================================================================

    final activities = await _getActivitiesForSubjectTask(
      pcbSubjectTaskId,
    );

    if (activities.isEmpty) {
      return 0;
    }

    final taskDescription =
        _string(subjectTask[_subjectTaskNameColumn]) ?? pcbSubjectTaskId;

    final duration = _taskDuration(
      subjectTask,
      activities,
    );

    // =========================================================================
    // EXACT SAME TASK ID LOGIC
    // =========================================================================

    final taskId = _buildTaskId(
      milestoneDate: milestoneDate,
      ruleId: 'PCB',
      subjectTaskId: pcbSubjectTaskId,
    );

    // =========================================================================
    // CREATE PARENT TASK
    // =========================================================================

    await _ensureParentTask(
      taskId: taskId,
      taskDescription: taskDescription,
      dueDate: milestoneDate,
      durationMinutes: duration,
    );

    // =========================================================================
    // RECONCILE PCB ACTIVITIES
    // =========================================================================
    //
    // The current SubjectTask -> Activity relationship is authoritative.
    //
    // Current activity + missing:
    //     INSERT PENDING
    //
    // Current activity + CANCELLED:
    //     RESTORE PENDING
    //
    // Current activity + PENDING:
    //     NO ACTION
    //
    // Existing activity no longer present:
    //     CANCELLED
    //
    // Nothing is deleted.
    // =========================================================================

    final createdCount = await _reconcilePcbSubTasks(
      taskId: taskId,
      activities: activities,
    );

    if (createdCount > 0) {
      await _markCommonTasksCreated(
        milestone: milestone,
      );
    }

    return createdCount;
  }

  // ===========================================================================
  // PCB SUBTASK RECONCILIATION
  // ===========================================================================

  Future<int> _reconcilePcbSubTasks({
    required String taskId,
    required List<Map<String, Object?>> activities,
  }) async {
    final existingRows = await _db.query(
      _subTaskLogTable,
      where: 'SubTaskID = ? '
          'AND SubTaskSubjectCode = ?',
      whereArgs: [
        taskId,
        'PCB',
      ],
    );

    final currentActivities = <String, Map<String, Object?>>{};

    for (final activity in activities) {
      final activityId = _string(activity['ActivityID']);

      if (activityId == null) {
        continue;
      }

      currentActivities[activityId] = activity;
    }

    var createdCount = 0;

    // =========================================================================
    // CURRENT PCB ACTIVITIES
    // =========================================================================

    for (final entry in currentActivities.entries) {
      final activityId = entry.key;
      final activity = entry.value;

      Map<String, Object?>? existing;

      for (final row in existingRows) {
        final rowChapter = _string(row['SubTaskChapterCode']);

        if (rowChapter == activityId) {
          existing = row;
          break;
        }
      }

      // -----------------------------------------------------------------------
      // NEW PCB ACTIVITY
      // -----------------------------------------------------------------------

      if (existing == null) {
        final activityDescription =
            _string(activity['ActivityDisplayName']) ?? activityId;

        final activityDuration = _int(activity['ActivityDurationMinutes']) ?? 0;

        final created = await _insertSubTaskIfMissing(
          subTaskId: taskId,
          subjectCode: 'PCB',
          chapterCode: activityId,
          description: activityDescription,
          durationMinutes: activityDuration,
        );

        if (created) {
          createdCount++;
        }

        continue;
      }

      // -----------------------------------------------------------------------
      // RESTORE CANCELLED PCB ACTIVITY
      // -----------------------------------------------------------------------

      final status = _string(existing['SubTaskStatus'])?.toUpperCase();

      if (status == 'CANCELLED') {
        await _setSubTaskStatus(
          subTaskId: taskId,
          subjectCode: 'PCB',
          chapterCode: activityId,
          status: 'PENDING',
        );
      }

      // PENDING -> no action.
    }

    // =========================================================================
    // PCB ACTIVITIES NO LONGER APPLICABLE
    // =========================================================================

    for (final row in existingRows) {
      final activityId = _string(row['SubTaskChapterCode']);

      if (activityId == null) {
        continue;
      }

      if (currentActivities.containsKey(activityId)) {
        continue;
      }

      final status = _string(row['SubTaskStatus'])?.toUpperCase();

      if (status == 'PENDING') {
        await _setSubTaskStatus(
          subTaskId: taskId,
          subjectCode: 'PCB',
          chapterCode: activityId,
          status: 'CANCELLED',
        );
      }
    }

    // =========================================================================
    // PARENT TASK STATUS
    // =========================================================================

    await _reconcileParentTaskStatus(
      taskId: taskId,
    );

    return createdCount;
  }

  // ===========================================================================
  // NORMAL SUBJECT TASK
  // ===========================================================================

  Future<int> _createTaskFromSubjectTask({
    required Map<String, Object?> subjectTask,
    required Map<String, Object?> rule,
    required DateTime milestoneDate,
  }) async {
    final subjectTaskId = _string(subjectTask[_subjectTaskIdColumn]);

    if (subjectTaskId == null) {
      return 0;
    }

    // =========================================================================
    // SAME TASK DESCRIPTION
    // =========================================================================

    final subjectTaskName =
        _string(subjectTask[_subjectTaskNameColumn]) ?? subjectTaskId;

    // =========================================================================
    // SAME RULE ID
    // =========================================================================

    final ruleId = _string(rule[_ruleIdColumn]) ?? '0';

    // =========================================================================
    // SAME ACTIVITY LOOKUP
    // =========================================================================

    final activities = await _getActivitiesForSubjectTask(subjectTaskId);

    if (activities.isEmpty) {
      return 0;
    }

    // =========================================================================
    // SAME TASK DURATION
    // =========================================================================

    final duration = _taskDuration(subjectTask, activities);

    // =========================================================================
    // SAME TASK ID
    // =========================================================================

    final taskId = _buildTaskId(
      milestoneDate: milestoneDate,
      ruleId: ruleId,
      subjectTaskId: subjectTaskId,
    );

    // =========================================================================
    // CREATE PARENT TASK
    // =========================================================================

    await _ensureParentTask(
      taskId: taskId,
      taskDescription: subjectTaskName,
      dueDate: milestoneDate,
      durationMinutes: duration,
    );

    // =========================================================================
    // CREATE SUBTASKS FROM EXISTING ACTIVITIES
    // =========================================================================

    var createdCount = 0;

    for (final activity in activities) {
      final activityId = _string(activity['ActivityID']);

      if (activityId == null) {
        continue;
      }

      final activityDescription =
          _string(activity['ActivityDisplayName']) ?? activityId;

      final activityDuration = _int(activity['ActivityDurationMinutes']) ?? 0;

      final created = await _insertSubTaskIfMissing(
        subTaskId: taskId,
        subjectCode: _subjectCodeFromSubjectTask(subjectTaskId),
        chapterCode: activityId,
        description: activityDescription,
        durationMinutes: activityDuration,
      );

      if (created) {
        createdCount++;
      }
    }

    return createdCount;
  }

  // ===========================================================================
  // PARENT TASK CREATION
  // ===========================================================================

  Future<void> _ensureParentTask({
    required String taskId,
    required String taskDescription,
    required DateTime dueDate,
    required int durationMinutes,
  }) async {
    // =========================================================================
    // SAME EXISTING TASK CHECK
    // =========================================================================

    final existingTask = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [taskId],
      limit: 1,
    );

    if (existingTask.isNotEmpty) {
      return;
    }

    // =========================================================================
    // SAME db_TaskLogWeekEnd INSERT
    // =========================================================================

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
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // ===========================================================================
  // INSERT SUBTASK
  // ===========================================================================

  Future<bool> _insertSubTaskIfMissing({
    required String subTaskId,
    required String subjectCode,
    required String chapterCode,
    required String description,
    required int durationMinutes,
  }) async {
    final normalizedSubject = _normalizeSubjectCode(subjectCode);

    final normalizedChapter = chapterCode.trim();

    if (normalizedSubject.isEmpty || normalizedChapter.isEmpty) {
      return false;
    }

    // =========================================================================
    // CHECK COMPOSITE PRIMARY KEY
    // =========================================================================

    final existing = await _db.query(
      _subTaskLogTable,
      columns: const [
        'SubTaskID',
        'SubTaskSubjectCode',
        'SubTaskChapterCode',
      ],
      where: 'SubTaskID = ? '
          'AND SubTaskSubjectCode = ? '
          'AND SubTaskChapterCode = ?',
      whereArgs: [
        subTaskId,
        normalizedSubject,
        normalizedChapter,
      ],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return false;
    }

    // =========================================================================
    // INSERT
    //
    // Database defaults remain authoritative.
    // =========================================================================

    await _db.insert(
      _subTaskLogTable,
      <String, Object?>{
        'SubTaskID': subTaskId,
        'SubTaskSubjectCode': normalizedSubject,
        'SubTaskChapterCode': normalizedChapter,
        'SubTaskDescription': description,
        'SubTaskDurationMinutes': durationMinutes,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    return true;
  }

  // ===========================================================================
  // UPDATE SUBTASK STATUS
  // ===========================================================================
  //
  // Used only for reconciliation.
  //
  // When a chapter/activity is cancelled or restored:
  //
  //     SubTaskStatus
  //     SubTaskStatusUpdateTime
  //
  // are updated.
  //
  // All other subtask fields remain untouched.
  // ===========================================================================

  Future<void> _setSubTaskStatus({
    required String subTaskId,
    required String subjectCode,
    required String chapterCode,
    required String status,
  }) async {
    final normalizedSubject = _normalizeSubjectCode(subjectCode);

    final normalizedChapter = chapterCode.trim();

    final timestamp = _formatDateTime(_now());

    await _db.update(
      _subTaskLogTable,
      <String, Object?>{
        'SubTaskStatus': status,
        'SubTaskStatusUpdateTime': timestamp,
      },
      where: 'SubTaskID = ? '
          'AND SubTaskSubjectCode = ? '
          'AND SubTaskChapterCode = ?',
      whereArgs: [
        subTaskId,
        normalizedSubject,
        normalizedChapter,
      ],
    );
  }

  // ===========================================================================
  // RECONCILE PARENT TASK STATUS
  // ===========================================================================
  //
  // Parent remains active while at least one subtask is active.
  //
  // If there are no PENDING subtasks:
  //
  //     parent -> CANCELLED
  //
  // If at least one PENDING subtask exists:
  //
  //     parent -> PENDING
  //
  // This is only called by FSR / PCB reconciliation.
  // ===========================================================================

  Future<void> _reconcileParentTaskStatus({
    required String taskId,
  }) async {
    final activeRows = await _db.query(
      _subTaskLogTable,
      columns: const ['SubTaskID'],
      where: 'SubTaskID = ? '
          'AND UPPER(SubTaskStatus) = ?',
      whereArgs: [
        taskId,
        'PENDING',
      ],
      limit: 1,
    );

    final newParentStatus = activeRows.isEmpty ? 'CANCELLED' : 'PENDING';

    await _db.update(
      _taskLogTable,
      <String, Object?>{
        'TaskStatus': newParentStatus,
      },
      where: 'TaskID = ?',
      whereArgs: [taskId],
    );
  }

  // ===========================================================================
  // SUBJECT CODE FROM SUBJECT TASK ID
  // ===========================================================================

  String _subjectCodeFromSubjectTask(
    String subjectTaskId,
  ) {
    final normalized = subjectTaskId.trim().toUpperCase();

    if (normalized.startsWith('PHY_')) {
      return 'PHY';
    }

    if (normalized.startsWith('CHEM_') || normalized.startsWith('CHE_')) {
      return 'CHEM';
    }

    if (normalized.startsWith('BIO_')) {
      return 'BIO';
    }

    if (normalized.startsWith('PCB_')) {
      return 'PCB';
    }

    final underscoreIndex = normalized.indexOf('_');

    if (underscoreIndex > 0) {
      return _normalizeSubjectCode(
        normalized.substring(0, underscoreIndex),
      );
    }

    return _normalizeSubjectCode(normalized);
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
      whereArgs: [
        1,
        normalizedType,
      ],
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
      whereArgs: [
        '$partialKey%',
        'Yes',
      ],
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
      whereArgs: [
        subjectTaskId,
        'Yes',
      ],
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
        whereArgs: [
          activityId,
          'Yes',
        ],
        limit: 1,
      );

      if (activityRows.isEmpty) {
        continue;
      }

      result.add(
        <String, Object?>{
          ...link,
          ...activityRows.first,
        },
      );
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
      whereArgs: [
        mtType.trim().toUpperCase(),
        _formatDate(date),
      ],
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

    return _splitCodes(
      milestone[column]?.toString(),
    );
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

  String _normalizeSubjectCode(
    String value,
  ) {
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

  DateTime _parseMilestoneDate(
    Map<String, Object?> milestone,
  ) {
    final value = _string(milestone[_milestoneDateColumn]);

    if (value == null) {
      throw StateError(
        'Milestone date is missing.',
      );
    }

    return DateTime.parse(value);
  }

  static DateTime _dateOnly(
    DateTime date,
  ) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  static String _formatDate(
    DateTime date,
  ) {
    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  static String _formatDateTime(
    DateTime date,
  ) {
    final year = date.year.toString().padLeft(4, '0');

    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    final hour = date.hour.toString().padLeft(2, '0');

    final minute = date.minute.toString().padLeft(2, '0');

    final second = date.second.toString().padLeft(2, '0');

    return '$year-$month-$day '
        '$hour:$minute:$second';
  }

  static String _compactDate(
    DateTime date,
  ) {
    return '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ===========================================================================
  // GENERIC HELPERS
  // ===========================================================================

  static List<String> _splitCodes(
    String? value,
  ) {
    if (value == null || value.trim().isEmpty) {
      return const [];
    }

    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String? _string(
    Object? value,
  ) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }

  static int? _int(
    Object? value,
  ) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
      value?.toString() ?? '',
    );
  }
}
