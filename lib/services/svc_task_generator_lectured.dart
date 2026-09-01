import 'package:sqflite/sqflite.dart';
import '../services/svc_status_topics.dart';

/// EPMS Lecture Task Generator
///
/// DEBUG VERSION
///
/// Flow:
///
/// db_LectureLog
///      ↓
/// LECTURE_RECORDED
///      ↓
/// db_TaskCreationRuleWeekDay
///      ↓
/// db_SubjectTasks
///      ↓
/// db_SubjectTaskActivities
///      ↓
/// db_Activities
///      ↓
/// db_TaskLogWeekDay
///      ↓
/// db_LectureLog.lecture_task_created = 1
///
/// IMPORTANT:
/// This service does not create/save the lecture.
/// LectureService must complete and commit the lecture first.
///
/// This version contains detailed terminal logging so that every stage
/// of lecture task generation can be diagnosed.
///
class TaskGeneratorLectured {
  TaskGeneratorLectured({
    required Database db,
    DateTime Function()? now,
  })  : _db = db,
        _now = now ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;

  final StatusTopicService _statusTopicService = StatusTopicService.instance;

  static const String _lectureLogTable = 'db_LectureLog';
  static const String _ruleTable = 'db_TaskCreationRuleWeekDay';
  static const String _subjectTaskTable = 'db_SubjectTasks';
  static const String _subjectTaskActivityTable = 'db_SubjectTaskActivities';
  static const String _activityTable = 'db_Activities';
  static const String _taskLogTable = 'db_TaskLogWeekDay';

  static const String _triggerCode = 'LECTURE_RECORDED';

// ===========================================================================
// DEBUG
// ===========================================================================

  void _log(String message) {
    print(
      '[LECTURED GENERATOR] '
      '${DateTime.now().toIso8601String()} '
      '$message',
    );
  }

  void _section(String title) {
    print('');
    print(
      '[LECTURED GENERATOR] '
      '============================================================',
    );
    print('[LECTURED GENERATOR] $title');
    print(
      '[LECTURED GENERATOR] '
      '============================================================',
    );
  }

// ===========================================================================
// MAIN GENERATOR
// ===========================================================================

  Future<LectureTaskGenerationResult> generateLectureTasks({
    required String lectureId,
    String triggerCode = _triggerCode,
  }) async {
    _section('GENERATE LECTURE TASKS START');

    final cleanLectureId = lectureId.trim();
    final cleanTriggerCode = triggerCode.trim();

    _log('lectureId=$cleanLectureId');
    _log('triggerCode=$cleanTriggerCode');

    if (cleanLectureId.isEmpty) {
      _log('ERROR: lectureId is empty.');
      throw ArgumentError.value(
        lectureId,
        'lectureId',
      );
    }

    if (cleanTriggerCode.isEmpty) {
      _log('ERROR: triggerCode is empty.');
      throw ArgumentError.value(
        triggerCode,
        'triggerCode',
      );
    }

// -------------------------------------------------------------------------
// STEP 1 - READ LECTURE
// -------------------------------------------------------------------------

    _section('STEP 1 - READ db_LectureLog');

    _log(
      'Querying $_lectureLogTable '
      'where lecture_id=$cleanLectureId',
    );

    final lecture = await _getLecture(cleanLectureId);

    if (lecture == null) {
      _log('ERROR: Lecture record NOT FOUND.');
      _log(
        'The lecture was expected to exist because '
        'LectureService.saveLecture() already completed.',
      );

      throw StateError(
        'Lecture not found in db_LectureLog: $cleanLectureId',
      );
    }

    _log('Lecture record FOUND.');

    _log('Lecture database values:');

    lecture.forEach((key, value) {
      _log('  $key = $value');
    });

// -------------------------------------------------------------------------
// STEP 2 - CHECK FLAG
// -------------------------------------------------------------------------

    _section('STEP 2 - CHECK lecture_task_created');

    final taskCreated = _int(lecture['lecture_task_created']) ?? 0;

    _log(
      'lecture_task_created=$taskCreated',
    );

    if (taskCreated == 1) {
      _log(
        'Lecture tasks are already marked as created.',
      );

      final existingTaskIds = await _getLectureTaskIds(cleanLectureId);

      _log(
        'Existing lecture task count='
        '${existingTaskIds.length}',
      );

      for (final id in existingTaskIds) {
        _log('Existing TaskID=$id');
      }

      return LectureTaskGenerationResult(
        lectureId: cleanLectureId,
        success: true,
        tasksCreated: existingTaskIds.length,
        taskIds: existingTaskIds,
        alreadyGenerated: true,
        message: 'Lecture tasks were already generated.',
      );
    }

    _log(
      'lecture_task_created=0. '
      'Task generation will continue.',
    );

// -------------------------------------------------------------------------
// STEP 3 - PARSE LECTURE ID
// -------------------------------------------------------------------------

    _section('STEP 3 - PARSE LectureID');

    _log(
      'Parsing LectureID=$cleanLectureId',
    );

    final lectureParts = LectureIdParts.parse(cleanLectureId);

    _log(
      'Parsed LectureID:',
    );

    _log(
      '  subjectCode=${lectureParts.subjectCode}',
    );

    _log(
      '  chapterCode=${lectureParts.chapterCode}',
    );

    _log(
      '  topicCode=${lectureParts.topicCode}',
    );

    _log(
      '  lectureNumber=${lectureParts.lectureNumber}',
    );

    _log(
      '  lectureDate=${lectureParts.lectureDate}',
    );
// -------------------------------------------------------------------------
// STEP 3A - GET TOPIC DETAILS FROM db_StatusTopics
// -------------------------------------------------------------------------

    _section(
      'STEP 3A - GET TOPIC DETAILS FROM db_StatusTopics',
    );

    final topicId =
        '${lectureParts.subjectCode}-${lectureParts.chapterCode}-${lectureParts.topicCode}';

    _log(
      'Looking up StatusTopic using TopicID=$topicId',
    );

    final statusTopic = await _statusTopicService.findByTopicId(topicId);

    if (statusTopic == null) {
      _log(
        'WARNING: StatusTopic NOT FOUND for TopicID=$topicId',
      );
    } else {
      _log(
        'StatusTopic FOUND for TopicID=$topicId',
      );

      statusTopic.forEach((key, value) {
        _log(
          '  StatusTopic.$key = $value',
        );
      });
    }
    final topicName = statusTopic?['TopicName']?.toString().trim() ?? '';

    final chapterName =
        statusTopic?['TopicChapterName']?.toString().trim() ?? '';
// -------------------------------------------------------------------------
// STEP 4 - FIND RULES
// -------------------------------------------------------------------------

    _section(
      'STEP 4 - FIND MATCHING TASK CREATION RULES',
    );

    _log(
      'TriggerCode=$cleanTriggerCode',
    );

    _log(
      'SubjectCode=${lectureParts.subjectCode}',
    );

    final rules = await _getMatchingRules(
      triggerCode: cleanTriggerCode,
      subjectCode: lectureParts.subjectCode,
    );

    _log(
      'Matching rule count=${rules.length}',
    );

    if (rules.isEmpty) {
      _log(
        'WARNING: No matching WeekDay task creation rules found.',
      );

      _log(
        'Task generation will stop without setting '
        'lecture_task_created=1.',
      );

      return LectureTaskGenerationResult(
        lectureId: cleanLectureId,
        success: true,
        tasksCreated: 0,
        taskIds: const [],
        alreadyGenerated: false,
        message: 'Lecture saved. No applicable task rules found.',
      );
    }

    for (var i = 0; i < rules.length; i++) {
      final rule = rules[i];

      _log('RULE ${i + 1}:');

      rule.forEach((key, value) {
        _log('  $key = $value');
      });
    }

// -------------------------------------------------------------------------
// STEP 5 - RESOLVE SUBJECT TASKS
// -------------------------------------------------------------------------

    _section(
      'STEP 5 - RESOLVE SUBJECT TASKS',
    );

    final occurrences = <_TaskOccurrence>[];

    final processedSubjectTaskIds = <String>{};

    for (final rule in rules) {
      final subjectTaskId = _string(rule['RuleSubjectTaskID']);

      _log(
        'Processing RuleSubjectTaskID=$subjectTaskId',
      );

      if (subjectTaskId == null) {
        _log(
          'WARNING: Rule has empty RuleSubjectTaskID. '
          'Skipping.',
        );

        continue;
      }

      if (!processedSubjectTaskIds.add(subjectTaskId)) {
        _log(
          'SubjectTaskID=$subjectTaskId already processed. '
          'Skipping duplicate rule.',
        );

        continue;
      }

      _log(
        'Querying db_SubjectTasks '
        'for SubjectTaskID=$subjectTaskId',
      );

      final subjectTask = await _getActiveSubjectTask(
        subjectTaskId,
      );

      if (subjectTask == null) {
        _log(
          'WARNING: SubjectTask NOT FOUND or inactive: '
          '$subjectTaskId',
        );

        continue;
      }

      _log(
        'SubjectTask FOUND: $subjectTaskId',
      );

      subjectTask.forEach((key, value) {
        _log(
          '  SubjectTask.$key = $value',
        );
      });

// -----------------------------------------------------------------------
// STEP 6 - ACTIVITIES
// -----------------------------------------------------------------------

      _section(
        'STEP 6 - RESOLVE ACTIVITIES '
        'FOR $subjectTaskId',
      );

      final activities = await _getActivitiesForSubjectTask(
        subjectTaskId,
      );

      _log(
        'Resolved activity count=${activities.length}',
      );

      if (activities.isEmpty) {
        _log(
          'WARNING: No activities found for '
          '$subjectTaskId. Skipping.',
        );

        continue;
      }

      for (var i = 0; i < activities.length; i++) {
        final activity = activities[i];

        _log(
          'ACTIVITY ${i + 1}:',
        );

        activity.forEach((key, value) {
          _log(
            '  $key = $value',
          );
        });
      }

// -----------------------------------------------------------------------
// STEP 7 - GROUP BY DAY OFFSET
// -----------------------------------------------------------------------

      _section(
        'STEP 7 - GROUP ACTIVITIES BY DayOffset',
      );

      final grouped = <int, List<Map<String, Object?>>>{};

      for (final activity in activities) {
        final dayOffset = _int(activity['DayOffset']) ?? 0;

        _log(
          'Activity '
          '${activity['ActivityID']} '
          'has DayOffset=$dayOffset',
        );

        grouped.putIfAbsent(
          dayOffset,
          () => [],
        );

        grouped[dayOffset]!.add(activity);
      }

      final sortedOffsets = grouped.keys.toList()..sort();

      _log(
        'DayOffset groups=${sortedOffsets.length}',
      );

      for (final offset in sortedOffsets) {
        _log(
          'DayOffset=$offset '
          'contains ${grouped[offset]!.length} activities.',
        );
      }

// -----------------------------------------------------------------------
// STEP 8 - BUILD TASK OCCURRENCES
// -----------------------------------------------------------------------

      _section(
        'STEP 8 - BUILD TASK OCCURRENCES',
      );

      final subjectTaskName = _string(
            subjectTask['SubjectTaskName'],
          ) ??
          subjectTaskId;

      for (final dayOffset in sortedOffsets) {
        final dayActivities = grouped[dayOffset]!;

        dayActivities.sort(
          (a, b) => (_int(a['ActivitySequence']) ?? 0).compareTo(
            _int(b['ActivitySequence']) ?? 0,
          ),
        );

        final duration = _taskDuration(
          subjectTask: subjectTask,
          activities: dayActivities,
        );

        final description = _buildTaskDescription(
          subjectName: lectureParts.subjectCode,
          chapterName: '${lectureParts.chapterCode} - $chapterName',
          topicName: '${lectureParts.topicCode} - $topicName',
          subjectTaskName: subjectTaskName,
          activities: dayActivities,
        );

        final dueDate = _dateOnly(
          lectureParts.lectureDateParsed.add(
            Duration(
              days: dayOffset,
            ),
          ),
        );

        final taskId = _buildTaskId(
          lectureId: cleanLectureId,
          subjectTaskId: subjectTaskId,
          dayOffset: dayOffset,
        );

        _log('TASK OCCURRENCE:');
        _log('  TaskID=$taskId');
        _log('  DayOffset=$dayOffset');
        _log(
          '  TaskDueDate=${_formatDate(dueDate)}',
        );
        _log(
          '  Duration=$duration minutes',
        );
        _log('  Description:');
        _log(description);

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
// STEP 9 - CREATE TASKS
// -------------------------------------------------------------------------

    _section(
      'STEP 9 - INSERT TASKS INTO db_TaskLogWeekDay',
    );

    _log(
      'Total task occurrences=${occurrences.length}',
    );

    final createdTaskIds = <String>[];

    for (final occurrence in occurrences) {
      _log('');
      _log(
        'Processing TaskID=${occurrence.taskId}',
      );

      final inserted = await _createTaskIfAbsent(
        occurrence,
      );

      if (inserted) {
        _log(
          'TASK INSERTED successfully: '
          '${occurrence.taskId}',
        );

        createdTaskIds.add(
          occurrence.taskId,
        );
      } else {
        _log(
          'TASK ALREADY EXISTS: '
          '${occurrence.taskId}',
        );

        createdTaskIds.add(
          occurrence.taskId,
        );
      }
    }

// -------------------------------------------------------------------------
// STEP 10 - UPDATE LECTURE FLAG
// -------------------------------------------------------------------------

    if (occurrences.isNotEmpty) {
      _section(
        'STEP 10 - UPDATE lecture_task_created',
      );

      _log(
        'Updating db_LectureLog:',
      );

      _log(
        '  lecture_id=$cleanLectureId',
      );

      _log(
        '  lecture_task_created: 0 -> 1',
      );

      await _markLectureTasksCreated(
        cleanLectureId,
      );

      _log(
        'Lecture task-created flag updated successfully.',
      );
    } else {
      _log(
        'No task occurrences were generated.',
      );

      _log(
        'lecture_task_created remains 0.',
      );
    }

// -------------------------------------------------------------------------
// COMPLETE
// -------------------------------------------------------------------------

    _section(
      'LECTURE TASK GENERATION COMPLETED',
    );

    _log(
      'lectureId=$cleanLectureId',
    );

    _log(
      'tasksCreated=${createdTaskIds.length}',
    );

    for (final taskId in createdTaskIds) {
      _log(
        'Generated TaskID=$taskId',
      );
    }

    return LectureTaskGenerationResult(
      lectureId: cleanLectureId,
      success: true,
      tasksCreated: createdTaskIds.length,
      taskIds: createdTaskIds,
      alreadyGenerated: false,
      message: createdTaskIds.isEmpty
          ? 'Lecture saved. No tasks generated.'
          : 'Lecture saved and '
              '${createdTaskIds.length} task(s) generated.',
    );
  }

// ===========================================================================
// LECTURE
// ===========================================================================

  Future<Map<String, Object?>?> _getLecture(
    String lectureId,
  ) async {
    _log(
      '_getLecture(): querying db_LectureLog...',
    );

    final rows = await _db.query(
      _lectureLogTable,
      where: 'lecture_id = ?',
      whereArgs: [lectureId],
      limit: 1,
    );

    _log(
      '_getLecture(): rows=${rows.length}',
    );

    return rows.isEmpty ? null : rows.first;
  }

// ===========================================================================
// RULES
// ===========================================================================

  Future<List<Map<String, Object?>>> _getMatchingRules({
    required String triggerCode,
    required String subjectCode,
  }) async {
    _log(
      '_getMatchingRules(): START',
    );

    _log(
      'Querying active rules with '
      'TriggerCode=$triggerCode',
    );

    final rows = await _db.query(
      _ruleTable,
      where: 'IsActive = ? AND TriggerCode = ?',
      whereArgs: [
        'Yes',
        triggerCode,
      ],
      orderBy: 'RuleID ASC',
    );

    _log(
      '_getMatchingRules(): '
      'database returned ${rows.length} rules.',
    );

    final result = <Map<String, Object?>>[];

    final normalizedSubject = _normalizeSubjectCode(
      subjectCode,
    );

    _log(
      'Normalized subject=$normalizedSubject',
    );

    for (final row in rows) {
      final subjectTaskId = _string(
        row['RuleSubjectTaskID'],
      );

      _log(
        'Checking RuleSubjectTaskID=$subjectTaskId',
      );

      if (subjectTaskId == null) {
        _log(
          'Skipping rule because '
          'RuleSubjectTaskID is null.',
        );

        continue;
      }

      final matches = _subjectTaskBelongsToSubject(
        subjectTaskId,
        normalizedSubject,
      );

      _log(
        'Subject match=$matches',
      );

      if (matches) {
        result.add(row);

        _log(
          'RULE ACCEPTED: $subjectTaskId',
        );
      } else {
        _log(
          'RULE REJECTED: $subjectTaskId',
        );
      }
    }

    _log(
      '_getMatchingRules(): '
      'final matching count=${result.length}',
    );

    return result;
  }

// ===========================================================================
// SUBJECT TASK
// ===========================================================================

  Future<Map<String, Object?>?> _getActiveSubjectTask(
    String subjectTaskId,
  ) async {
    _log(
      '_getActiveSubjectTask(): '
      'SubjectTaskID=$subjectTaskId',
    );

    final rows = await _db.query(
      _subjectTaskTable,
      where: 'SubjectTaskID = ? '
          'AND SubjectTaskIsActive = ?',
      whereArgs: [
        subjectTaskId,
        'Yes',
      ],
      limit: 1,
    );

    _log(
      '_getActiveSubjectTask(): '
      'rows=${rows.length}',
    );

    return rows.isEmpty ? null : rows.first;
  }

// ===========================================================================
// ACTIVITIES
// ===========================================================================

  Future<List<Map<String, Object?>>> _getActivitiesForSubjectTask(
    String subjectTaskId,
  ) async {
    _log(
      '_getActivitiesForSubjectTask(): START',
    );

    _log(
      'Querying db_SubjectTaskActivities '
      'for SubjectTaskID=$subjectTaskId',
    );

    final links = await _db.query(
      _subjectTaskActivityTable,
      where: 'SubjectTaskID = ?',
      whereArgs: [subjectTaskId],
      orderBy: 'ActivitySequence ASC',
    );

    _log(
      'SubjectTaskActivity links=${links.length}',
    );

    final result = <Map<String, Object?>>[];

    for (final link in links) {
      final activityId = _string(link['ActivityID']);

      _log(
        'Activity link: ActivityID=$activityId',
      );

      if (activityId == null) {
        _log(
          'Skipping activity link with null ActivityID.',
        );

        continue;
      }

      _log(
        'Querying db_Activities '
        'for ActivityID=$activityId',
      );

      final activityRows = await _db.query(
        _activityTable,
        where: 'ActivityID = ? AND IsActive = ?',
        whereArgs: [
          activityId,
          'Yes',
        ],
        limit: 1,
      );

      _log(
        'Activity rows=${activityRows.length}',
      );

      if (activityRows.isEmpty) {
        _log(
          'WARNING: Activity not found or inactive: '
          '$activityId',
        );

        continue;
      }

      final merged = <String, Object?>{
        ...link,
        ...activityRows.first,
      };

      result.add(merged);

      _log(
        'Activity resolved successfully: '
        '$activityId',
      );
    }

    _log(
      '_getActivitiesForSubjectTask(): '
      'resolved=${result.length}',
    );

    return result;
  }

// ===========================================================================
// INSERT TASK
// ===========================================================================

  Future<bool> _createTaskIfAbsent(
    _TaskOccurrence occurrence,
  ) async {
    _log(
      '_createTaskIfAbsent(): '
      'checking TaskID=${occurrence.taskId}',
    );

    final existing = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [occurrence.taskId],
      limit: 1,
    );

    _log(
      '_createTaskIfAbsent(): '
      'existing rows=${existing.length}',
    );

    if (existing.isNotEmpty) {
      return false;
    }

    _log(
      'INSERTING into $_taskLogTable...',
    );

    final row = <String, Object?>{
      'TaskID': occurrence.taskId,
      'TaskDescription': occurrence.taskDescription,
      'TaskDueDate': _formatDate(
        occurrence.taskDueDate,
      ),
      'TaskStartTime': null,
      'TaskDurationMinutes': occurrence.taskDurationMinutes,
      'TaskCalendarEventID': null,
      'TaskReminderMinutes': null,
      'TaskStatus': 'PENDING',
    };

    row.forEach((key, value) {
      _log(
        '  $key = $value',
      );
    });

    final insertedId = await _db.insert(
      _taskLogTable,
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    _log(
      'INSERT completed. '
      'returned rowId=$insertedId',
    );

    return true;
  }

// ===========================================================================
// UPDATE LECTURE FLAG
// ===========================================================================

  Future<void> _markLectureTasksCreated(
    String lectureId,
  ) async {
    _log(
      '_markLectureTasksCreated(): START',
    );

    final updateCount = await _db.update(
      _lectureLogTable,
      <String, Object?>{
        'lecture_task_created': 1,
      },
      where: 'lecture_id = ?',
      whereArgs: [lectureId],
    );

    _log(
      '_markLectureTasksCreated(): '
      'updateCount=$updateCount',
    );

    if (updateCount != 1) {
      throw StateError(
        'Unable to update lecture_task_created '
        'for lecture: $lectureId',
      );
    }

    _log(
      '_markLectureTasksCreated(): SUCCESS',
    );
  }

// ===========================================================================
// EXISTING TASKS
// ===========================================================================

  Future<List<String>> _getLectureTaskIds(
    String lectureId,
  ) async {
    _log(
      '_getLectureTaskIds(): '
      'lectureId=$lectureId',
    );

    final pattern = 'WD_${lectureId}_%';

    final rows = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID LIKE ?',
      whereArgs: [pattern],
      orderBy: 'TaskID ASC',
    );

    _log(
      '_getLectureTaskIds(): '
      'found ${rows.length} tasks.',
    );

    return rows
        .map(
          (row) => _string(row['TaskID']),
        )
        .whereType<String>()
        .toList();
  }

// ===========================================================================
// DESCRIPTION
// ===========================================================================

  String _buildTaskDescription({
    required String subjectName,
    required String chapterName,
    required String topicName,
    required String subjectTaskName,
    required List<Map<String, Object?>> activities,
  }) {
    final buffer = StringBuffer();

    buffer.writeln(
      'Subject - $subjectName',
    );

    buffer.writeln(
      'Chapter - $chapterName',
    );

    if (subjectTaskName.trim().isNotEmpty) {
      buffer.writeln(
        'Task Type - $subjectTaskName',
      );
    }

    for (var i = 0; i < activities.length; i++) {
      final activity = activities[i];

      final sequence = _int(
            activity['ActivitySequence'],
          ) ??
          (i + 1);

      final activityName = _string(
            activity['ActivityDisplayName'],
          ) ??
          _string(
            activity['ActivityDescription'],
          ) ??
          _string(
            activity['ActivityName'],
          ) ??
          _string(
            activity['ActivityID'],
          ) ??
          'Activity';

      final prefix = i == 0 ? 'ToDo    - ' : '        - ';

      buffer.write(prefix);
      buffer.write('$sequence. ');
      buffer.write(topicName);
      buffer.write(' - ');
      buffer.writeln(
        activityName,
      );
    }

    return buffer.toString().trimRight();
  }

// ===========================================================================
// TASK DURATION
// ===========================================================================

  int _taskDuration({
    required Map<String, Object?> subjectTask,
    required List<Map<String, Object?>> activities,
  }) {
    final configured = _int(
      subjectTask['SubjectTaskDurationMinutes'],
    );

    if (configured != null) {
      _log(
        'Using SubjectTask configured '
        'duration=$configured minutes',
      );

      return configured;
    }

    final duration = activities.fold<int>(
      0,
      (sum, row) =>
          sum +
          (_int(
                row['ActivityDurationMinutes'],
              ) ??
              0),
    );

    _log(
      'Calculated activity duration='
      '$duration minutes',
    );

    return duration;
  }

// ===========================================================================
// SUBJECT MATCHING
// ===========================================================================

  bool _subjectTaskBelongsToSubject(
    String subjectTaskId,
    String subjectCode,
  ) {
    final task = subjectTaskId.trim().toUpperCase();

    final subject = subjectCode.trim().toUpperCase();

    return task == subject ||
        task.startsWith(
          '${subject}_',
        );
  }

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
        return 'CHE';

      case 'BIOLOGY':
      case 'BIO':
        return 'BIO';

      default:
        return code;
    }
  }

// ===========================================================================
// TASK ID
// ===========================================================================

  String _buildTaskId({
    required String lectureId,
    required String subjectTaskId,
    required int dayOffset,
  }) {
    final taskId = 'WD_${lectureId}_'
        '${subjectTaskId}_'
        'D$dayOffset';

    _log(
      '_buildTaskId(): $taskId',
    );

    return taskId;
  }

// ===========================================================================
// GENERIC HELPERS
// ===========================================================================

  static String? _string(
    Object? value,
  ) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
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
}

// ============================================================================
// LECTURE ID
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
    final parsed = _parseLectureDate(
      lectureDate,
    );

    if (parsed == null) {
      throw FormatException(
        'Invalid lecture date: $lectureId',
      );
    }

    return parsed;
  }

  static LectureIdParts parse(
    String lectureId,
  ) {
    final raw = lectureId.trim();

    final parts = raw
        .split('-')
        .where(
          (e) => e.trim().isNotEmpty,
        )
        .map(
          (e) => e.trim(),
        )
        .toList();

    if (parts.length != 5) {
      throw FormatException(
        'Unable to parse LectureID "$lectureId". '
        'Expected: '
        'Subject-Chapter-Topic-LNN-YYYYMMDD',
      );
    }

    final subjectCode = parts[0];

    final chapterCode = parts[1];

    final topicCode = parts[2];

    final lectureNumber = parts[3];

    final lectureDate = parts[4];

    if (!RegExp(
      r'^L\d+$',
    ).hasMatch(
      lectureNumber.toUpperCase(),
    )) {
      throw FormatException(
        'Invalid lecture number: $lectureId',
      );
    }

    if (!RegExp(
      r'^\d{8}$',
    ).hasMatch(
      lectureDate,
    )) {
      throw FormatException(
        'Invalid lecture date: $lectureId',
      );
    }

    if (_parseLectureDate(
          lectureDate,
        ) ==
        null) {
      throw FormatException(
        'Invalid calendar date: $lectureId',
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

  static DateTime? _parseLectureDate(
    String value,
  ) {
    if (!RegExp(
      r'^\d{8}$',
    ).hasMatch(value)) {
      return null;
    }

    final year = int.tryParse(
      value.substring(0, 4),
    );

    final month = int.tryParse(
      value.substring(4, 6),
    );

    final day = int.tryParse(
      value.substring(6, 8),
    );

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
// RESULT
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
