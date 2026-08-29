import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// MT Task Generator
///
/// Dynamic Milestone Task Generator.
///
/// The caller supplies:
///
///     mtType
///     milestoneDate
///
/// Example:
///
///     generateMilestoneTasks(
///       mtType: 'CMT',
///       milestoneDate: someSunday,
///     );
///
/// or:
///
///     generateMilestoneTasks(
///       mtType: 'PMT',
///       milestoneDate: someSunday,
///     );
///
/// Generation hierarchy:
///
///   db_Milestones
///        │
///        ├── PHY
///        │     └── MT Rule
///        │            └── MT_Subject_Code + MT_Type
///        │                   └── partial SubjectTaskID lookup
///        │                          └── db_SubjectTasks
///        │                                 └── SubjectTaskActivities
///        │                                        └── db_Activities
///        │
///        ├── CHEM
///        │     └── same flow
///        │
///        ├── BIO
///        │     └── same flow
///        │
///        └── PCB
///              └── PCB_<MT_TYPE>_TEST
///                     └── SubjectTaskActivities
///                            └── db_Activities
///
/// Subject task lookup:
///
///   MT_Subject_Code + MT_Type
///              ↓
///       partial SubjectTaskID
///              ↓
///       LIKE 'PHY_CMT_%'
///       LIKE 'PHY_PMT_%'
///       LIKE 'CHEM_CMT_%'
///       LIKE 'CHEM_PMT_%'
///       LIKE 'BIO_CMT_%'
///       LIKE 'BIO_PMT_%'
///
/// Created task data:
///   db_TaskLogWeekEnd
///   db_TaskActivityStatus
///
/// Return value:
///
///   {
///     'PHY':  <number of PHY tasks created/present>,
///     'CHEM': <number of CHEM tasks created/present>,
///     'BIO':  <number of BIO tasks created/present>,
///     'PCB':  <number of PCB tasks created/present>,
///   }
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

  static const String _subjectTaskActivityTable =
      'db_SubjectTaskActivities';

  static const String _activityTable = 'db_Activities';

  static const String _taskLogTable = 'db_TaskLogWeekEnd';

  static const String _taskActivityStatusTable =
      'db_TaskActivityStatus';

  // ===========================================================================
  // MILESTONE COLUMNS
  // ===========================================================================

  static const String _milestoneDateColumn =
      'milestone_date';

  static const String _milestoneTypeColumn =
      'milestone_type';

  static const String _phyColumn =
      'milestone_phy_chapters';

  static const String _chemColumn =
      'milestone_chem_chapters';

  static const String _bioColumn =
      'milestone_bio_chapters';

  // Task-created flags.

  static const String _phyTaskCreatedColumn =
      'milestone_phy_task_created';

  static const String _chemTaskCreatedColumn =
      'milestone_chem_task_created';

  static const String _bioTaskCreatedColumn =
      'milestone_bio_task_created';

  static const String _commonTasksCreatedColumn =
      'milestone_common_tasks_created';

  // ===========================================================================
  // TASK CREATION RULE COLUMNS
  // ===========================================================================

  static const String _ruleIdColumn =
      'MT_Rule_ID';

  static const String _ruleActiveColumn =
      'MT_Rule_IsActive';

  static const String _ruleTypeColumn =
      'MT_Type';

  static const String _ruleSubjectColumn =
      'MT_Subject_Code';

  static const String _ruleDescriptionColumn =
      'MT_Rule_Description';

  // ===========================================================================
  // SUBJECT TASK COLUMNS
  // ===========================================================================

  static const String _subjectTaskIdColumn =
      'SubjectTaskID';

  static const String _subjectTaskNameColumn =
      'SubjectTaskName';

  static const String _subjectTaskActiveColumn =
      'SubjectTaskIsActive';

  static const String _subjectTaskDurationColumn =
      'SubjectTaskDurationMinutes';

  // ===========================================================================
  // PUBLIC METHOD
  // ===========================================================================

  /// Generates all milestone tasks for [milestoneDate] and [mtType].
  ///
  /// [mtType] is supplied by the Milestone UI.
  ///
  /// Example:
  ///
  ///     mtType = CMT
  ///
  /// or:
  ///
  ///     mtType = PMT
  ///
  /// The supplied type is used dynamically for:
  ///
  ///   1. Milestone lookup
  ///   2. Rule lookup
  ///   3. SubjectTask matching
  ///
  /// PHY/CHEM/BIO:
  ///
  ///   - Requires milestone chapter scope.
  ///   - Finds active rule for the requested subject + MT type.
  ///   - Builds partial SubjectTaskID:
  ///
  ///         MT_Subject_Code + MT_Type
  ///
  ///   - Finds all matching active SubjectTasks.
  ///   - Creates/checks a task for each matching SubjectTask.
  ///
  /// PCB:
  ///
  ///   - Is milestone-level.
  ///   - Does not require chapter scope.
  ///   - Uses PCB_<MT_TYPE>_TEST.
  Future<Map<String, int>> generateMilestoneTasks({
    required String mtType,
    DateTime? milestoneDate,
  }) async {
    final date = _dateOnly(
      milestoneDate ?? _now(),
    );

    final normalizedType =
    mtType.trim().toUpperCase();

    debugPrint('');
    debugPrint('================================================');
    debugPrint('        MT TASK GENERATION START');
    debugPrint('================================================');
    debugPrint(
      'Requested MT Type : $normalizedType',
    );
    debugPrint(
      'Milestone Date    : ${_formatDate(date)}',
    );

    // -----------------------------------------------------------------------
    // VALIDATE MT TYPE
    // -----------------------------------------------------------------------

    if (normalizedType.isEmpty) {
      debugPrint(
        'ERROR: MT Type is empty.',
      );

      throw ArgumentError(
        'MT Type cannot be empty.',
      );
    }

    // -----------------------------------------------------------------------
    // VALIDATE DATE
    // -----------------------------------------------------------------------

    if (date.weekday != DateTime.sunday) {
      debugPrint(
        'ERROR: Milestone date is not Sunday.',
      );

      debugPrint(
        'Received date: ${_formatDate(date)}',
      );

      throw ArgumentError(
        'Milestone task generation requires a Sunday milestone date.',
      );
    }

    debugPrint(
      'Validation passed.',
    );

    // -----------------------------------------------------------------------
    // MILESTONE LOOKUP
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint('>>> MILESTONE LOOKUP');

    debugPrint(
      'Looking for milestone:',
    );

    debugPrint(
      '  Type : $normalizedType',
    );

    debugPrint(
      '  Date : ${_formatDate(date)}',
    );

    final milestone = await _getMilestone(
      date,
      normalizedType,
    );

    if (milestone == null) {
      debugPrint('');
      debugPrint(
        'DECISION: Matching milestone NOT FOUND.',
      );

      debugPrint(
        'No $normalizedType milestone exists for '
            '${_formatDate(date)}.',
      );

      debugPrint(
        'Generation stopped.',
      );

      debugPrint('================================================');
      debugPrint('        MT TASK GENERATION END');
      debugPrint('================================================');

      return const {
        'PHY': 0,
        'CHEM': 0,
        'BIO': 0,
        'PCB': 0,
      };
    }

    debugPrint('');
    debugPrint(
      'DECISION: Matching milestone FOUND.',
    );

    debugPrint(
      'Milestone Type : '
          '${milestone[_milestoneTypeColumn]}',
    );

    debugPrint(
      'Milestone Date : '
          '${milestone[_milestoneDateColumn]}',
    );

    debugPrint(
      'PHY Chapters   : '
          '${milestone[_phyColumn]}',
    );

    debugPrint(
      'CHEM Chapters  : '
          '${milestone[_chemColumn]}',
    );

    debugPrint(
      'BIO Chapters   : '
          '${milestone[_bioColumn]}',
    );

    // -----------------------------------------------------------------------
    // RESULT HOLDER
    // -----------------------------------------------------------------------

    final results = <String, int>{
      'PHY': 0,
      'CHEM': 0,
      'BIO': 0,
      'PCB': 0,
    };

    // -----------------------------------------------------------------------
    // PHY
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint('>>> STARTING PHY PROCESSING');

    results['PHY'] = await _processSubject(
      milestone: milestone,
      subjectCode: 'PHY',
      mtType: normalizedType,
    );

    debugPrint(
      '<<< PHY PROCESSING COMPLETE: '
          '${results['PHY']} task(s)',
    );

    // -----------------------------------------------------------------------
    // CHEM
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint('>>> STARTING CHEM PROCESSING');

    results['CHEM'] = await _processSubject(
      milestone: milestone,
      subjectCode: 'CHEM',
      mtType: normalizedType,
    );

    debugPrint(
      '<<< CHEM PROCESSING COMPLETE: '
          '${results['CHEM']} task(s)',
    );

    // -----------------------------------------------------------------------
    // BIO
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint('>>> STARTING BIO PROCESSING');

    results['BIO'] = await _processSubject(
      milestone: milestone,
      subjectCode: 'BIO',
      mtType: normalizedType,
    );

    debugPrint(
      '<<< BIO PROCESSING COMPLETE: '
          '${results['BIO']} task(s)',
    );

    // -----------------------------------------------------------------------
    // PCB / COMMON
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint('>>> STARTING PCB / COMMON PROCESSING');

    results['PCB'] = await _processCommonTasks(
      milestone: milestone,
      milestoneDate: date,
      mtType: normalizedType,
    );

    debugPrint(
      '<<< PCB / COMMON PROCESSING COMPLETE: '
          '${results['PCB']} task(s)',
    );

    // -----------------------------------------------------------------------
    // FINAL OUTPUT
    // -----------------------------------------------------------------------

    final total =
    results.values.fold<int>(
      0,
          (sum, value) => sum + value,
    );

    debugPrint('');
    debugPrint('================================================');
    debugPrint('        MT TASK GENERATION END');
    debugPrint('================================================');

    debugPrint(
      'MT Type : $normalizedType',
    );

    debugPrint(
      'Date    : ${_formatDate(date)}',
    );

    debugPrint(
      'PHY     : ${results['PHY']}',
    );

    debugPrint(
      'CHEM    : ${results['CHEM']}',
    );

    debugPrint(
      'BIO     : ${results['BIO']}',
    );

    debugPrint(
      'PCB     : ${results['PCB']}',
    );

    debugPrint(
      'TOTAL   : $total',
    );

    debugPrint('================================================');

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
    debugPrint('');
    debugPrint('------------------------------------------------');
    debugPrint('PROCESS SUBJECT');
    debugPrint('------------------------------------------------');

    debugPrint(
      'Subject : $subjectCode',
    );

    debugPrint(
      'MT Type : $mtType',
    );

    // -----------------------------------------------------------------------
    // 1. READ MILESTONE CHAPTER SCOPE
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      '[$subjectCode] Reading milestone chapter scope...',
    );

    final chapters = _milestoneScope(
      milestone,
      subjectCode,
    );

    debugPrint(
      '[$subjectCode] Chapter scope received: $chapters',
    );

    debugPrint(
      '[$subjectCode] Chapter count: ${chapters.length}',
    );

    if (chapters.isEmpty) {
      debugPrint(
        'DECISION: $subjectCode has NO chapter scope.',
      );

      debugPrint(
        'RESULT: $subjectCode = 0',
      );

      return 0;
    }

    debugPrint(
      'DECISION: $subjectCode has '
          '${chapters.length} chapter(s) to process.',
    );

    // -----------------------------------------------------------------------
    // 2. FIND ACTIVE RULES
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      '[$subjectCode] Looking for active '
          '$mtType rules...',
    );

    final rules = await _getRulesForSubject(
      subjectCode,
      mtType,
    );

    debugPrint(
      '[$subjectCode] Matching active rules: '
          '${rules.length}',
    );

    if (rules.isEmpty) {
      debugPrint(
        'DECISION: No active rules found for '
            '$subjectCode / $mtType.',
      );

      debugPrint(
        'RESULT: $subjectCode = 0',
      );

      return 0;
    }

    var taskCount = 0;

    // -----------------------------------------------------------------------
    // 3. PROCESS EACH RULE
    // -----------------------------------------------------------------------

    for (var ruleIndex = 0;
    ruleIndex < rules.length;
    ruleIndex++) {
      final rule = rules[ruleIndex];

      final ruleId = _string(
        rule[_ruleIdColumn],
      );

      final ruleDescription = _string(
        rule[_ruleDescriptionColumn],
      );

      final ruleSubjectCode = _string(
        rule[_ruleSubjectColumn],
      );

      final ruleType = _string(
        rule[_ruleTypeColumn],
      );

      debugPrint('');
      debugPrint('***********************************************');
      debugPrint(
        'PROCESSING RULE '
            '${ruleIndex + 1}/${rules.length}',
      );
      debugPrint('***********************************************');

      debugPrint(
        'Rule ID          : '
            '${ruleId ?? '(missing)'}',
      );

      debugPrint(
        'Rule Description : '
            '${ruleDescription ?? '(none)'}',
      );

      debugPrint(
        'MT_Subject_Code  : '
            '${ruleSubjectCode ?? '(missing)'}',
      );

      debugPrint(
        'MT_Type          : '
            '${ruleType ?? '(missing)'}',
      );

      // ---------------------------------------------------------------------
      // VALIDATE RULE
      // ---------------------------------------------------------------------

      if (ruleSubjectCode == null ||
          ruleType == null) {
        debugPrint(
          'DECISION: Rule SKIPPED.',
        );

        debugPrint(
          'Reason: MT_Subject_Code or MT_Type is missing.',
        );

        continue;
      }

      // ---------------------------------------------------------------------
      // BUILD PARTIAL SUBJECT TASK KEY
      // ---------------------------------------------------------------------

      final partialKey =
          '${ruleSubjectCode}_'
          '${ruleType}_';

      debugPrint('');
      debugPrint(
        'SUBJECT TASK MATCHING KEY',
      );

      debugPrint(
        'MT_Subject_Code : $ruleSubjectCode',
      );

      debugPrint(
        'MT_Type         : $ruleType',
      );

      debugPrint(
        'Generated Key   : $partialKey',
      );

      debugPrint(
        'LIKE Pattern    : ${partialKey}%',
      );

      // ---------------------------------------------------------------------
      // LOOKUP SUBJECT TASKS
      // ---------------------------------------------------------------------

      final subjectTasks =
      await _getSubjectTasksByPartialKey(
        partialKey,
      );

      debugPrint(
        'Matching SubjectTasks: '
            '${subjectTasks.length}',
      );

      if (subjectTasks.isEmpty) {
        debugPrint(
          'DECISION: No SubjectTask matched '
              '${partialKey}%',
        );

        continue;
      }

      // ---------------------------------------------------------------------
      // PROCESS EACH SUBJECT TASK
      // ---------------------------------------------------------------------

      for (var taskIndex = 0;
      taskIndex < subjectTasks.length;
      taskIndex++) {
        final subjectTask =
        subjectTasks[taskIndex];

        final subjectTaskId = _string(
          subjectTask[_subjectTaskIdColumn],
        );

        debugPrint('');
        debugPrint('==============================================');
        debugPrint(
          'PROCESSING SUBJECT TASK '
              '${taskIndex + 1}/${subjectTasks.length}',
        );
        debugPrint('==============================================');

        debugPrint(
          'SubjectTaskID   : '
              '${subjectTaskId ?? '(missing)'}',
        );

        debugPrint(
          'SubjectTaskName : '
              '${subjectTask[_subjectTaskNameColumn] ?? '(none)'}',
        );

        debugPrint(
          'Active          : '
              '${subjectTask[_subjectTaskActiveColumn] ?? '(none)'}',
        );

        debugPrint(
          'Configured Time : '
              '${subjectTask[_subjectTaskDurationColumn] ?? '(none)'}',
        );

        if (subjectTaskId == null) {
          debugPrint(
            'DECISION: SubjectTask SKIPPED.',
          );

          debugPrint(
            'Reason: SubjectTaskID is missing.',
          );

          continue;
        }

        final created =
        await _createTaskFromSubjectTask(
          subjectTask: subjectTask,
          rule: rule,
          milestone: milestone,
          milestoneDate:
          _parseMilestoneDate(milestone),
          chapterCodes: chapters,
        );

        if (created) {
          taskCount++;

          debugPrint(
            'DECISION: SubjectTask produced '
                'a task successfully.',
          );

          debugPrint(
            'Running $subjectCode count: $taskCount',
          );
        } else {
          debugPrint(
            'DECISION: SubjectTask did NOT '
                'produce a task.',
          );
        }
      }
    }

    // -----------------------------------------------------------------------
    // 4. MARK SUBJECT TASKS CREATED
    // -----------------------------------------------------------------------

    if (taskCount > 0) {
      debugPrint('');
      debugPrint(
        '[$subjectCode] Tasks created/present: '
            '$taskCount',
      );

      debugPrint(
        'Updating milestone task-created flag...',
      );

      await _markSubjectTasksCreated(
        subjectCode: subjectCode,
        milestone: milestone,
      );

      debugPrint(
        'Milestone task-created flag updated.',
      );
    } else {
      debugPrint('');
      debugPrint(
        '[$subjectCode] No tasks created/present.',
      );
    }

    debugPrint('');
    debugPrint(
      'PROCESS SUBJECT END',
    );

    debugPrint(
      '$subjectCode RESULT = $taskCount',
    );

    debugPrint('------------------------------------------------');

    return taskCount;
  }

  // ===========================================================================
  // COMMON / PCB PROCESSING
  // ===========================================================================

  Future<int> _processCommonTasks({
    required Map<String, Object?> milestone,
    required DateTime milestoneDate,
    required String mtType,
  }) async {
    debugPrint('');
    debugPrint('------------------------------------------------');
    debugPrint('PROCESSING COMMON / PCB TASK');
    debugPrint('------------------------------------------------');

    debugPrint(
      'MT Type: $mtType',
    );

    debugPrint(
      'PCB is milestone-level and does not require '
          'chapter scope.',
    );

    // -----------------------------------------------------------------------
    // PCB SUBJECT TASK ID
    // -----------------------------------------------------------------------

    final pcbSubjectTaskId =
        'PCB_${mtType}_TEST';

    debugPrint('');
    debugPrint(
      'PCB SubjectTaskID generated dynamically:',
    );

    debugPrint(
      '  $pcbSubjectTaskId',
    );

    debugPrint(
      'Looking up active PCB SubjectTask...',
    );

    final subjectTask =
    await _getSubjectTaskById(
      pcbSubjectTaskId,
    );

    if (subjectTask == null) {
      debugPrint(
        'DECISION: PCB SubjectTask NOT FOUND '
            'or inactive.',
      );

      debugPrint(
        'Expected SubjectTaskID: '
            '$pcbSubjectTaskId',
      );

      return 0;
    }

    debugPrint(
      'DECISION: PCB SubjectTask FOUND.',
    );

    debugPrint('');
    debugPrint('PCB SUBJECT TASK DETAILS');

    debugPrint(
      'SubjectTaskID   : '
          '${subjectTask[_subjectTaskIdColumn]}',
    );

    debugPrint(
      'SubjectTaskName : '
          '${subjectTask[_subjectTaskNameColumn]}',
    );

    debugPrint(
      'Configured Time : '
          '${subjectTask[_subjectTaskDurationColumn]}',
    );

    // -----------------------------------------------------------------------
    // ACTIVITIES
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'Loading PCB SubjectTask activities...',
    );

    final activities =
    await _getActivitiesForSubjectTask(
      pcbSubjectTaskId,
    );

    debugPrint(
      'PCB active activities: '
          '${activities.length}',
    );

    if (activities.isEmpty) {
      debugPrint(
        'DECISION: PCB has no active activities.',
      );

      return 0;
    }

    // -----------------------------------------------------------------------
    // DESCRIPTION
    // -----------------------------------------------------------------------

    final taskDescription =
        _string(
          subjectTask[_subjectTaskNameColumn],
        ) ??
            pcbSubjectTaskId;

    debugPrint('');
    debugPrint(
      'PCB Task Description:',
    );

    debugPrint(
      taskDescription,
    );

    // -----------------------------------------------------------------------
    // DURATION
    // -----------------------------------------------------------------------

    final duration = _taskDuration(
      subjectTask,
      activities,
    );

    debugPrint(
      'PCB calculated duration: '
          '$duration minutes',
    );

    // -----------------------------------------------------------------------
    // TASK ID
    // -----------------------------------------------------------------------

    final taskId = _buildTaskId(
      milestoneDate: milestoneDate,
      ruleId: 'PCB',
      subjectTaskId: pcbSubjectTaskId,
    );

    debugPrint('');
    debugPrint(
      'PCB FINAL TASK ID:',
    );

    debugPrint(
      taskId,
    );

    // -----------------------------------------------------------------------
    // CREATE
    // -----------------------------------------------------------------------

    final result =
    await _createTaskAndActivityStatus(
      taskId: taskId,
      taskDescription: taskDescription,
      dueDate: milestoneDate,
      durationMinutes: duration,
      activities: activities,
    );

    if (result) {
      debugPrint(
        'PCB task created/present successfully.',
      );

      await _markCommonTasksCreated(
        milestone: milestone,
      );

      debugPrint(
        'PCB/common milestone task-created '
            'flag updated.',
      );

      debugPrint(
        'PCB RESULT = 1',
      );

      return 1;
    }

    debugPrint(
      'PCB RESULT = 0',
    );

    return 0;
  }

  // ===========================================================================
  // SUBJECT TASK CREATION
  // ===========================================================================

  Future<bool> _createTaskFromSubjectTask({
    required Map<String, Object?> subjectTask,
    required Map<String, Object?> rule,
    required Map<String, Object?> milestone,
    required DateTime milestoneDate,
    required List<String> chapterCodes,
  }) async {
    final subjectTaskId =
    _string(
      subjectTask[_subjectTaskIdColumn],
    );

    if (subjectTaskId == null) {
      debugPrint(
        'DECISION: SubjectTask skipped because '
            'SubjectTaskID is missing.',
      );

      return false;
    }

    final subjectTaskName =
        _string(
          subjectTask[_subjectTaskNameColumn],
        ) ??
            subjectTaskId;

    final ruleId =
        _string(
          rule[_ruleIdColumn],
        ) ??
            '0';

    final ruleSubjectCode =
    _string(
      rule[_ruleSubjectColumn],
    );

    final ruleType =
    _string(
      rule[_ruleTypeColumn],
    );

    debugPrint('');
    debugPrint('==============================================');
    debugPrint('SUBJECT TASK → TASK CREATION');
    debugPrint('==============================================');

    debugPrint(
      'SubjectTaskID   : $subjectTaskId',
    );

    debugPrint(
      'SubjectTaskName : $subjectTaskName',
    );

    debugPrint(
      'RuleID          : $ruleId',
    );

    debugPrint(
      'MT_Subject_Code : '
          '${ruleSubjectCode ?? '(none)'}',
    );

    debugPrint(
      'MT_Type         : '
          '${ruleType ?? '(none)'}',
    );

    debugPrint(
      'Milestone Date  : '
          '${_formatDate(milestoneDate)}',
    );

    // -----------------------------------------------------------------------
    // ACTIVITIES
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'Loading activities for SubjectTask...',
    );

    final activities =
    await _getActivitiesForSubjectTask(
      subjectTaskId,
    );

    debugPrint(
      'Active activities found: '
          '${activities.length}',
    );

    if (activities.isEmpty) {
      debugPrint(
        'DECISION: Task SKIPPED.',
      );

      debugPrint(
        'Reason: SubjectTask has no active activities.',
      );

      return false;
    }

    // -----------------------------------------------------------------------
    // ACTIVITY DETAILS
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'FINAL ACTIVE ACTIVITIES FOR TASK',
    );

    for (var i = 0;
    i < activities.length;
    i++) {
      final activity = activities[i];

      final activityId =
      _string(
        activity['ActivityID'],
      );

      final activityDescription =
      _activityDescription(activity);

      final activityDuration =
      _int(
        activity['ActivityDurationMinutes'],
      );

      debugPrint(
        '  ${i + 1}.',
      );

      debugPrint(
        '     ActivityID          : '
            '${activityId ?? '(missing)'}',
      );

      debugPrint(
        '     Sequence            : '
            '${activity['ActivitySequence'] ?? '(none)'}',
      );

      debugPrint(
        '     ActivityName        : '
            '${activity['ActivityName'] ?? '(none)'}',
      );

      debugPrint(
        '     ActivityDescription : '
            '$activityDescription',
      );

      debugPrint(
        '     Duration            : '
            '${activityDuration ?? 0} minutes',
      );
    }

    // -----------------------------------------------------------------------
    // DESCRIPTION
    // -----------------------------------------------------------------------

    final taskDescription =
        subjectTaskName;

    debugPrint('');
    debugPrint(
      'FINAL TASK DESCRIPTION',
    );

    debugPrint(
      taskDescription,
    );

    // -----------------------------------------------------------------------
    // SCOPE
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'TASK CHAPTER SCOPE',
    );

    debugPrint(
      'Chapter count: ${chapterCodes.length}',
    );

    debugPrint(
      'Chapters: ${chapterCodes.join(', ')}',
    );

    // -----------------------------------------------------------------------
    // DURATION
    // -----------------------------------------------------------------------

    final duration =
    _taskDuration(
      subjectTask,
      activities,
    );

    debugPrint('');
    debugPrint(
      'TASK DURATION',
    );

    debugPrint(
      'Configured SubjectTask duration: '
          '${subjectTask[_subjectTaskDurationColumn]}',
    );

    debugPrint(
      'Final duration used: '
          '$duration minutes',
    );

    // -----------------------------------------------------------------------
    // TASK ID
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'BUILDING TASK ID',
    );

    final taskId = _buildTaskId(
      milestoneDate: milestoneDate,
      ruleId: ruleId,
      subjectTaskId: subjectTaskId,
    );

    debugPrint(
      'FINAL GENERATED TASK ID:',
    );

    debugPrint(
      taskId,
    );

    // -----------------------------------------------------------------------
    // CREATE
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      '>>> CALLING TASK + ACTIVITY STATUS CREATION',
    );

    final result =
    await _createTaskAndActivityStatus(
      taskId: taskId,
      taskDescription: taskDescription,
      dueDate: milestoneDate,
      durationMinutes: duration,
      activities: activities,
    );

    if (result) {
      debugPrint(
        '<<< TASK CREATION RESULT: SUCCESS',
      );

      debugPrint(
        'TaskID: $taskId',
      );
    } else {
      debugPrint(
        '<<< TASK CREATION RESULT: FAILURE',
      );

      debugPrint(
        'TaskID: $taskId',
      );
    }

    return result;
  }

  // ===========================================================================
  // TASK + ACTIVITY STATUS INSERT
  // ===========================================================================

  Future<bool> _createTaskAndActivityStatus({
    required String taskId,
    required String taskDescription,
    required DateTime dueDate,
    required int durationMinutes,
    required List<Map<String, Object?>> activities,
  }) async {
    debugPrint('');
    debugPrint('================================================');
    debugPrint('CREATE TASK + ACTIVITY STATUS');
    debugPrint('================================================');

    debugPrint(
      'TaskID      : $taskId',
    );

    debugPrint(
      'Description : $taskDescription',
    );

    debugPrint(
      'Due Date    : ${_formatDate(dueDate)}',
    );

    debugPrint(
      'Duration    : $durationMinutes minutes',
    );

    debugPrint(
      'Activities  : ${activities.length}',
    );

    // -----------------------------------------------------------------------
    // TASK EXISTENCE CHECK
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'TASK EXISTENCE CHECK',
    );

    debugPrint(
      'Searching db_TaskLogWeekEnd for:',
    );

    debugPrint(
      'TaskID = $taskId',
    );

    final existingTask =
    await _db.query(
      _taskLogTable,
      columns: const [
        'TaskID',
      ],
      where: 'TaskID = ?',
      whereArgs: [
        taskId,
      ],
      limit: 1,
    );

    final alreadyExists =
        existingTask.isNotEmpty;

    if (alreadyExists) {
      debugPrint(
        'DECISION: Task ALREADY EXISTS.',
      );

      debugPrint(
        'No duplicate TaskLog row will be inserted.',
      );
    } else {
      debugPrint(
        'DECISION: Task DOES NOT EXIST.',
      );

      debugPrint(
        'Proceeding with TaskLog insertion.',
      );

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
        conflictAlgorithm:
        ConflictAlgorithm.ignore,
      );

      debugPrint(
        'TaskLog INSERT completed:',
      );

      debugPrint(
        taskId,
      );
    }

    // -----------------------------------------------------------------------
    // ACTIVITY STATUS JSON
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'ACTIVITY STATUS GENERATION',
    );

    debugPrint(
      'TaskID: $taskId',
    );

    final activityStatus =
    <String, bool>{};

    for (final activity in activities) {
      final activityId =
      _string(
        activity['ActivityID'],
      );

      if (activityId == null) {
        debugPrint(
          'Activity skipped from status JSON '
              'because ActivityID is missing.',
        );

        continue;
      }

      final description =
      _activityDescription(activity);

      activityStatus[activityId] =
      false;

      debugPrint(
        '  $activityId'
            ' -> false'
            ' | $description',
      );
    }

    final activityStatusJson =
    jsonEncode(activityStatus);

    debugPrint('');
    debugPrint(
      'FINAL ActivityStatusJSON:',
    );

    debugPrint(
      activityStatusJson,
    );

    // -----------------------------------------------------------------------
    // ACTIVITY STATUS TABLE
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'ACTIVITY STATUS TABLE CHECK',
    );

    debugPrint(
      'Searching db_TaskActivityStatus '
          'for TaskID: $taskId',
    );

    final existingStatus =
    await _db.query(
      _taskActivityStatusTable,
      columns: const [
        'TaskID',
      ],
      where: 'TaskID = ?',
      whereArgs: [
        taskId,
      ],
      limit: 1,
    );

    if (existingStatus.isEmpty) {
      debugPrint(
        'DECISION: Activity status does NOT exist.',
      );

      debugPrint(
        'Proceeding with ActivityStatus INSERT.',
      );

      await _db.insert(
        _taskActivityStatusTable,
        <String, Object?>{
          'TaskID': taskId,
          'ActivityStatusJSON':
          activityStatusJson,
          'TaskActivityUpdatedDate':
          _now().toIso8601String(),
        },
        conflictAlgorithm:
        ConflictAlgorithm.ignore,
      );

      debugPrint(
        'Activity status INSERT completed:',
      );

      debugPrint(
        taskId,
      );
    } else {
      debugPrint(
        'DECISION: Activity status ALREADY EXISTS.',
      );

      debugPrint(
        'No duplicate ActivityStatus row '
            'will be inserted.',
      );
    }

    debugPrint('');
    debugPrint(
      'CREATE TASK + ACTIVITY STATUS COMPLETE',
    );

    debugPrint(
      'TaskID: $taskId',
    );

    debugPrint('================================================');

    return true;
  }

  // ===========================================================================
  // RULE LOOKUP
  // ===========================================================================

  /// Returns active rules for a specific subject and requested MT type.
  ///
  /// The rule provides:
  ///
  ///   MT_Subject_Code
  ///   MT_Type
  ///
  /// These are combined later to form the partial SubjectTaskID.
  ///
  /// Example:
  ///
  ///   MT_Subject_Code = PHY
  ///   MT_Type         = PMT
  ///
  /// produces:
  ///
  ///   PHY_PMT_
  Future<List<Map<String, Object?>>> _getRulesForSubject(
      String subjectCode,
      String mtType,
      ) async {
    final normalizedSubject =
    _normalizeSubjectCode(
      subjectCode,
    );

    final normalizedType =
    mtType.trim().toUpperCase();

    debugPrint('');
    debugPrint('------------------------------------------------');
    debugPrint('RULE LOOKUP');
    debugPrint('------------------------------------------------');

    debugPrint(
      'Requested Subject : $normalizedSubject',
    );

    debugPrint(
      'Requested MT Type : $normalizedType',
    );

    debugPrint(
      'Searching active rules...',
    );

    final rows =
    await _db.query(
      _ruleTable,
      where:
      '$_ruleActiveColumn = ? '
          'AND $_ruleTypeColumn = ?',
      whereArgs: [
        1,
        normalizedType,
      ],
      orderBy:
      '$_ruleIdColumn ASC',
    );

    debugPrint(
      'Active $normalizedType rule rows returned: '
          '${rows.length}',
    );

    final result =
    <Map<String, Object?>>[];

    for (final row in rows) {
      final ruleId =
      _string(
        row[_ruleIdColumn],
      );

      final ruleSubject =
      _string(
        row[_ruleSubjectColumn],
      )?.toUpperCase();

      final normalizedRuleSubject =
      ruleSubject == null
          ? null
          : _normalizeSubjectCode(
        ruleSubject,
      );

      final ruleType =
      _string(
        row[_ruleTypeColumn],
      );

      final description =
      _string(
        row[_ruleDescriptionColumn],
      );

      debugPrint('');

      debugPrint(
        'Rule candidate:',
      );

      debugPrint(
        '  ID          : '
            '${ruleId ?? '(missing)'}',
      );

      debugPrint(
        '  Subject     : '
            '${ruleSubject ?? '(missing)'}',
      );

      debugPrint(
        '  Normalized  : '
            '${normalizedRuleSubject ?? '(missing)'}',
      );

      debugPrint(
        '  Type        : '
            '${ruleType ?? '(missing)'}',
      );

      debugPrint(
        '  Description : '
            '${description ?? '(none)'}',
      );

      if (normalizedRuleSubject ==
          normalizedSubject) {
        debugPrint(
          '  DECISION: MATCHED',
        );

        result.add(row);
      } else {
        debugPrint(
          '  DECISION: IGNORED',
        );

        debugPrint(
          '  Reason: Rule subject does not match '
              '$normalizedSubject.',
        );
      }
    }

    debugPrint('');
    debugPrint(
      'FINAL MATCHING RULE COUNT: '
          '${result.length}',
    );

    debugPrint(
      'For Subject=$normalizedSubject, '
          'MT_Type=$normalizedType',
    );

    debugPrint('------------------------------------------------');

    return result;
  }

  // ===========================================================================
  // SUBJECT TASK LOOKUP BY PARTIAL KEY
  // ===========================================================================

  /// Finds all active SubjectTasks whose SubjectTaskID begins with
  /// [partialKey].
  ///
  /// Example:
  ///
  ///   partialKey = PHY_PMT_
  ///
  /// executes:
  ///
  ///   SubjectTaskID LIKE 'PHY_PMT_%'
  Future<List<Map<String, Object?>>>
  _getSubjectTasksByPartialKey(
      String partialKey,
      ) async {
    debugPrint('');
    debugPrint('================================================');
    debugPrint('SUBJECT TASK MATCHING');
    debugPrint('================================================');

    debugPrint(
      'Partial Key : $partialKey',
    );

    debugPrint(
      'LIKE Pattern: ${partialKey}%',
    );

    debugPrint(
      'Active condition: '
          '$_subjectTaskActiveColumn = Yes',
    );

    final rows =
    await _db.query(
      _subjectTaskTable,
      where:
      '$_subjectTaskIdColumn LIKE ? '
          'AND $_subjectTaskActiveColumn = ?',
      whereArgs: [
        '$partialKey%',
        'Yes',
      ],
      orderBy:
      '$_subjectTaskIdColumn ASC',
    );

    debugPrint('');
    debugPrint(
      'Matching active SubjectTasks: '
          '${rows.length}',
    );

    if (rows.isEmpty) {
      debugPrint(
        'RESULT: No SubjectTask matched '
            '${partialKey}%',
      );
    } else {
      for (var i = 0;
      i < rows.length;
      i++) {
        final row = rows[i];

        debugPrint('');
        debugPrint(
          'MATCH ${i + 1}/${rows.length}',
        );

        debugPrint(
          '  SubjectTaskID   : '
              '${row[_subjectTaskIdColumn]}',
        );

        debugPrint(
          '  SubjectTaskName : '
              '${row[_subjectTaskNameColumn]}',
        );

        debugPrint(
          '  Active          : '
              '${row[_subjectTaskActiveColumn]}',
        );

        debugPrint(
          '  Duration        : '
              '${row[_subjectTaskDurationColumn]} minutes',
        );
      }
    }

    debugPrint('================================================');

    return rows;
  }

  // ===========================================================================
  // SUBJECT TASK LOOKUP BY ID
  // ===========================================================================

  Future<Map<String, Object?>?> _getSubjectTaskById(
      String subjectTaskId,
      ) async {
    debugPrint('');
    debugPrint(
      'SUBJECT TASK EXACT LOOKUP',
    );

    debugPrint(
      'SubjectTaskID: $subjectTaskId',
    );

    final rows =
    await _db.query(
      _subjectTaskTable,
      where:
      '$_subjectTaskIdColumn = ? '
          'AND $_subjectTaskActiveColumn = ?',
      whereArgs: [
        subjectTaskId,
        'Yes',
      ],
      limit: 1,
    );

    debugPrint(
      'Rows found: ${rows.length}',
    );

    if (rows.isEmpty) {
      debugPrint(
        'DECISION: SubjectTask not found '
            'or inactive.',
      );

      return null;
    }

    debugPrint(
      'DECISION: Active SubjectTask found.',
    );

    return rows.first;
  }

  // ===========================================================================
  // SUBJECT TASK ACTIVITIES + db_ACTIVITIES
  // ===========================================================================

  Future<List<Map<String, Object?>>>
  _getActivitiesForSubjectTask(
      String subjectTaskId,
      ) async {
    debugPrint('');
    debugPrint('------------------------------------------------');
    debugPrint('SUBJECT TASK → ACTIVITIES');
    debugPrint('------------------------------------------------');

    debugPrint(
      'SubjectTaskID: $subjectTaskId',
    );

    // -----------------------------------------------------------------------
    // GET LINKED ACTIVITIES
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'Looking up linked SubjectTaskActivity rows...',
    );

    final links =
    await _db.query(
      _subjectTaskActivityTable,
      where:
      'SubjectTaskID = ?',
      whereArgs: [
        subjectTaskId,
      ],
      orderBy:
      'ActivitySequence ASC',
    );

    debugPrint(
      'Linked SubjectTaskActivity rows: '
          '${links.length}',
    );

    if (links.isEmpty) {
      debugPrint(
        'DECISION: No activity links found.',
      );

      return const [];
    }

    final result =
    <Map<String, Object?>>[];

    // -----------------------------------------------------------------------
    // PROCESS EACH ACTIVITY LINK
    // -----------------------------------------------------------------------

    for (var i = 0;
    i < links.length;
    i++) {
      final link = links[i];

      final activityId =
      _string(
        link['ActivityID'],
      );

      final sequence =
      link['ActivitySequence'];

      debugPrint('');
      debugPrint(
        'Activity Link ${i + 1}/${links.length}',
      );

      debugPrint(
        '  ActivityID : '
            '${activityId ?? '(missing)'}',
      );

      debugPrint(
        '  Sequence   : '
            '${sequence ?? '(none)'}',
      );

      if (activityId == null) {
        debugPrint(
          '  DECISION: SKIPPED',
        );

        debugPrint(
          '  Reason: ActivityID missing.',
        );

        continue;
      }

      // ---------------------------------------------------------------------
      // LOOK UP ACTIVITY
      // ---------------------------------------------------------------------

      debugPrint(
        '  Looking up db_Activities...',
      );

      final activityRows =
      await _db.query(
        _activityTable,
        where:
        'ActivityID = ? '
            'AND IsActive = ?',
        whereArgs: [
          activityId,
          'Yes',
        ],
        limit: 1,
      );

      if (activityRows.isEmpty) {
        debugPrint(
          '  DECISION: SKIPPED',
        );

        debugPrint(
          '  Reason: Activity not found '
              'or inactive.',
        );

        continue;
      }

      final activity =
          activityRows.first;

      final activityName =
      _string(
        activity['ActivityName'],
      );

      final description =
      _activityDescription(
        activity,
      );

      final duration =
      _int(
        activity['ActivityDurationMinutes'],
      );

      debugPrint(
        '  DECISION: INCLUDED',
      );

      debugPrint(
        '  ActivityName        : '
            '${activityName ?? '(none)'}',
      );

      debugPrint(
        '  ActivityDescription : '
            '$description',
      );

      debugPrint(
        '  Duration            : '
            '${duration ?? 0} minutes',
      );

      debugPrint(
        '  IsActive            : '
            '${activity['IsActive']}',
      );

      // ---------------------------------------------------------------------
      // MERGE LINK + ACTIVITY
      // ---------------------------------------------------------------------

      result.add(
        <String, Object?>{
          ...link,
          ...activity,
        },
      );
    }

    // -----------------------------------------------------------------------
    // FINAL ACTIVITY LIST
    // -----------------------------------------------------------------------

    debugPrint('');
    debugPrint(
      'FINAL ACTIVE ACTIVITIES FOR '
          '$subjectTaskId: ${result.length}',
    );

    if (result.isEmpty) {
      debugPrint(
        'WARNING: All linked activities were '
            'missing or inactive.',
      );
    } else {
      for (var i = 0;
      i < result.length;
      i++) {
        final activity =
        result[i];

        debugPrint(
          '  ${i + 1}. '
              '${activity['ActivityID']}'
              ' | '
              '${_activityDescription(activity)}'
              ' | '
              '${_int(activity['ActivityDurationMinutes']) ?? 0} min',
        );
      }
    }

    debugPrint('------------------------------------------------');

    return result;
  }

  // ===========================================================================
  // DURATION
  // ===========================================================================

  int _taskDuration(
      Map<String, Object?> subjectTask,
      List<Map<String, Object?>> activities,
      ) {
    final configured =
    _int(
      subjectTask[
      _subjectTaskDurationColumn
      ],
    );

    if (configured != null) {
      debugPrint(
        'TASK DURATION DECISION: '
            'Using configured SubjectTask duration '
            '$configured minutes.',
      );

      return configured;
    }

    debugPrint(
      'TASK DURATION DECISION: '
          'No configured SubjectTask duration.',
    );

    debugPrint(
      'Calculating duration from activities...',
    );

    final calculated =
    activities.fold<int>(
      0,
          (sum, row) =>
      sum +
          (_int(
            row[
            'ActivityDurationMinutes'
            ],
          ) ??
              0),
    );

    debugPrint(
      'Calculated activity duration: '
          '$calculated minutes.',
    );

    return calculated;
  }

  // ===========================================================================
  // MILESTONE LOOKUP
  // ===========================================================================

  Future<Map<String, Object?>?>
  _getMilestone(
      DateTime date,
      String mtType,
      ) async {
    final normalizedType =
    mtType.trim().toUpperCase();

    final formattedDate =
    _formatDate(date);

    debugPrint('');
    debugPrint(
      'MILESTONE DATABASE QUERY',
    );

    debugPrint(
      'Table: $_milestoneTable',
    );

    debugPrint(
      'Type : $normalizedType',
    );

    debugPrint(
      'Date : $formattedDate',
    );

    final rows =
    await _db.query(
      _milestoneTable,
      where:
      '$_milestoneTypeColumn = ? '
          'AND $_milestoneDateColumn = ?',
      whereArgs: [
        normalizedType,
        formattedDate,
      ],
      limit: 1,
    );

    debugPrint(
      'Milestone rows found: ${rows.length}',
    );

    if (rows.isEmpty) {
      debugPrint(
        'Milestone lookup result: NOT FOUND',
      );

      return null;
    }

    debugPrint(
      'Milestone lookup result: FOUND',
    );

    return rows.first;
  }

  // ===========================================================================
  // MILESTONE CHAPTER SCOPE
  // ===========================================================================

  List<String> _milestoneScope(
      Map<String, Object?> milestone,
      String subjectCode,
      ) {
    final normalizedSubject =
    _normalizeSubjectCode(
      subjectCode,
    );

    final column =
    switch (normalizedSubject) {
      'PHY' => _phyColumn,
      'CHEM' => _chemColumn,
      'BIO' => _bioColumn,
      _ => null,
    };

    if (column == null) {
      debugPrint(
        'MILESTONE SCOPE: Unknown subject '
            '$subjectCode.',
      );

      return const [];
    }

    final rawValue =
    milestone[column]?.toString();

    debugPrint('');
    debugPrint(
      'MILESTONE SCOPE LOOKUP',
    );

    debugPrint(
      'Subject : $normalizedSubject',
    );

    debugPrint(
      'Column  : $column',
    );

    debugPrint(
      'Raw     : ${rawValue ?? '(null)'}',
    );

    final codes =
    _splitCodes(
      rawValue,
    );

    debugPrint(
      'Parsed chapters: $codes',
    );

    return codes;
  }

  // ===========================================================================
  // MARK SUBJECT TASKS CREATED
  // ===========================================================================

  Future<void> _markSubjectTasksCreated({
    required String subjectCode,
    required Map<String, Object?> milestone,
  }) async {
    final normalizedSubject =
    _normalizeSubjectCode(
      subjectCode,
    );

    final column =
    switch (normalizedSubject) {
      'PHY' => _phyTaskCreatedColumn,
      'CHEM' => _chemTaskCreatedColumn,
      'BIO' => _bioTaskCreatedColumn,
      _ => null,
    };

    if (column == null) {
      debugPrint(
        'Cannot update task-created flag for '
            '$subjectCode.',
      );

      return;
    }

    debugPrint('');
    debugPrint(
      'UPDATING SUBJECT TASK CREATED FLAG',
    );

    debugPrint(
      'Subject : $normalizedSubject',
    );

    debugPrint(
      'Column  : $column',
    );

    await _db.update(
      _milestoneTable,
      {
        column: 1,
      },
      where:
      '$_milestoneTypeColumn = ? '
          'AND $_milestoneDateColumn = ?',
      whereArgs: [
        milestone[
        _milestoneTypeColumn
        ],
        milestone[
        _milestoneDateColumn
        ],
      ],
    );

    debugPrint(
      '$normalizedSubject milestone '
          'task-created flag = 1',
    );
  }

  // ===========================================================================
  // MARK COMMON / PCB TASKS CREATED
  // ===========================================================================

  Future<void> _markCommonTasksCreated({
    required Map<String, Object?> milestone,
  }) async {
    debugPrint('');
    debugPrint(
      'UPDATING COMMON / PCB TASK CREATED FLAG',
    );

    await _db.update(
      _milestoneTable,
      {
        _commonTasksCreatedColumn: 1,
      },
      where:
      '$_milestoneTypeColumn = ? '
          'AND $_milestoneDateColumn = ?',
      whereArgs: [
        milestone[
        _milestoneTypeColumn
        ],
        milestone[
        _milestoneDateColumn
        ],
      ],
    );

    debugPrint(
      'PCB/common milestone '
          'task-created flag = 1',
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
    final compactDate =
    _compactDate(
      milestoneDate,
    );

    final taskId =
        'MT_${compactDate}_'
        '${ruleId}_'
        '$subjectTaskId';

    debugPrint('');
    debugPrint(
      'TASK ID BUILDER',
    );

    debugPrint(
      '  Milestone Date : '
          '${_formatDate(milestoneDate)}',
    );

    debugPrint(
      '  Compact Date   : '
          '$compactDate',
    );

    debugPrint(
      '  Rule ID        : '
          '$ruleId',
    );

    debugPrint(
      '  SubjectTaskID  : '
          '$subjectTaskId',
    );

    debugPrint(
      '  FINAL TaskID   : '
          '$taskId',
    );

    return taskId;
  }

  // ===========================================================================
  // ACTIVITY DESCRIPTION
  // ===========================================================================

  String _activityDescription(
      Map<String, Object?> activity,
      ) {
    final description =
    _string(
      activity['ActivityDescription'],
    );

    if (description != null) {
      return description;
    }

    final name =
    _string(
      activity['ActivityName'],
    );

    if (name != null) {
      return name;
    }

    final id =
    _string(
      activity['ActivityID'],
    );

    if (id != null) {
      return id;
    }

    return 'Activity';
  }

  // ===========================================================================
  // SUBJECT CODE NORMALIZATION
  // ===========================================================================

  String _normalizeSubjectCode(
      String value,
      ) {
    final code =
    value.trim().toUpperCase();

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
    final value =
    _string(
      milestone[
      _milestoneDateColumn
      ],
    );

    if (value == null) {
      debugPrint(
        'ERROR: Milestone date is missing.',
      );

      throw StateError(
        'Milestone date is missing.',
      );
    }

    debugPrint(
      'Parsing milestone date: $value',
    );

    return DateTime.parse(
      value,
    );
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
    final month =
    date.month
        .toString()
        .padLeft(2, '0');

    final day =
    date.day
        .toString()
        .padLeft(2, '0');

    return '${date.year}-$month-$day';
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
    if (value == null ||
        value.trim().isEmpty) {
      return const [];
    }

    return value
        .split(',')
        .map(
          (e) => e.trim(),
    )
        .where(
          (e) => e.isNotEmpty,
    )
        .toList();
  }

  static String? _string(
      Object? value,
      ) {
    final text =
    value?.toString().trim();

    if (text == null ||
        text.isEmpty) {
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