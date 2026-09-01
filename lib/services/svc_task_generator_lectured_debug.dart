import 'package:sqflite/sqflite.dart';

/// EPMS Lecture Task Generator.
///
/// Generation hierarchy:
///
///   db_LectureLog
///        │
///        └── LECTURE_RECORDED
///                  │
///                  ▼
///        db_TaskCreationRuleWeekDay
///                  │
///                  ▼
///        db_SubjectTasks
///                  │
///                  ▼
///        db_SubjectTaskActivities
///                  │
///                  ▼
///        db_Activities
///                  │
///                  ▼
///        db_TaskLogWeekDay
///
/// Philosophy:
/// - LectureService saves the lecture first.
/// - LectureService transaction is committed and released.
/// - This generator starts afterwards.
/// - The generator reads the saved lecture from db_LectureLog.
/// - Rules are matched using TriggerCode + RuleSubjectTaskID.
/// - SubjectTask activities determine the actual task content.
/// - DayOffset determines the task due date.
/// - Existing tasks are not duplicated.
/// - lecture_task_created remains 0 until task generation succeeds.
/// - After successful generation, lecture_task_created is set to 1.
///
/// No calendar work is performed here.
/// No database is opened/configured here.
/// No lecture is created here.
class TaskGeneratorLectured {
  TaskGeneratorLectured({
    required Database db,
    DateTime Function()? now,
  })  : _db = db,
        _now = now ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;

// ===========================================================================
// TABLES
// ===========================================================================

  static const String _lectureLogTable = 'db_LectureLog';
  static const String _ruleTable = 'db_TaskCreationRuleWeekDay';
  static const String _subjectTaskTable = 'db_SubjectTasks';
  static const String _subjectTaskActivityTable = 'db_SubjectTaskActivities';
  static const String _activityTable = 'db_Activities';
  static const String _taskLogTable = 'db_TaskLogWeekDay';

// ===========================================================================
// COLUMNS
// ===========================================================================

  static const String _lectureIdColumn = 'lecture_id';
  static const String _lectureTypeColumn = 'lecture_type_code';
  static const String _lectureTaskCreatedColumn = 'lecture_task_created';

  static const String _triggerCodeColumn = 'TriggerCode';
  static const String _ruleSubjectTaskIdColumn = 'RuleSubjectTaskID';
  static const String _ruleActiveColumn = 'IsActive';

  static const String _subjectTaskIdColumn = 'SubjectTaskID';
  static const String _subjectTaskActiveColumn = 'SubjectTaskIsActive';

  static const String _activityIdColumn = 'ActivityID';
  static const String _activitySequenceColumn = 'ActivitySequence';
  static const String _activityDurationColumn = 'ActivityDurationMinutes';
  static const String _activityDayOffsetColumn = 'DayOffset';
  static const String _activityMandatoryColumn = 'IsMandatory';

// ===========================================================================
// PUBLIC METHOD
// ===========================================================================

  /// Generates lecture-driven WeekDay tasks for [lectureId].
  ///
  /// Expected trigger:
  ///
  ///   LECTURE_RECORDED
  ///
  /// The lecture must already exist in db_LectureLog.
  ///
  /// The lecture_task_created flag is changed from 0 to 1 only after
  /// all applicable task generation has completed successfully.
  Future<LectureTaskGenerationResult> generateLectureTasks({
    required String lectureId,
    String triggerCode = 'LECTURE_RECORDED',
  }) async {
    final cleanLectureId = lectureId.trim();
    final cleanTriggerCode = triggerCode.trim();

    if (cleanLectureId.isEmpty) {
      throw ArgumentError.value(lectureId, 'lectureId');
    }

    if (cleanTriggerCode.isEmpty) {
      throw ArgumentError.value(triggerCode, 'triggerCode');
    }

// -------------------------------------------------------------------------
// 1. READ LECTURE
// -------------------------------------------------------------------------

    final lecture = await _getLecture(cleanLectureId);

    if (lecture == null) {
      throw StateError(
        'Lecture not found in db_LectureLog: $cleanLectureId',
      );
    }

// -------------------------------------------------------------------------
// 2. CHECK TASK-CREATED FLAG
// -------------------------------------------------------------------------

    final taskCreated = _int(lecture[_lectureTaskCreatedColumn]) ?? 0;

    if (taskCreated == 1) {
      final existingTaskIds = await _getLectureTaskIds(
        cleanLectureId,
      );

      return LectureTaskGenerationResult(
        lectureId: cleanLectureId,
        success: true,
        tasksCreated: existingTaskIds.length,
        taskIds: existingTaskIds,
        alreadyGenerated: true,
        message: existingTaskIds.isEmpty
            ? 'Lecture tasks were already marked as created.'
            : 'Lecture tasks were already created.',
      );
    }

// -------------------------------------------------------------------------
// 3. READ LECTURE ID COMPONENTS
// -------------------------------------------------------------------------

    final lectureParts = LectureIdParts.parse(cleanLectureId);

// -------------------------------------------------------------------------
// 4. FIND MATCHING RULES
// -------------------------------------------------------------------------

    final rules = await _getMatchingRules(
      triggerCode: cleanTriggerCode,
      subjectCode: lectureParts.subjectCode,
    );

    if (rules.isEmpty) {
// No applicable rule means there is nothing to generate.
//
// IMPORTANT:
// We do NOT mark lecture_task_created = 1 here.
//
// This preserves the meaning:
//   0 = task generation has not successfully completed.
//
      return LectureTaskGenerationResult(
        lectureId: cleanLectureId,
        success: true,
        tasksCreated: 0,
        taskIds: const [],
        alreadyGenerated: false,
        message: 'Lecture saved. No applicable task rules were found.',
      );
    }

// -------------------------------------------------------------------------
// 5. RESOLVE RULE -> SUBJECT TASK -> ACTIVITIES
// -------------------------------------------------------------------------

    final occurrences = <_TaskOccurrence>[];

    final processedSubjectTaskIds = <String>{};

    for (final rule in rules) {
      final subjectTaskId = _string(rule[_ruleSubjectTaskIdColumn]);

      if (subjectTaskId == null) {
        continue;
      }

// Avoid generating the same SubjectTask twice if duplicate rules
// point to the same SubjectTask.
      if (!processedSubjectTaskIds.add(subjectTaskId)) {
        continue;
      }

      final subjectTask = await _getActiveSubjectTask(subjectTaskId);

      if (subjectTask == null) {
        continue;
      }

      final activities = await _getActivitiesForSubjectTask(subjectTaskId);

      if (activities.isEmpty) {
        continue;
      }

      final subjectName =
          _string(subjectTask['SubjectTaskName']) ?? subjectTaskId;

// Activities are grouped by DayOffset.
//
// Example:
//
// DayOffset 0
//   Activity 1
//   Activity 2
//
// DayOffset 1
//   Activity 3
//
// DayOffset 3
//   Activity 4
//
      final grouped = <int, List<Map<String, Object?>>>{};

      for (final activity in activities) {
        final dayOffset = _int(activity[_activityDayOffsetColumn]) ?? 0;

        grouped.putIfAbsent(dayOffset, () => []);
        grouped[dayOffset]!.add(activity);
      }

      final sortedOffsets = grouped.keys.toList()..sort();

      for (final dayOffset in sortedOffsets) {
        final dayActivities = grouped[dayOffset]!;

        dayActivities.sort(
          (a, b) => (_int(a[_activitySequenceColumn]) ?? 0).compareTo(
            _int(b[_activitySequenceColumn]) ?? 0,
          ),
        );

        final duration = _taskDuration(
          subjectTask: subjectTask,
          activities: dayActivities,
        );

        final description = _buildTaskDescription(
          subjectName: lectureParts.subjectCode,
          chapterName: lectureParts.chapterCode,
          topicName: lectureParts.topicCode,
          subjectTaskName: subjectName,
          activities: dayActivities,
        );

        final dueDate = _dateOnly(
          lectureParts.lectureDateParsed.add(
            Duration(days: dayOffset),
          ),
        );

        final taskId = _buildTaskId(
          lectureId: cleanLectureId,
          subjectTaskId: subjectTaskId,
          dayOffset: dayOffset,
        );

        occurrences.add(
          _TaskOccurrence(
            taskId: taskId,
            taskDescription: description,
            taskDueDate: dueDate,
            taskDurationMinutes: duration,
          ),
        );
      }
    }

// -------------------------------------------------------------------------
// 6. CREATE TASKS
// -------------------------------------------------------------------------

    final createdTaskIds = <String>[];

    for (final occurrence in occurrences) {
      final inserted = await _createTaskIfAbsent(
        occurrence,
      );

      if (inserted) {
        createdTaskIds.add(occurrence.taskId);
      } else {
// Existing task is also considered successfully present.
        createdTaskIds.add(occurrence.taskId);
      }
    }

// -------------------------------------------------------------------------
// 7. MARK LECTURE TASKS CREATED
// -------------------------------------------------------------------------

//
// We mark the lecture only when generation has reached the end without
// throwing an exception.
//
// If task insertion throws, this method exits through the exception and
// this update never happens.
//
    if (occurrences.isNotEmpty) {
      await _markLectureTasksCreated(
        cleanLectureId,
      );
    }

    return LectureTaskGenerationResult(
      lectureId: cleanLectureId,
      success: true,
      tasksCreated: createdTaskIds.length,
      taskIds: createdTaskIds,
      alreadyGenerated: false,
      message: occurrences.isEmpty
          ? 'Lecture saved. No tasks were generated.'
          : 'Lecture saved and ${createdTaskIds.length} task(s) generated.',
    );
  }

// ===========================================================================
// LECTURE LOOKUP
// ===========================================================================

  Future<Map<String, Object?>?> _getLecture(
    String lectureId,
  ) async {
    final rows = await _db.query(
      _lectureLogTable,
      where: '$_lectureIdColumn = ?',
      whereArgs: [lectureId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

// ===========================================================================
// RULE LOOKUP
// ===========================================================================

  Future<List<Map<String, Object?>>> _getMatchingRules({
    required String triggerCode,
    required String subjectCode,
  }) async {
    final rows = await _db.query(
      _ruleTable,
      where: '$_ruleActiveColumn = ? AND $_triggerCodeColumn = ?',
      whereArgs: [
        'Yes',
        triggerCode,
      ],
      orderBy: 'RuleID ASC',
    );

    final result = <Map<String, Object?>>[];

    final normalizedSubject = _normalizeSubjectCode(subjectCode);

    for (final row in rows) {
      final subjectTaskId = _string(row[_ruleSubjectTaskIdColumn]);

      if (subjectTaskId == null) {
        continue;
      }

      if (_subjectTaskBelongsToSubject(
        subjectTaskId,
        normalizedSubject,
      )) {
        result.add(row);
      }
    }

    return result;
  }

// ===========================================================================
// SUBJECT TASK LOOKUP
// ===========================================================================

  Future<Map<String, Object?>?> _getActiveSubjectTask(
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

    return rows.isEmpty ? null : rows.first;
  }

// ===========================================================================
// SUBJECT TASK ACTIVITIES
// ===========================================================================

  Future<List<Map<String, Object?>>> _getActivitiesForSubjectTask(
    String subjectTaskId,
  ) async {
    final links = await _db.query(
      _subjectTaskActivityTable,
      where: '$_subjectTaskIdColumn = ?',
      whereArgs: [subjectTaskId],
      orderBy: '$_activitySequenceColumn ASC',
    );

    final result = <Map<String, Object?>>[];

    for (final link in links) {
      final activityId = _string(link[_activityIdColumn]);

      if (activityId == null) {
        continue;
      }

      final activityRows = await _db.query(
        _activityTable,
        where: '$_activityIdColumn = ? AND IsActive = ?',
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
// TASK CREATION
// ===========================================================================

  Future<bool> _createTaskIfAbsent(
    _TaskOccurrence occurrence,
  ) async {
    final existing = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [occurrence.taskId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return false;
    }

    await _db.insert(
      _taskLogTable,
      <String, Object?>{
        'TaskID': occurrence.taskId,
        'TaskDescription': occurrence.taskDescription,
        'TaskDueDate': _formatDate(occurrence.taskDueDate),
        'TaskStartTime': null,
        'TaskDurationMinutes': occurrence.taskDurationMinutes,
        'TaskCalendarEventID': null,
        'TaskReminderMinutes': null,
        'TaskStatus': 'PENDING',
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    return true;
  }

// ===========================================================================
// LECTURE FLAG
// ===========================================================================

  Future<void> _markLectureTasksCreated(
    String lectureId,
  ) async {
    await _db.update(
      _lectureLogTable,
      <String, Object?>{
        _lectureTaskCreatedColumn: 1,
      },
      where: '$_lectureIdColumn = ?',
      whereArgs: [lectureId],
    );
  }

// ===========================================================================
// TASK DESCRIPTION
// ===========================================================================

  String _buildTaskDescription({
    required String subjectName,
    required String chapterName,
    required String topicName,
    required String subjectTaskName,
    required List<Map<String, Object?>> activities,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('Subject - $subjectName');
    buffer.writeln('Chapter - $chapterName');

    if (subjectTaskName.trim().isNotEmpty) {
      buffer.writeln('Task Type - $subjectTaskName');
    }

    for (var i = 0; i < activities.length; i++) {
      final activity = activities[i];

      final sequence = _int(activity[_activitySequenceColumn]) ?? (i + 1);

      final activityName = _string(activity['ActivityDisplayName']) ??
          _string(activity['ActivityDescription']) ??
          _string(activity['ActivityName']) ??
          _string(activity[_activityIdColumn]) ??
          'Activity';

      final prefix = i == 0 ? 'ToDo    - ' : '        - ';

      buffer.write(prefix);
      buffer.write('$sequence. ');
      buffer.write(topicName);
      buffer.write(' - ');
      buffer.writeln(activityName);
    }

    return buffer.toString().trimRight();
  }

// ===========================================================================
// TASK ID
// ===========================================================================

  String _buildTaskId({
    required String lectureId,
    required String subjectTaskId,
    required int dayOffset,
  }) {
//
// Example:
//
// Lecture:
// PHY-CH01-T01-L01-20260901
//
// Task:
// WD_PHY-CH01-T01-L01-20260901_PHY_STUDY_D0
//
// This guarantees that DayOffset 0, 1 and 3 are separate tasks.
//
    return 'WD_${lectureId}_${subjectTaskId}_D$dayOffset';
  }

// ===========================================================================
// DURATION
// ===========================================================================

  int _taskDuration({
    required Map<String, Object?> subjectTask,
    required List<Map<String, Object?>> activities,
  }) {
    final configured = _int(subjectTask['SubjectTaskDurationMinutes']);

    if (configured != null) {
      return configured;
    }

    return activities.fold<int>(
      0,
      (sum, row) => sum + (_int(row[_activityDurationColumn]) ?? 0),
    );
  }

// ===========================================================================
// SUBJECT ROUTING
// ===========================================================================

  bool _subjectTaskBelongsToSubject(
    String subjectTaskId,
    String subjectCode,
  ) {
    final task = subjectTaskId.trim().toUpperCase();

    final subject = _normalizeSubjectCode(subjectCode);

    return task == subject || task.startsWith('${subject}_');
  }

  String _normalizeSubjectCode(String value) {
    final code = value.trim().toUpperCase();

    switch (code) {
      case 'PHYSICS':
      case 'PHY':
        return 'PHY';

      case 'CHEMISTRY':
      case 'CHEM':
      case 'BHEM':
        return 'CHEM';

      case 'BIOLOGY':
      case 'BIO':
        return 'BIO';

      default:
        return code;
    }
  }

// ===========================================================================
// LECTURE TASK LOOKUP
// ===========================================================================

  Future<List<String>> _getLectureTaskIds(
    String lectureId,
  ) async {
    final pattern = 'WD_${lectureId}_%';

    final rows = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID LIKE ?',
      whereArgs: [pattern],
      orderBy: 'TaskID ASC',
    );

    return rows
        .map((row) => _string(row['TaskID']))
        .whereType<String>()
        .toList();
  }

// ===========================================================================
// LECTURE ID PARSER
// ===========================================================================

  /// Application LectureID format:
  ///
  ///   SubjectCode-ChapterCode-TopicCode-LNN-YYYYMMDD
  ///
  /// Example:
  ///
  ///   PHY-CH01-T01-L03-20260818
  ///
  /// This matches the LectureService _buildLectureId() format.
  static LectureIdParts _parseLectureId(
    String lectureId,
  ) {
    return LectureIdParts.parse(lectureId);
  }

// ===========================================================================
// GENERIC HELPERS
// ===========================================================================

  static String? _string(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
      value?.toString() ?? '',
    );
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }
}

// ============================================================================
// LECTURE ID PARTS
// ============================================================================

class LectureIdParts {
  const LectureIdParts({
    required this.lectureId,
    required this.subjectCode,
    required this.chapterCode,
    required this.topicCode,
    required this.lectureNumber,
    required this.lectureDate,
  });

  final String lectureId;
  final String subjectCode;
  final String chapterCode;
  final String topicCode;
  final String lectureNumber;
  final String lectureDate;

  DateTime get lectureDateParsed {
    final parsed = _parseLectureDate(lectureDate);

    if (parsed == null) {
      throw FormatException(
        'Invalid lecture date in LectureID: $lectureId',
      );
    }

    return parsed;
  }

  static LectureIdParts parse(String lectureId) {
    final raw = lectureId.trim();

    final parts = raw
        .split('-')
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim())
        .toList();

    if (parts.length != 5) {
      throw FormatException(
        'Unable to parse LectureID "$lectureId". '
        'Expected format: '
        'SubjectCode-ChapterCode-TopicCode-LNN-YYYYMMDD.',
      );
    }

    final subjectCode = parts[0];
    final chapterCode = parts[1];
    final topicCode = parts[2];
    final lectureNumber = parts[3];
    final lectureDate = parts[4];

    if (subjectCode.isEmpty ||
        chapterCode.isEmpty ||
        topicCode.isEmpty ||
        lectureNumber.isEmpty ||
        lectureDate.isEmpty) {
      throw FormatException(
        'LectureID contains an empty component: $lectureId',
      );
    }

    if (!RegExp(r'^L\d+$').hasMatch(
      lectureNumber.toUpperCase(),
    )) {
      throw FormatException(
        'Invalid lecture number in LectureID: $lectureId',
      );
    }

    if (!RegExp(r'^\d{8}$').hasMatch(lectureDate)) {
      throw FormatException(
        'Invalid lecture date in LectureID: $lectureId',
      );
    }

    if (_parseLectureDate(lectureDate) == null) {
      throw FormatException(
        'Invalid calendar date in LectureID: $lectureId',
      );
    }

    return LectureIdParts(
      lectureId: raw,
      subjectCode: subjectCode,
      chapterCode: chapterCode,
      topicCode: topicCode,
      lectureNumber: lectureNumber,
      lectureDate: lectureDate,
    );
  }

  static DateTime? _parseLectureDate(String value) {
    if (!RegExp(r'^\d{8}$').hasMatch(value)) {
      return null;
    }

    final year = int.tryParse(value.substring(0, 4));

    final month = int.tryParse(value.substring(4, 6));

    final day = int.tryParse(value.substring(6, 8));

    if (year == null || month == null || day == null) {
      return null;
    }

    final date = DateTime(
      year,
      month,
      day,
    );

    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }

    return date;
  }
}

// ============================================================================
// TASK OCCURRENCE
// ============================================================================

class _TaskOccurrence {
  const _TaskOccurrence({
    required this.taskId,
    required this.taskDescription,
    required this.taskDueDate,
    required this.taskDurationMinutes,
  });

  final String taskId;
  final String taskDescription;
  final DateTime taskDueDate;
  final int taskDurationMinutes;
}

// ============================================================================
// GENERATOR RESULT
// ============================================================================

class LectureTaskGenerationResult {
  const LectureTaskGenerationResult({
    required this.lectureId,
    required this.success,
    required this.tasksCreated,
    required this.taskIds,
    required this.alreadyGenerated,
    required this.message,
  });

  final String lectureId;
  final bool success;
  final int tasksCreated;
  final List<String> taskIds;
  final bool alreadyGenerated;
  final String message;
}
