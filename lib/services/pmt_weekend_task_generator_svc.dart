import 'package:sqflite/sqflite.dart';

/// EPMS Weekend PMT Task Generator.
///
/// PMT scope is calculated at generation time from db_StatusChapters:
///   Chapter = InProgress AND PMT Tested = No.
///
/// The task definition still comes from the same weekend-rule pipeline:
///   db_TaskCreationRuleWeekEnd -> db_SubjectTasks
///   -> db_SubjectTaskActivities -> db_Activities
///   -> db_TaskLogWeekEnd.
///
/// One PMT FCR task is created per qualifying chapter.
/// Calendar integration is outside this service.
class PmtWeekendTaskGeneratorSvc {
  PmtWeekendTaskGeneratorSvc({required Database db, DateTime Function()? now})
      : _db = db,
        _now = now ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;

  static const String _ruleTable = 'db_TaskCreationRuleWeekEnd';
  static const String _subjectTaskTable = 'db_SubjectTasks';
  static const String _subjectTaskActivityTable = 'db_SubjectTaskActivities';
  static const String _activityTable = 'db_Activities';
  static const String _statusChapterTable = 'db_StatusChapters';
  static const String _taskLogTable = 'db_TaskLogWeekEnd';

  /// Live schema names should be these in the current EPMS design.
  /// If the database uses a renamed spelling, the service detects common
  /// alternatives through PRAGMA table_info and fails with a useful message.
  static const List<String> _chapterStateCandidates = <String>[
    'ChapterState',
    'ChapterStatus',
    'Status',
  ];

  static const List<String> _pmtTestedCandidates = <String>[
    'PMTTested',
    'PMT_Tested',
    'PMTTest',
    'PMTTestStatus',
    'PMTTestedStatus',
  ];

  static const List<String> _subjectCandidates = <String>[
    'SubjectCode',
    'subject_code',
  ];

  static const List<String> _chapterCandidates = <String>[
    'ChapterCode',
    'chapter_code',
  ];

  /// Generates PMT tasks for the supplied Sunday.
  ///
  /// The routine may be called manually or by the weekend scheduler. It does
  /// not create its own timer.
  Future<List<String>> generatePmtTasks({DateTime? runDate}) async {
    final date = _dateOnly(runDate ?? _now());
    if (date.weekday != DateTime.sunday) {
      throw ArgumentError('PMT task generation requires a Sunday run date.');
    }

    final rules = await _getPmtRules();
    if (rules.isEmpty) return const [];

    final statusColumns = await _resolveStatusChapterColumns();
    final qualifyingChapters = await _getQualifyingChapters(statusColumns);
    if (qualifyingChapters.isEmpty) return const [];

    final created = <String>[];

    for (final rule in rules) {
      final ruleId = _string(rule['RuleID']);
      final ruleCode = _string(rule['RuleCode']);
      if (ruleId == null || ruleCode == null) continue;

      // The established SubjectTask master uses PHY_PMT_FCR, CHE_PMT_FCR and
      // BIO_PMT_FCR, matching the logical RuleCode.
      final subjectTaskId = ruleCode;
      final subjectTask = await _getActiveSubjectTask(subjectTaskId);
      if (subjectTask == null) continue;

      final subjectCode = _subjectCodeFromPmtSubjectTask(subjectTaskId);
      if (subjectCode == null) continue;

      final activities = await _getActiveActivities(subjectTaskId);
      if (activities.isEmpty) continue;
      final duration = _taskDuration(subjectTask, activities);

      for (final chapter in qualifyingChapters) {
        final chapterSubject = _string(chapter['subjectCode']);
        if (!_sameSubject(chapterSubject, subjectCode)) continue;

        final chapterCode = _string(chapter['chapterCode']);
        if (chapterCode == null) continue;

        final syllabus = await _findChapter(subjectCode, chapterCode);
        final chapterName = _string(syllabus?['chapter_name']) ??
            _string(chapter['chapterName']) ??
            chapterCode;

        final taskId = 'WE_${_compactDate(date)}_${ruleId}_$chapterCode';
        final description = 'Revise Full Chapter: $chapterCode - $chapterName';

        final inserted = await _insertIfAbsent(
          taskId: taskId,
          description: description,
          dueDate: date,
          durationMinutes: duration,
        );
        if (inserted) created.add(taskId);
      }
    }

    return created;
  }

  Future<List<Map<String, Object?>>> generatePmtTaskRows({
    DateTime? runDate,
  }) async {
    final ids = await generatePmtTasks(runDate: runDate);
    if (ids.isEmpty) return const [];

    final rows = <Map<String, Object?>>[];
    for (final id in ids) {
      final found = await _db.query(
        _taskLogTable,
        where: 'TaskID = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (found.isNotEmpty) rows.add(found.first);
    }
    return rows;
  }

  Future<List<Map<String, Object?>>> _getPmtRules() async {
    final rows = await _db.query(
      _ruleTable,
      where: 'IsActive = ?',
      whereArgs: ['Yes'],
      orderBy: 'RuleID ASC',
    );

    return rows.where((row) {
      final triggerDay = _string(row['TriggerDay']);
      final triggerType = _string(row['TriggerType']);
      final ruleCode = _string(row['RuleCode']);

      final sunday = triggerDay
              ?.split(',')
              .map((e) => e.trim().toUpperCase())
              .contains('SUN') ??
          false;

      final isPmt = (triggerType?.toUpperCase() == 'PMT') ||
          (ruleCode?.toUpperCase().contains('_PMT_') ?? false);

      return sunday && isPmt;
    }).toList();
  }

  Future<Map<String, Object?>?> _getActiveSubjectTask(String id) async {
    final rows = await _db.query(
      _subjectTaskTable,
      where: 'SubjectTaskID = ? AND SubjectTaskIsActive = ?',
      whereArgs: [id, 'Yes'],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> _getActiveActivities(
    String subjectTaskId,
  ) async {
    final links = await _db.query(
      _subjectTaskActivityTable,
      where: 'SubjectTaskID = ?',
      whereArgs: [subjectTaskId],
      orderBy: 'ActivitySequence ASC',
    );

    final result = <Map<String, Object?>>[];
    for (final link in links) {
      final activityId = _string(link['ActivityID']);
      if (activityId == null) continue;

      final activity = await _db.query(
        _activityTable,
        where: 'ActivityID = ? AND IsActive = ?',
        whereArgs: [activityId, 'Yes'],
        limit: 1,
      );
      if (activity.isEmpty) continue;

      result.add(<String, Object?>{...link, ...activity.first});
    }
    return result;
  }

  int _taskDuration(
    Map<String, Object?> subjectTask,
    List<Map<String, Object?>> activities,
  ) {
    final configured = _int(subjectTask['SubjectTaskDurationMinutes']);
    if (configured != null) return configured;

    return activities.fold<int>(
      0,
      (sum, row) => sum + (_int(row['ActivityDurationMinutes']) ?? 0),
    );
  }

  Future<Map<String, String>> _resolveStatusChapterColumns() async {
    final rows = await _db.rawQuery('PRAGMA table_info($_statusChapterTable)');
    final actual =
        rows.map((row) => _string(row['name'])).whereType<String>().toList();

    String resolve(List<String> candidates, String purpose) {
      for (final candidate in candidates) {
        final found = actual.where(
          (name) => name.toUpperCase() == candidate.toUpperCase(),
        );
        if (found.isNotEmpty) return found.first;
      }
      throw StateError(
        'db_StatusChapters is missing the $purpose column. '
        'Expected one of: ${candidates.join(', ')}. '
        'Actual columns: ${actual.join(', ')}',
      );
    }

    return <String, String>{
      'state': resolve(_chapterStateCandidates, 'chapter-state'),
      'pmt': resolve(_pmtTestedCandidates, 'PMT-tested'),
      'subject': resolve(_subjectCandidates, 'subject-code'),
      'chapter': resolve(_chapterCandidates, 'chapter-code'),
    };
  }

  Future<List<Map<String, String>>> _getQualifyingChapters(
    Map<String, String> columns,
  ) async {
    final stateColumn = _quoteIdentifier(columns['state']!);
    final pmtColumn = _quoteIdentifier(columns['pmt']!);
    final subjectColumn = _quoteIdentifier(columns['subject']!);
    final chapterColumn = _quoteIdentifier(columns['chapter']!);

    final rows = await _db.rawQuery(
      '''
      SELECT $subjectColumn AS _subject,
             $chapterColumn AS _chapter
      FROM $_statusChapterTable
      WHERE $stateColumn = ?
        AND $pmtColumn = ?
      ORDER BY $subjectColumn ASC, $chapterColumn ASC
    ''',
      const ['InProgress', 'No'],
    );

    return rows
        .map((row) {
          return <String, String>{
            'subjectCode': _string(row['_subject']) ?? '',
            'chapterCode': _string(row['_chapter']) ?? '',
          };
        })
        .where(
          (row) =>
              row['subjectCode']!.isNotEmpty && row['chapterCode']!.isNotEmpty,
        )
        .toList();
  }

  Future<Map<String, Object?>?> _findChapter(
    String subjectCode,
    String chapterCode,
  ) async {
    final aliases = switch (subjectCode) {
      'PHY' => const ['PHY', 'PHYSICS'],
      'CHEM' => const ['CHEM', 'CHEMISTRY', 'BHEM'],
      'BIO' => const ['BIO', 'BIOLOGY'],
      _ => const <String>[],
    };

    for (final alias in aliases) {
      final rows = await _db.query(
        'db_SyllabusMaster',
        where: 'UPPER(subject_code) = ? AND UPPER(chapter_code) = ?',
        whereArgs: [alias, chapterCode.toUpperCase()],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first;
    }
    return null;
  }

  String? _subjectCodeFromPmtSubjectTask(String id) {
    final value = id.toUpperCase();
    if (value.startsWith('PHY_')) return 'PHY';
    if (value.startsWith('CHE_')) return 'CHEM';
    if (value.startsWith('BIO_')) return 'BIO';
    return null;
  }

  Future<bool> _insertIfAbsent({
    required String taskId,
    required String description,
    required DateTime dueDate,
    required int durationMinutes,
  }) async {
    final existing = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;

    await _db.insert(
        _taskLogTable,
        <String, Object?>{
          'TaskID': taskId,
          'TaskDescription': description,
          'TaskDueDate': _formatDate(dueDate),
          'TaskStartTime': null,
          'TaskDurationMinutes': durationMinutes,
          'TaskCalendarEventID': null,
          'TaskReminderMinutes': null,
          'TaskStatus': 'PENDING',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);

    final verify = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    return verify.isNotEmpty;
  }

  static String _quoteIdentifier(String value) =>
      '"${value.replaceAll('"', '""')}"';

  static bool _sameSubject(String? actual, String expected) {
    if (actual == null) return false;
    final a = actual.trim().toUpperCase();
    final e = expected.trim().toUpperCase();
    if (a == e) return true;
    return switch (e) {
      'PHY' => a == 'PHYSICS',
      'CHEM' => a == 'CHEMISTRY' || a == 'BHEM',
      'BIO' => a == 'BIOLOGY',
      _ => false,
    };
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _formatDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  static String _compactDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
