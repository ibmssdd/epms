import 'package:sqflite/sqflite.dart';

/// EPMS task read/query service.
///
/// Reads the two authoritative task-instance logs:
///   - db_TaskLogWeekDay
///   - db_TaskLogWeekEnd
///
/// db_TasksStatus is deliberately not used; it is parked for later.
class TaskEnquirySvc {
  TaskEnquirySvc(this._db);

  final Database _db;

  static int? taskCountStateChecker;
  static int dueTodayCount = 0;
  static int pastDueCount = 0;
  static int inProgressCount = 0;
  static int completedCount = 0;

  static void updateTaskCounters({
    required int dueToday,
    required int pastDue,
    required int inProgress,
    required int completed,
  }) {
    dueTodayCount = dueToday;
    pastDueCount = pastDue;
    inProgressCount = inProgress;
    completedCount = completed;
    taskCountStateChecker = 2;
  }

  static const _weekdayTable = 'db_TaskLogWeekDay';
  static const _weekendTable = 'db_TaskLogWeekEnd';

  Future<List<Map<String, Object?>>> getAllTasks() =>
      _queryBoth(orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC');

  Future<Map<String, Object?>?> getTaskById(String taskId) async {
    final id = taskId.trim();
    if (id.isEmpty) return null;

    for (final table in [_weekdayTable, _weekendTable]) {
      final rows = await _db.query(
        table,
        where: 'TaskID = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first;
    }
    return null;
  }

  // DATE QUERIES -------------------------------------------------------------

  Future<List<Map<String, Object?>>> getTodaysTasks({DateTime? date}) {
    return _queryByDate(date ?? DateTime.now(), operator: '=');
  }

  Future<List<Map<String, Object?>>> getOverdueTasks({DateTime? date}) {
    final value = _formatDate(_dateOnly(date ?? DateTime.now()));
    return _queryBoth(
      where: '''
TaskDueDate < ?
AND UPPER(TaskStatus) NOT IN
('COMPLETED', 'CANCELLED', 'CANCELLED / NOT REQUIRED')
''',
      whereArgs: [value],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  /// Upcoming means TaskDueDate > today.
  Future<List<Map<String, Object?>>> getUpcomingTasks({DateTime? date}) {
    final value = _formatDate(_dateOnly(date ?? DateTime.now()));
    return _queryBoth(
      where: 'TaskDueDate > ?',
      whereArgs: [value],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  Future<List<Map<String, Object?>>> getTasksByDate(DateTime date) {
    return getTodaysTasks(date: date);
  }

  Future<List<Map<String, Object?>>> getTasksByDateRange({
    required DateTime from,
    required DateTime to,
  }) {
    final start = _formatDate(_dateOnly(from));
    final end = _formatDate(_dateOnly(to));

    return _queryBoth(
      where: 'TaskDueDate >= ? AND TaskDueDate <= ?',
      whereArgs: [start, end],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  // STATUS QUERIES -----------------------------------------------------------

  Future<List<Map<String, Object?>>> getOpenTasks() =>
      getTasksByStatus('PENDING');

  Future<List<Map<String, Object?>>> getPendingTasks() =>
      getTasksByStatus('PENDING');

  Future<List<Map<String, Object?>>> getInProgressTasks() =>
      getTasksByStatus('IN_PROGRESS');

  Future<List<Map<String, Object?>>> getCompletedTasks() =>
      getTasksByStatus('COMPLETED');
  // TASK COUNTERS ------------------------------------------------------------

  /// Returns the task counters required by the Dashboard.
  ///
  /// Counters:
  ///   - dueToday
  ///   - pastDue
  ///   - inProgress
  ///   - completed
  ///
  /// The actual task records remain in the two authoritative task-log tables.
  /// This method only returns the counts needed by the UI.
  Future<Map<String, int>> getTaskCounters({DateTime? date}) async {
    final overdueTasks = await getOverdueTasks(date: date);
    final todaysTasks = await getTodaysTasks(date: date);
    final inProgressTasks = await getInProgressTasks();
    final completedTasks = await getCompletedTasks();

    // Today's actionable tasks only.
    final dueToday = todaysTasks.where((task) {
      final status = task['TaskStatus']?.toString().trim().toUpperCase();

      return status != 'COMPLETED' &&
          status != 'CANCELLED' &&
          status != 'CANCELLED / NOT REQUIRED';
    }).length;

    return {
      'dueToday': dueToday,
      'pastDue': overdueTasks.length,
      'inProgress': inProgressTasks.length,
      'completed': completedTasks.length,
    };
  }

  Future<List<Map<String, Object?>>> getTasksByStatus(String status) {
    final value = status.trim().toUpperCase();
    if (value.isEmpty) return Future.value(const []);

    return _queryBoth(
      where: 'UPPER(TaskStatus) = ?',
      whereArgs: [value],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  // SUBJECT / TYPE / ACTIVITY / SCOPE ---------------------------------------

  Future<List<Map<String, Object?>>> getTasksBySubject(String subjectCode) {
    final code = subjectCode.trim().toUpperCase();
    if (code.isEmpty) return Future.value(const []);

    // The finalized task-log schema has no SubjectCode column.
    // Search the encoded TaskID and resolved TaskDescription.
    return _queryBoth(
      where: '''
UPPER(TaskID) LIKE ? OR UPPER(TaskDescription) LIKE ?
''',
      whereArgs: ['%_${code}_%', '%SUBJECT - $code%'],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  /// Convenience search only.
  ///
  /// The finalized schema intentionally has no TaskType column, so this
  /// searches TaskID/TaskDescription rather than inventing a stored field.
  Future<List<Map<String, Object?>>> getTasksByTaskType(String taskType) {
    final value = taskType.trim().toUpperCase();
    if (value.isEmpty) return Future.value(const []);

    return _queryBoth(
      where: '''
UPPER(TaskID) LIKE ? OR UPPER(TaskDescription) LIKE ?
''',
      whereArgs: ['%_$value%', '%$value%'],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  Future<List<Map<String, Object?>>> getTasksByActivity(String activity) {
    final value = activity.trim().toLowerCase();
    if (value.isEmpty) return Future.value(const []);

    return _queryBoth(
      where: 'LOWER(TaskDescription) LIKE ?',
      whereArgs: ['%$value%'],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  Future<List<Map<String, Object?>>> getTasksByActivityName(
    String activityName,
  ) =>
      getTasksByActivity(activityName);

  Future<List<Map<String, Object?>>> getTasksByChapter(String chapter) {
    final value = chapter.trim().toLowerCase();
    if (value.isEmpty) return Future.value(const []);

    return _queryBoth(
      where: 'LOWER(TaskDescription) LIKE ?',
      whereArgs: ['%$value%'],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  Future<List<Map<String, Object?>>> getTasksByTopic(String topic) {
    final value = topic.trim().toLowerCase();
    if (value.isEmpty) return Future.value(const []);

    return _queryBoth(
      where: 'LOWER(TaskDescription) LIKE ?',
      whereArgs: ['%$value%'],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  // COMBINED FILTERS ---------------------------------------------------------

  Future<List<Map<String, Object?>>> getTasksBySubjectAndStatus({
    required String subjectCode,
    required String status,
  }) {
    final subject = subjectCode.trim().toUpperCase();
    final state = status.trim().toUpperCase();
    if (subject.isEmpty || state.isEmpty) return Future.value(const []);

    return _queryBoth(
      where: '''
UPPER(TaskStatus) = ?
AND (UPPER(TaskID) LIKE ? OR UPPER(TaskDescription) LIKE ?)
''',
      whereArgs: [state, '%_${subject}_%', '%SUBJECT - $subject%'],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  Future<List<Map<String, Object?>>> getTasksByTaskTypeAndStatus({
    required String taskType,
    required String status,
  }) {
    final type = taskType.trim().toUpperCase();
    final state = status.trim().toUpperCase();
    if (type.isEmpty || state.isEmpty) return Future.value(const []);

    return _queryBoth(
      where: '''
UPPER(TaskStatus) = ?
AND (UPPER(TaskID) LIKE ? OR UPPER(TaskDescription) LIKE ?)
''',
      whereArgs: [state, '%_$type%', '%$type%'],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  Future<List<Map<String, Object?>>> getTasksByActivityAndStatus({
    required String activity,
    required String status,
  }) {
    final activityText = activity.trim().toLowerCase();
    final state = status.trim().toUpperCase();
    if (activityText.isEmpty || state.isEmpty) return Future.value(const []);

    return _queryBoth(
      where: '''
UPPER(TaskStatus) = ?
AND LOWER(TaskDescription) LIKE ?
''',
      whereArgs: [state, '%$activityText%'],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  // MILESTONES ----------------------------------------------------------------

  Future<List<Map<String, Object?>>> getUpcomingMilestones({DateTime? date}) {
    final value = _formatDate(_dateOnly(date ?? DateTime.now()));

    return _db.query(
      'db_Milestones',
      where: 'MilestoneDate > ?',
      whereArgs: [value],
      orderBy: 'MilestoneDate ASC',
    );
  }

  /// Returns upcoming milestones and tasks due on the milestone date.
  ///
  /// The finalized milestone schema has no direct TaskID/MilestoneID
  /// relationship, so this currently uses date matching.
  Future<List<Map<String, Object?>>> getUpcomingMilestonesWithTasks({
    DateTime? date,
  }) async {
    final milestones = await getUpcomingMilestones(date: date);
    final result = <Map<String, Object?>>[];

    for (final milestone in milestones) {
      final milestoneDate = _string(milestone['MilestoneDate']);
      if (milestoneDate == null) continue;

      final tasks = await _queryBoth(
        where: 'TaskDueDate = ?',
        whereArgs: [milestoneDate],
        orderBy: 'TaskCreatedDate ASC',
      );

      result.add({'milestone': milestone, 'tasks': tasks});
    }

    return result;
  }

  // INTERNAL -----------------------------------------------------------------

  Future<List<Map<String, Object?>>> _queryByDate(
    DateTime date, {
    required String operator,
  }) {
    final value = _formatDate(_dateOnly(date));

    return _queryBoth(
      where: 'TaskDueDate $operator ?',
      whereArgs: [value],
      orderBy: 'TaskDueDate ASC, TaskCreatedDate ASC',
    );
  }

  Future<List<Map<String, Object?>>> _queryBoth({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final weekday = await _db.query(
      _weekdayTable,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );

    final weekend = await _db.query(
      _weekendTable,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );

    final rows = <Map<String, Object?>>[...weekday, ...weekend];

    rows.sort((a, b) {
      final due = _string(
        a['TaskDueDate'],
      ).toString().compareTo(_string(b['TaskDueDate']).toString());
      if (due != 0) return due;

      return _string(
        a['TaskCreatedDate'],
      ).toString().compareTo(_string(b['TaskCreatedDate']).toString());
    });

    return rows;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}
