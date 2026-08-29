import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart';

/// EPMS Weekend CMT Task Generator.
///
/// Creates CMT weekend tasks immediately after a CMT milestone is saved.
///
/// Source flow:
///   db_Milestones -> db_TaskCreationRuleWeekEnd -> db_SubjectTasks
///   -> db_SubjectTaskActivities -> db_Activities -> db_TaskLogWeekEnd
///
/// The milestone table used here is the current live schema used by
/// MilestoneCalendarSvc: milestone_type, milestone_date,
/// milestone_phy_chapters, milestone_chem_chapters, milestone_bio_chapters.
///
/// No calendar work is performed here.
class CmtWeekendTaskGeneratorSvc {
  CmtWeekendTaskGeneratorSvc({required Database db, DateTime Function()? now})
    : _db = db,
      _now = now ?? DateTime.now;

  final Database _db;
  final DateTime Function() _now;

  static const String _milestoneTable = 'db_Milestones';
  static const String _ruleTable = 'db_TaskCreationRuleWeekEnd';
  static const String _subjectTaskTable = 'db_SubjectTasks';
  static const String _subjectTaskActivityTable = 'db_SubjectTaskActivities';
  static const String _activityTable = 'db_Activities';
  static const String _taskLogTable = 'db_TaskLogWeekEnd';

  static const String _dateColumn = 'milestone_date';
  static const String _typeColumn = 'milestone_type';
  static const String _phyColumn = 'milestone_phy_chapters';
  static const String _chemColumn = 'milestone_chem_chapters';
  static const String _bioColumn = 'milestone_bio_chapters';

  /// Generates all CMT tasks for [milestoneDate].
  ///
  /// This should be called immediately after a CMT milestone save succeeds.
  /// The date must be Sunday and a CMT milestone must exist for that date.
  Future<List<String>> generateCmtTasks({DateTime? milestoneDate}) async {
    final date = _dateOnly(milestoneDate ?? _now());

    debugPrint('========== CMT TASK GENERATION START ==========');
    debugPrint('CMT milestone date: ${_formatDate(date)}');

    if (date.weekday != DateTime.sunday) {
      debugPrint('❌ CMT generation stopped: date is not Sunday.');
      throw ArgumentError(
        'CMT task generation requires a Sunday milestone date.',
      );
    }

    debugPrint('✓ Date is Sunday');

    final milestone = await _getCmtMilestone(date);

    if (milestone == null) {
      debugPrint(
        '❌ No CMT milestone found for ${_formatDate(date)}',
      );
      return const [];
    }

    debugPrint(
      '✓ CMT milestone found for ${_formatDate(date)}',
    );

    debugPrint(
      'Milestone PHY chapters: ${milestone[_phyColumn]}',
    );
    debugPrint(
      'Milestone CHEM chapters: ${milestone[_chemColumn]}',
    );
    debugPrint(
      'Milestone BIO chapters: ${milestone[_bioColumn]}',
    );

    final rules = await _getCmtRules();

    debugPrint(
      'CMT rules found: ${rules.length}',
    );

    for (final rule in rules) {
      debugPrint(
        '  RuleID=${rule['RuleID']} '
            'RuleCode=${rule['RuleCode']} '
            'TriggerDay=${rule['TriggerDay']} '
            'TriggerType=${rule['TriggerType']}',
      );
    }

    if (rules.isEmpty) {
      debugPrint('❌ No active CMT Sunday rules found.');
      return const [];
    }

    final created = <String>[];

    for (final rule in rules) {
      final ruleId = _string(rule['RuleID']);
      final ruleCode = _string(rule['RuleCode']);

      debugPrint(
        '\n--- Processing CMT Rule --- '
            'RuleID=$ruleId RuleCode=$ruleCode',
      );

      if (ruleId == null || ruleCode == null) {
        debugPrint('❌ Rule skipped: missing RuleID or RuleCode.');
        continue;
      }

      final subjectTaskId = ruleCode;

      debugPrint(
        'Looking for active SubjectTask: $subjectTaskId',
      );

      final subjectTask = await _getActiveSubjectTask(subjectTaskId);

      if (subjectTask == null) {
        debugPrint(
          '❌ SubjectTask NOT FOUND or inactive: $subjectTaskId',
        );
        continue;
      }

      debugPrint(
        '✓ SubjectTask found: $subjectTaskId',
      );

      final subjectCode =
      _subjectCodeFromCmtSubjectTask(subjectTaskId);

      debugPrint(
        'Resolved subject code: $subjectCode',
      );

      if (subjectCode == null) {
        debugPrint(
          '❌ Could not determine subject from SubjectTaskID: '
              '$subjectTaskId',
        );
        continue;
      }

      final chapterCodes =
      _milestoneScope(milestone, subjectCode);

      debugPrint(
        'Milestone chapters for $subjectCode: $chapterCodes',
      );

      if (chapterCodes.isEmpty) {
        debugPrint(
          '⚠️ No chapters selected for $subjectCode. '
              'Skipping this subject.',
        );
        continue;
      }

      final chapterNames = <String>[];

      for (final chapterCode in chapterCodes) {
        debugPrint(
          'Looking up syllabus chapter: '
              '$subjectCode / $chapterCode',
        );

        final syllabus =
        await _findChapter(subjectCode, chapterCode);

        final name =
            _string(syllabus?['chapter_name']) ?? chapterCode;

        debugPrint(
          '  Chapter resolved as: $chapterCode - $name',
        );

        chapterNames.add('$chapterCode - $name');
      }

      final activities =
      await _getActiveActivities(subjectTaskId);

      debugPrint(
        'Active activities for $subjectTaskId: '
            '${activities.length}',
      );

      if (activities.isEmpty) {
        debugPrint(
          '❌ No active activities found for $subjectTaskId',
        );
        continue;
      }

      for (final activity in activities) {
        debugPrint(
          '  ActivityID=${activity['ActivityID']} '
              'Sequence=${activity['ActivitySequence']} '
              'Duration=${activity['ActivityDurationMinutes']}',
        );
      }

      final duration =
      _taskDuration(subjectTask, activities);

      final description =
          'Revise Full Syllabus: ${chapterNames.join('; ')}';

      final taskId =
          'WE_${_compactDate(date)}_$ruleId';

      debugPrint('Task ID: $taskId');
      debugPrint('Task description: $description');
      debugPrint('Task duration: $duration minutes');

      final inserted = await _insertIfAbsent(
        taskId: taskId,
        description: description,
        dueDate: date,
        durationMinutes: duration,
      );

      if (inserted) {
        debugPrint('✅ TASK CREATED: $taskId');
        created.add(taskId);
      } else {
        debugPrint(
          'ℹ️ Task already exists or was ignored: $taskId',
        );
      }
    }

    debugPrint(
        '\n========== CMT TASK GENERATION END =========='
    );
    debugPrint(
      'Total tasks created: ${created.length}',
    );
    debugPrint(
      'Created task IDs: $created',
    );

    return created;
  }
  /// Returns all CMT weekend task rows for the milestone date. This is used by
  /// the dashboard/right-panel display after generation so an idempotent
  /// second run still shows the already-existing task rows.
  Future<List<Map<String, Object?>>> getCmtTaskRowsForDate({
    required DateTime milestoneDate,
  }) async {
    final date = _dateOnly(milestoneDate);
    final rules = await _getCmtRules();
    if (rules.isEmpty) return const [];

    final ruleIds = rules
        .map((r) => _string(r['RuleID']))
        .whereType<String>()
        .toList();
    if (ruleIds.isEmpty) return const [];

    final rows = await _db.query(
      _taskLogTable,
      where: 'TaskDueDate = ?',
      whereArgs: [_formatDate(date)],
      orderBy: 'TaskID ASC',
    );

    return rows.where((row) {
      final id = _string(row['TaskID']);
      if (id == null) return false;
      return ruleIds.any((ruleId) => id == 'WE_${_compactDate(date)}_$ruleId');
    }).toList();
  }

  /// Convenience method returning the generated TaskLog rows.
  Future<List<Map<String, Object?>>> generateCmtTaskRows({
    DateTime? milestoneDate,
  }) async {
    final ids = await generateCmtTasks(milestoneDate: milestoneDate);
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

  Future<Map<String, Object?>?> _getCmtMilestone(DateTime date) async {
    final rows = await _db.query(
      _milestoneTable,
      where: '$_typeColumn = ? AND $_dateColumn = ?',
      whereArgs: ['CMT', _formatDate(date)],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }
  Future<List<Map<String, Object?>>> _getCmtRules() async {
    debugPrint('========== CHECKING CMT WEEKEND RULES ==========');

    final rows = await _db.query(
      _ruleTable,
      where: 'IsActive = ?',
      whereArgs: ['Yes'],
      orderBy: 'RuleID ASC',
    );

    debugPrint(
      'Total active weekend rules found: ${rows.length}',
    );

    final result = rows.where((row) {
      final triggerType = _string(row['TriggerType']);
      final ruleCode = _string(row['RuleCode']);

      debugPrint(
        'RULE DB ROW: '
            'RuleID=${row['RuleID']}, '
            'RuleCode=$ruleCode, '
            'TriggerType=$triggerType, '
            'TriggerDay=${row['TriggerDay']}, '
            'TriggerCondition=${row['TriggerCondition']}, '
            'IsActive=${row['IsActive']}',
      );

      final isCmt =
          (triggerType?.trim().toUpperCase() == 'CMT') ||
              (ruleCode?.toUpperCase().contains('_CMT_') ?? false);

      debugPrint(
        '  → isCMT=$isCmt',
      );

      return isCmt;
    }).toList();

    debugPrint(
      'FINAL CMT RULES SELECTED: ${result.length}',
    );

    for (final rule in result) {
      debugPrint(
        '  ✓ Selected Rule: '
            'RuleID=${rule['RuleID']}, '
            'RuleCode=${rule['RuleCode']}',
      );
    }

    debugPrint('================================================');

    return result;
  }
  Future<Map<String, Object?>?> _getActiveSubjectTask(
      String id,
      ) async {
    debugPrint(
      'Checking db_SubjectTasks: '
          'SubjectTaskID=$id, Active=Yes',
    );

    final rows = await _db.query(
      _subjectTaskTable,
      where: 'SubjectTaskID = ? AND SubjectTaskIsActive = ?',
      whereArgs: [id, 'Yes'],
      limit: 1,
    );

    if (rows.isEmpty) {
      debugPrint(
        '❌ No active SubjectTask found for $id',
      );
      return null;
    }

    debugPrint(
      '✓ Active SubjectTask found for $id',
    );

    return rows.first;
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

  List<String> _milestoneScope(
    Map<String, Object?> milestone,
    String subjectCode,
  ) {
    final column = switch (subjectCode) {
      'PHY' => _phyColumn,
      'CHEM' => _chemColumn,
      'BIO' => _bioColumn,
      _ => null,
    };
    if (column == null) return const [];
    return _splitCodes(milestone[column]?.toString());
  }

  String? _subjectCodeFromCmtSubjectTask(String id) {
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

    await _db.insert(_taskLogTable, <String, Object?>{
      'TaskID': taskId,
      'TaskDescription': description,
      'TaskDueDate': _formatDate(dueDate),
      'TaskStartTime': null,
      'TaskDurationMinutes': durationMinutes,
      'TaskCalendarEventID': null,
      'TaskReminderMinutes': null,
      'TaskStatus': 'PENDING',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final verify = await _db.query(
      _taskLogTable,
      columns: const ['TaskID'],
      where: 'TaskID = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    return verify.isNotEmpty;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _formatDate(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  static String _compactDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  static List<String> _splitCodes(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    return value
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
