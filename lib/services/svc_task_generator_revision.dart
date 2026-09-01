import 'package:sqflite/sqflite.dart';

/// EPMS Daily Revision Task Generator.
///
/// Responsibilities:
/// - Generates daily revision task occurrences for today's weekday.
/// - Processes all currently InProgress topics for eligible subjects.
/// - Uses db_TaskCreationRuleWeekDay for scheduling.
/// - Uses db_SubjectTasks / db_SubjectTaskActivities / db_Activities
///   to determine task activities.
/// - Creates one db_TaskLogWeekDay row per Topic + SubjectTask + DueDate.
/// - Provides read methods for the Tasks > Generate Tasks workspace.
///
/// This service does NOT:
/// - create or modify the database;
/// - create calendar events;
/// - update Google Calendar;
/// - manage task activity completion state.
///
/// Task activity completion is handled by TaskActivityStatusSvc.
class RevisionTaskGeneratorSvc {
  // RevisionTaskGeneratorSvc({required this._db, DateTime Function()? now})
  //     : _now = now ?? DateTime.now;

  RevisionTaskGeneratorSvc({
    required Database db,
    DateTime Function()? now,
  })  : _db = db,
        _now = now ?? DateTime.now;
  final Database _db;
  final DateTime Function() _now;

  static const String _triggerCode = 'DAILY_CURRENT_TOPIC';

  static const String _triggerCondition = 'CURRENT_TOPIC_ACTIVE_NOT_COMPLETED';

  // ===========================================================================
  // GENERATION - PUBLIC
  // ===========================================================================

  /// Generate revision tasks and return all existing REV_* task rows.
  ///
  /// The generator itself is idempotent. Existing task IDs are not inserted
  /// again.
  Future<List<Map<String, Object?>>> generateRevisionTaskRows() async {
    await generateRevisionTasks();

    final rows = await _db.query(
      'db_TaskLogWeekDay',
      where: 'TaskID GLOB ?',
      whereArgs: ['REV_*'],
    );

    return _sortRevisionRows(rows);
  }

  /// Generate revision tasks scheduled for today's weekday.
  Future<List<String>> generateRevisionTasks() async {
    final today = _now();

    final weekday = _weekdayCode(today);

    // Rules are filtered by today's weekday first.
    final rules = await _getEligibleRules(weekday);

    final createdTaskIds = <String>[];

    for (final rule in rules) {
      final subjectTaskId = _string(rule['RuleSubjectTaskID']);

      if (subjectTaskId == null) {
        continue;
      }

      final subjectCode = _subjectCodeFromSubjectTaskId(subjectTaskId);

      if (subjectCode == null) {
        continue;
      }

      final inProgressTopics = await _getInProgressTopicsForSubject(
        subjectCode,
      );

      for (final statusTopic in inProgressTopics) {
        final topicId = _string(statusTopic['TopicID']);

        if (topicId == null) {
          continue;
        }

        final syllabus = await _findSyllabusTopic(topicId);

        if (syllabus == null) {
          continue;
        }

        final syllabusSubjectCode = _string(syllabus['subject_code']);

        if (syllabusSubjectCode == null ||
            !_sameSubject(syllabusSubjectCode, subjectCode)) {
          continue;
        }

        final subjectTask = await _findSubjectTask(subjectTaskId);

        if (subjectTask == null) {
          continue;
        }

        final occurrences = await _buildTaskOccurrences(
          syllabus: syllabus,
          subjectTask: subjectTask,
        );

        for (final occurrence in occurrences) {
          if (await _insertTaskIfAbsent(occurrence)) {
            createdTaskIds.add(occurrence.taskId);
          }
        }
      }
    }

    return createdTaskIds;
  }

  // ===========================================================================
  // GENERATE WORKSPACE ENQUIRY
  // ===========================================================================

  /// Returns true when at least one REV_* task was actually created today.
  ///
  /// IMPORTANT:
  /// This checks TaskCreatedDate, not TaskDueDate.
  ///
  /// Therefore a task generated today for tomorrow is still considered part
  /// of today's generation and the Generate button is disabled.
  Future<bool> hasGeneratedRevisionTasksToday({DateTime? date}) async {
    final day = _formatDate(_dateOnly(date ?? _now()));

    final rows = await _db.query(
      'db_TaskLogWeekDay',
      columns: const ['TaskID'],
      where: '''
        TaskID GLOB ?
        AND date(TaskCreatedDate) = date(?)
      ''',
      whereArgs: ['REV_*', day],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  /// Returns revision tasks whose TaskCreatedDate is today.
  ///
  /// These are the rows shown under:
  ///
  /// Today's Tasks
  Future<List<Map<String, Object?>>> getTodaysGeneratedRevisionTasks({
    DateTime? date,
  }) async {
    final day = _formatDate(_dateOnly(date ?? _now()));

    final rows = await _db.query(
      'db_TaskLogWeekDay',
      where: '''
        TaskID GLOB ?
        AND date(TaskCreatedDate) = date(?)
      ''',
      whereArgs: ['REV_*', day],
    );

    return _sortRevisionRows(rows);
  }

  /// Returns revision tasks created before today.
  ///
  /// These are shown under:
  ///
  /// Previously Generated Revision Tasks
  ///
  /// Future-dated rows are intentionally included.
  Future<List<Map<String, Object?>>> getPreviouslyGeneratedRevisionTasks({
    DateTime? date,
  }) async {
    final day = _formatDate(_dateOnly(date ?? _now()));

    final rows = await _db.query(
      'db_TaskLogWeekDay',
      where: '''
        TaskID GLOB ?
        AND date(TaskCreatedDate) < date(?)
      ''',
      whereArgs: ['REV_*', day],
    );

    return _sortRevisionRows(rows);
  }

  /// Returns the complete state required by the Generate Tasks tab.
  ///
  /// generatedToday:
  ///   true  -> Generate button disabled
  ///   false -> Generate button enabled
  ///
  /// todaysTasks:
  ///   only rows actually created today
  ///
  /// previousTasks:
  ///   all REV_* rows created before today
  Future<RevisionTaskGenerationView> getRevisionTaskGenerationView({
    DateTime? date,
  }) async {
    final requestedDate = date ?? _now();

    final generatedToday = await hasGeneratedRevisionTasksToday(
      date: requestedDate,
    );

    final todaysTasks = generatedToday
        ? await getTodaysGeneratedRevisionTasks(date: requestedDate)
        : const <Map<String, Object?>>[];

    final previousTasks = await getPreviouslyGeneratedRevisionTasks(
      date: requestedDate,
    );

    return RevisionTaskGenerationView(
      generatedToday: generatedToday,
      todaysTasks: todaysTasks,
      previousTasks: previousTasks,
    );
  }

  // ===========================================================================
  // RULE LOOKUP
  // ===========================================================================

  Future<List<Map<String, Object?>>> _getEligibleRules(
    String todayWeekday,
  ) async {
    final rows = await _db.query(
      'db_TaskCreationRuleWeekDay',
      where: 'IsActive = ? AND TriggerCode = ?',
      whereArgs: ['Yes', _triggerCode],
    );

    return rows.where((row) {
      final condition = _string(row['TriggerCondition']);

      if (condition != _triggerCondition) {
        return false;
      }

      final triggerDay = _string(row['TriggerDay']);

      return _triggerDayContains(triggerDay, todayWeekday);
    }).toList();
  }

  bool _triggerDayContains(String? triggerDay, String todayWeekday) {
    if (triggerDay == null || triggerDay.trim().isEmpty) {
      return false;
    }

    final normalizedToday = todayWeekday.trim().toUpperCase();

    final days = triggerDay
        .split(',')
        .map((day) => day.trim().toUpperCase())
        .where((day) => day.isNotEmpty)
        .toSet();

    return days.contains(normalizedToday);
  }

  // ===========================================================================
  // STATUS TOPIC LOOKUP
  // ===========================================================================

  /// Gets all currently InProgress topics for a subject.
  ///
  /// db_StatusTopics stores TopicID, therefore the subject is resolved
  /// through db_SyllabusMaster.
  Future<List<Map<String, Object?>>> _getInProgressTopicsForSubject(
    String subjectCode,
  ) async {
    final statusRows = await _db.query(
      'db_StatusTopics',
      where: 'TopicState = ?',
      whereArgs: ['InProgress'],
      orderBy: 'TopicID ASC',
    );

    final result = <Map<String, Object?>>[];

    for (final statusRow in statusRows) {
      final topicId = _string(statusRow['TopicID']);

      if (topicId == null) {
        continue;
      }

      final syllabus = await _findSyllabusTopic(topicId);

      if (syllabus == null) {
        continue;
      }

      final topicSubjectCode = _string(syllabus['subject_code']);

      if (topicSubjectCode == null) {
        continue;
      }

      if (_sameSubject(topicSubjectCode, subjectCode)) {
        result.add(statusRow);
      }
    }

    return result;
  }

  // ===========================================================================
  // SYLLABUS LOOKUP
  // ===========================================================================

  Future<Map<String, Object?>?> _findSyllabusTopic(String topicId) async {
    final rows = await _db.query(
      'db_SyllabusMaster',
      where: 'topic_id = ?',
      whereArgs: [topicId],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  // ===========================================================================
  // SUBJECT TASK LOOKUP
  // ===========================================================================

  Future<Map<String, Object?>?> _findSubjectTask(String subjectTaskId) async {
    final rows = await _db.query(
      'db_SubjectTasks',
      where: 'SubjectTaskID = ? AND SubjectTaskIsActive = ?',
      whereArgs: [subjectTaskId, 'Yes'],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  // ===========================================================================
  // BUILD TASK OCCURRENCES
  // ===========================================================================

  Future<List<_RevisionTaskOccurrence>> _buildTaskOccurrences({
    required Map<String, Object?> syllabus,
    required Map<String, Object?> subjectTask,
  }) async {
    final subjectTaskId = _string(subjectTask['SubjectTaskID']);

    final topicId = _string(syllabus['topic_id']);

    final subjectName = _string(syllabus['subject_name']);

    final chapterName = _string(syllabus['chapter_name']);

    final topicName = _string(syllabus['topic_name']);

    if (subjectTaskId == null ||
        topicId == null ||
        subjectName == null ||
        chapterName == null ||
        topicName == null) {
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

      final sequence = _int(row['ActivitySequence']);

      if (activityId == null || sequence == null) {
        continue;
      }

      final activity = await _findActivity(activityId);

      if (activity == null) {
        continue;
      }

      final activityName = _string(activity['ActivityDisplayName']) ??
          _string(activity['ActivityName']) ??
          activityId;

      activities.add(
        _ResolvedActivity(
          activityId: activityId,
          sequence: sequence,
          activityName: activityName,
          durationMinutes: _int(row['ActivityDurationMinutes']) ?? 0,
          dayOffset: _int(row['DayOffset']) ?? 0,
          isMandatory: _toBool(row['IsMandatory']),
        ),
      );
    }

    if (activities.isEmpty) {
      return const [];
    }

    activities.sort((a, b) => a.sequence.compareTo(b.sequence));

    // Activities sharing a DayOffset form one task occurrence.
    final grouped = <int, List<_ResolvedActivity>>{};

    for (final activity in activities) {
      grouped.putIfAbsent(activity.dayOffset, () => []).add(activity);
    }

    final occurrences = <_RevisionTaskOccurrence>[];

    final offsets = grouped.keys.toList()..sort();

    for (final dayOffset in offsets) {
      final group = grouped[dayOffset]!;

      group.sort((a, b) => a.sequence.compareTo(b.sequence));

      final description = _buildTaskDescription(
        subjectName: subjectName,
        chapterName: chapterName,
        topicName: topicName,
        activities: group,
      );

      final duration = group.fold<int>(
        0,
        (total, activity) => total + activity.durationMinutes,
      );

      final dueDate = _dateOnly(_now().add(Duration(days: dayOffset)));

      final dueDateText = _formatDate(dueDate);

      // One occurrence is uniquely identified by:
      // Topic + SubjectTask + DueDate.
      final taskId = 'REV_${topicId}_${subjectTaskId}_$dueDateText';

      occurrences.add(
        _RevisionTaskOccurrence(
          taskId: taskId,
          taskDescription: description,
          taskDueDate: dueDateText,
          taskDurationMinutes: duration,
        ),
      );
    }

    return occurrences;
  }

  // ===========================================================================
  // ACTIVITY LOOKUP
  // ===========================================================================

  Future<Map<String, Object?>?> _findActivity(String activityId) async {
    final rows = await _db.query(
      'db_Activities',
      where: 'ActivityID = ? AND IsActive = ?',
      whereArgs: [activityId, 'Yes'],
      limit: 1,
    );

    return rows.isEmpty ? null : rows.first;
  }

  // ===========================================================================
  // TASK DESCRIPTION
  // ===========================================================================

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

  // ===========================================================================
  // INSERT TASK
  // ===========================================================================

  Future<bool> _insertTaskIfAbsent(_RevisionTaskOccurrence task) async {
    final existing = await _db.query(
      'db_TaskLogWeekDay',
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [task.taskId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return false;
    }

    await _db.insert(
        'db_TaskLogWeekDay',
        {
          'TaskID': task.taskId,
          'TaskDescription': task.taskDescription,
          'TaskDueDate': task.taskDueDate,
          'TaskStartTime': null,
          'TaskDurationMinutes': task.taskDurationMinutes,
          'TaskCalendarEventID': null,
          'TaskReminderMinutes': null,
          'TaskStatus': 'PENDING',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);

    return true;
  }

  // ===========================================================================
  // REVISION TASK SORTING
  // ===========================================================================

  /// Sort order:
  ///
  /// 1. TaskDueDate
  /// 2. Subject
  /// 3. Chapter
  /// 4. Topic
  /// 5. TaskID
  ///
  /// This is used by the Generate Tasks workspace.
  List<Map<String, Object?>> _sortRevisionRows(
    List<Map<String, Object?>> rows,
  ) {
    final result = List<Map<String, Object?>>.from(rows);

    result.sort((a, b) {
      final dueA = _string(a['TaskDueDate']) ?? '';

      final dueB = _string(b['TaskDueDate']) ?? '';

      final dueCompare = dueA.compareTo(dueB);

      if (dueCompare != 0) {
        return dueCompare;
      }

      final keyA = _revisionSortKey(a['TaskID']);

      final keyB = _revisionSortKey(b['TaskID']);

      final subjectCompare = keyA.subject.compareTo(keyB.subject);

      if (subjectCompare != 0) {
        return subjectCompare;
      }

      final chapterCompare = _naturalCodeCompare(keyA.chapter, keyB.chapter);

      if (chapterCompare != 0) {
        return chapterCompare;
      }

      final topicCompare = _naturalCodeCompare(keyA.topic, keyB.topic);

      if (topicCompare != 0) {
        return topicCompare;
      }

      final idA = _string(a['TaskID']) ?? '';

      final idB = _string(b['TaskID']) ?? '';

      return idA.compareTo(idB);
    });

    return result;
  }

  _RevisionSortKey _revisionSortKey(Object? value) {
    final taskId = _string(value) ?? '';

    for (final token in taskId.split('_')) {
      final match = RegExp(
        r'^([A-Za-z]+)-(Ch\d+)-(T\d+)$',
      ).firstMatch(token.trim());

      if (match != null) {
        return _RevisionSortKey(
          subject: match.group(1)!.toUpperCase(),
          chapter: match.group(2)!.toUpperCase(),
          topic: match.group(3)!.toUpperCase(),
        );
      }
    }

    return const _RevisionSortKey(subject: '', chapter: '', topic: '');
  }

  int _naturalCodeCompare(String left, String right) {
    if (left.isEmpty && right.isEmpty) {
      return 0;
    }

    if (left.isEmpty) {
      return -1;
    }

    if (right.isEmpty) {
      return 1;
    }

    final leftMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(left);

    final rightMatch = RegExp(r'([A-Z]+)(\d+)').firstMatch(right);

    if (leftMatch == null || rightMatch == null) {
      return left.compareTo(right);
    }

    final prefixCompare = leftMatch.group(1)!.compareTo(rightMatch.group(1)!);

    if (prefixCompare != 0) {
      return prefixCompare;
    }

    final leftNumber = int.tryParse(leftMatch.group(2)!) ?? 0;

    final rightNumber = int.tryParse(rightMatch.group(2)!) ?? 0;

    return leftNumber.compareTo(rightNumber);
  }

  // ===========================================================================
  // TASK ID / SUBJECT HELPERS
  // ===========================================================================

  /// RuleSubjectTaskID convention:
  ///
  /// PHY_REVISION -> PHY
  /// BIO_REVISION -> BIO
  /// CHE_REVISION -> CHE
  String? _subjectCodeFromSubjectTaskId(String subjectTaskId) {
    final parts = subjectTaskId.trim().split('_');

    if (parts.isEmpty || parts.first.trim().isEmpty) {
      return null;
    }

    return parts.first.trim();
  }

  bool _sameSubject(String left, String right) {
    return left.trim().toUpperCase() == right.trim().toUpperCase();
  }

  // ===========================================================================
  // WEEKDAY
  // ===========================================================================

  String _weekdayCode(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'MON';

      case DateTime.tuesday:
        return 'TUE';

      case DateTime.wednesday:
        return 'WED';

      case DateTime.thursday:
        return 'THU';

      case DateTime.friday:
        return 'FRI';

      case DateTime.saturday:
        return 'SAT';

      case DateTime.sunday:
        return 'SUN';

      default:
        throw StateError('Invalid weekday.');
    }
  }

  // ===========================================================================
  // GENERIC HELPERS
  // ===========================================================================

  static String? _string(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    return text.isEmpty ? null : text;
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

// ============================================================================
// GENERATE WORKSPACE RESULT
// ============================================================================

class RevisionTaskGenerationView {
  const RevisionTaskGenerationView({
    required this.generatedToday,
    required this.todaysTasks,
    required this.previousTasks,
  });

  final bool generatedToday;

  final List<Map<String, Object?>> todaysTasks;

  final List<Map<String, Object?>> previousTasks;
}

// ============================================================================
// INTERNAL ACTIVITY MODEL
// ============================================================================

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

// ============================================================================
// INTERNAL TASK OCCURRENCE
// ============================================================================

class _RevisionTaskOccurrence {
  const _RevisionTaskOccurrence({
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

// ============================================================================
// INTERNAL SORT KEY
// ============================================================================

class _RevisionSortKey {
  const _RevisionSortKey({
    required this.subject,
    required this.chapter,
    required this.topic,
  });

  final String subject;
  final String chapter;
  final String topic;
}
