import 'package:sqflite/sqflite.dart';

/// EPMS WeekDay Task Generator
///
/// Scope:
/// - Receives a successful lecture event: LECTURE_RECORDED + LectureID.
/// - Parses the LectureID.
/// - Finds active WeekDay rules for the lecture subject.
/// - Keeps rules whose TriggerCode matches the supplied trigger.
/// - Resolves RuleSubjectTaskID through db_SubjectTasks.
/// - Resolves SubjectTask activities through db_SubjectTaskActivities.
/// - Resolves ActivityID through db_Activities.
/// - Builds one TaskLogWeekDay row per SubjectTask/DayOffset occurrence.
/// - Builds the agreed human-readable TaskDescription.
///
/// This service intentionally does NOT:
/// - modify/open/configure the database;
/// - create calendar events;
/// - update Google Calendar;
/// - introduce new database tables.
///
/// IMPORTANT:
/// The exact persisted LectureID delimiter/format and the exact schema column
/// names for the Subject/Chapter/Topic master tables were not supplied in the
/// final agreed source. Therefore this implementation accepts those lookups
/// through configurable SQL/query callbacks rather than inventing schema names.
class TaskGeneratorSvc {
  TaskGeneratorSvc({required this._db, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;

  /// Generates WeekDay tasks from a successfully recorded lecture.
  ///
  /// [triggerCode] is normally "LECTURE_RECORDED".
  /// [lectureId] is the encoded LectureID supplied by Lecture Service.
  Future<List<String>> generateWeekDayTasks({
    required String triggerCode,
    required String lectureId,
  }) async {
    if (triggerCode.trim().isEmpty) {
      throw ArgumentError.value(triggerCode, 'triggerCode');
    }
    if (lectureId.trim().isEmpty) {
      throw ArgumentError.value(lectureId, 'lectureId');
    }

    final lecture = LectureIdParts.parse(lectureId);

    final rules = await _db.query(
      'db_TaskCreationRuleWeekDay',
      where: 'IsActive = ?',
      whereArgs: ['Yes'],
    );

    final matchingRules = rules.where((row) {
      final subjectTaskId = _string(row['RuleSubjectTaskID']);
      final ruleTrigger = _string(row['TriggerCode']);

      // Subject-specific filtering is done from the RuleSubjectTaskID
      // because the agreed rule table does not contain a SubjectCode column.
      final belongsToSubject = _subjectTaskBelongsToSubject(
        subjectTaskId,
        lecture.subjectCode,
      );

      return belongsToSubject && ruleTrigger == triggerCode;
    }).toList();

    final createdTaskIds = <String>[];

    for (final rule in matchingRules) {
      final subjectTaskId = _string(rule['RuleSubjectTaskID']);
      if (subjectTaskId == null) {
        continue;
      }

      final subjectTask = await _findSubjectTask(subjectTaskId);
      if (subjectTask == null) {
        continue;
      }

      final taskRows = await _buildTaskOccurrences(
        lecture: lecture,
        subjectTask: subjectTask,
      );

      for (final task in taskRows) {
        final inserted = await _insertTaskIfAbsent(task);
        if (inserted) {
          createdTaskIds.add(task.taskId);
        }
      }
    }

    return createdTaskIds;
  }

  Future<Map<String, Object?>?> _findSubjectTask(String subjectTaskId) async {
    final rows = await _db.query(
      'db_SubjectTasks',
      where: 'SubjectTaskID = ?',
      whereArgs: [subjectTaskId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  Future<List<_TaskOccurrence>> _buildTaskOccurrences({
    required LectureIdParts lecture,
    required Map<String, Object?> subjectTask,
  }) async {
    final subjectTaskId = _string(subjectTask['SubjectTaskID']);
    if (subjectTaskId == null) {
      return const [];
    }

    final activityRows = await _db.query(
      'db_SubjectTaskActivities',
      where: 'SubjectTaskID = ?',
      whereArgs: [subjectTaskId],
      orderBy: 'ActivitySequence ASC',
    );

    if (activityRows.isEmpty) {
      return const [];
    }

    final activities = <_ResolvedActivity>[];

    for (final row in activityRows) {
      final activityId = _string(row['ActivityID']);
      if (activityId == null) {
        continue;
      }

      final activity = await _findActivity(activityId);
      if (activity == null) {
        continue;
      }

      final sequence = _int(row['ActivitySequence']) ?? 0;
      final duration = _int(row['ActivityDurationMinutes']) ?? 0;
      final dayOffset = _int(row['DayOffset']) ?? 0;

      activities.add(
        _ResolvedActivity(
          activityId: activityId,
          sequence: sequence,
          activityName:
              _string(activity['ActivityDisplayName']) ??
              _string(activity['ActivityName']) ??
              activityId,
          durationMinutes: duration,
          dayOffset: dayOffset,
          isMandatory: _toBool(row['IsMandatory']),
        ),
      );
    }

    if (activities.isEmpty) {
      return const [];
    }

    activities.sort((a, b) => a.sequence.compareTo(b.sequence));

    final grouped = <int, List<_ResolvedActivity>>{};

    for (final activity in activities) {
      grouped.putIfAbsent(activity.dayOffset, () => []);
      grouped[activity.dayOffset]!.add(activity);
    }

    final subjectName = await _resolveSubjectName(lecture.subjectCode);
    final chapterName = await _resolveChapterName(
      lecture.subjectCode,
      lecture.chapterCode,
    );

    final result = <_TaskOccurrence>[];

    final sortedOffsets = grouped.keys.toList()..sort();

    for (final dayOffset in sortedOffsets) {
      final group = grouped[dayOffset]!
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

      final description = _buildTaskDescription(
        subjectName: subjectName,
        chapterName: chapterName,
        topicName: await _resolveTopicName(
          lecture.subjectCode,
          lecture.chapterCode,
          lecture.topicCode,
        ),
        activities: group,
      );

      final duration = group.fold<int>(
        0,
        (sum, item) => sum + item.durationMinutes,
      );

      final dueDate = _dateOnly(_now().add(Duration(days: dayOffset)));

      result.add(
        _TaskOccurrence(
          taskId: 'WD_${lecture.lectureId}_$subjectTaskId',
          taskDescription: description,
          taskDueDate: _formatDate(dueDate),
          taskDurationMinutes: duration,
        ),
      );
    }

    return result;
  }

  Future<Map<String, Object?>?> _findActivity(String activityId) async {
    final rows = await _db.query(
      'db_Activities',
      where: 'ActivityID = ?',
      whereArgs: [activityId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  String _buildTaskDescription({
    required String subjectName,
    required String chapterName,
    required String topicName,
    required List<_ResolvedActivity> activities,
  }) {
    final buffer = StringBuffer();

    buffer.writeln('Subject - $subjectName');
    buffer.writeln('Chapter - $chapterName');

    for (var i = 0; i < activities.length; i++) {
      final activity = activities[i];
      final prefix = i == 0 ? 'ToDo    - ' : '        - ';

      buffer.write(prefix);
      buffer.write('${activity.sequence}. ');
      buffer.write(topicName);
      buffer.write(' - ');
      buffer.writeln(activity.activityName);
    }

    return buffer.toString().trimRight();
  }

  Future<bool> _insertTaskIfAbsent(_TaskOccurrence task) async {
    final existing = await _db.query(
      'db_TaskLogWeekDay',
      columns: ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [task.taskId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return false;
    }

    await _db.insert('db_TaskLogWeekDay', {
      'TaskID': task.taskId,
      'TaskDescription': task.taskDescription,
      'TaskDueDate': task.taskDueDate,
      'TaskStartTime': null,
      'TaskDurationMinutes': task.taskDurationMinutes,
      'TaskCalendarEventID': null,
      'TaskReminderMinutes': null,
      'TaskStatus': 'PENDING',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    return true;
  }

  /// SubjectCode is not a column in the supplied WeekDay rule schema.
  ///
  /// The current agreed data uses subject-specific RuleSubjectTaskID values
  /// such as PHY_STUDY, BIO_STUDY and CHE_STUDY. This helper therefore uses
  /// the SubjectTaskID prefix as the subject routing key.
  bool _subjectTaskBelongsToSubject(String? subjectTaskId, String subjectCode) {
    if (subjectTaskId == null) {
      return false;
    }

    final normalizedTask = subjectTaskId.trim().toUpperCase();
    final normalizedSubject = subjectCode.trim().toUpperCase();

    return normalizedTask == normalizedSubject ||
        normalizedTask.startsWith('${normalizedSubject}_');
  }

  // ---------------------------------------------------------------------------
  // Subject / Chapter / Topic master lookups
  // ---------------------------------------------------------------------------
  //
  // These three database schemas were not supplied in the agreed WeekDay
  // specification. To avoid inventing table/column names, the default
  // implementation returns the parsed code.
  //
  // Replace these methods with the actual master-table lookups once their
  // schemas are supplied. No other task-generation logic needs to change.

  Future<String> _resolveSubjectName(String subjectCode) async {
    return subjectCode;
  }

  Future<String> _resolveChapterName(
    String subjectCode,
    String chapterCode,
  ) async {
    return chapterCode;
  }

  Future<String> _resolveTopicName(
    String subjectCode,
    String chapterCode,
    String topicCode,
  ) async {
    return topicCode;
  }

  static String? _string(Object? value) {
    if (value == null) {
      return null;
    }
    final valueString = value.toString().trim();
    return valueString.isEmpty ? null : valueString;
  }

  static int? _int(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }

  static bool _toBool(Object? value) {
    if (value is bool) {
      return value;
    }

    final text = value?.toString().trim().toLowerCase();
    return text == 'yes' || text == 'true' || text == '1';
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

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

  /// Expected logical format:
  /// SubjectCode + ChapterCode + TopicCode + LecNNN + LectureDate
  ///
  /// IMPORTANT:
  /// The exact delimiter used by the application's LectureID was not included
  /// in the final supplied schema. This parser therefore supports common
  /// delimiter-separated forms, but should be adjusted to the application's
  /// exact LectureID format before production use.
  static LectureIdParts parse(String lectureId) {
    final raw = lectureId.trim();

    final parts = raw
        .split(RegExp(r'[-_|:]'))
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim())
        .toList();

    if (parts.length >= 5) {
      return LectureIdParts(
        lectureId: raw,
        subjectCode: parts[0],
        chapterCode: parts[1],
        topicCode: parts[2],
        lectureNumber: parts[3],
        lectureDate: parts[4],
      );
    }

    throw FormatException(
      'Unable to parse LectureID "$lectureId". '
      'Expected SubjectCode + ChapterCode + TopicCode + LecNNN + LectureDate.',
    );
  }
}

class _ResolvedActivity {
  const _ResolvedActivity({
    required this.activityId,
    required this.sequence,
    required this.activityName,
    required this.durationMinutes,
    required this.dayOffset,
    required this.isMandatory,
  });

  final String activityId;
  final int sequence;
  final String activityName;
  final int durationMinutes;
  final int dayOffset;
  final bool isMandatory;
}

class _TaskOccurrence {
  const _TaskOccurrence({
    required this.taskId,
    required this.taskDescription,
    required this.taskDueDate,
    required this.taskDurationMinutes,
  });

  final String taskId;
  final String taskDescription;
  final String taskDueDate;
  final int taskDurationMinutes;
}
