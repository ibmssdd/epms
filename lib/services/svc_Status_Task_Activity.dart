import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../models/mo_task.dart';

class TaskActivityDefinition {
  const TaskActivityDefinition({
    required this.activityId,
    required this.activityCode,
    required this.activityName,
    required this.sequence,
    required this.isMandatory,
  });

  final String activityId;
  final String activityCode;
  final String activityName;
  final int sequence;
  final bool isMandatory;
}

class TaskActivityCommitResult {
  const TaskActivityCommitResult({
    required this.task,
    required this.activityStatus,
    required this.taskStatusChanged,
  });

  final Task task;
  final Map<String, bool> activityStatus;
  final bool taskStatusChanged;
}

class TaskActivityStatusSvc {
  TaskActivityStatusSvc(this._db);

  final Database _db;

  static const String _activityStatusTable = 'db_TaskActivityStatus';

  // ==========================================================================
  // LOAD ACTIVITY DEFINITIONS FOR A TASK
  // ==========================================================================

  Future<List<TaskActivityDefinition>> getActivitiesForTask(
      String taskId,
      ) async {
    final subjectTaskId = await _findSubjectTaskId(taskId);

    if (subjectTaskId == null) {
      return const [];
    }

    final rows = await _db.rawQuery(
      '''
      SELECT
        sta.ActivityID,
        sta.ActivitySequence,
        sta.IsMandatory,
        a.ActivityCode,
        a.ActivityDisplayName
      FROM db_SubjectTaskActivities sta
      INNER JOIN db_Activities a
        ON a.ActivityID = sta.ActivityID
      WHERE sta.SubjectTaskID = ?
        AND a.IsActive = 'Yes'
      ORDER BY sta.ActivitySequence ASC
      ''',
      [subjectTaskId],
    );

    return rows
        .map((row) {
      return TaskActivityDefinition(
        activityId: row['ActivityID']?.toString() ?? '',
        activityCode: row['ActivityCode']?.toString() ?? '',
        activityName: row['ActivityDisplayName']?.toString() ?? '',
        sequence: _toInt(row['ActivitySequence']) ?? 0,
        isMandatory: _toBool(row['IsMandatory']),
      );
    })
        .where((item) {
      return item.activityCode.isNotEmpty &&
          item.activityName.isNotEmpty &&
          item.sequence > 0;
    })
        .toList();
  }

  // ==========================================================================
  // LOAD SAVED ACTIVITY STATUS
  // ==========================================================================

  Future<Map<String, bool>> loadStatus(String taskId) async {
    final rows = await _db.query(
      _activityStatusTable,
      columns: ['ActivityStatusJSON'],
      where: 'TaskID = ?',
      whereArgs: [taskId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return {};
    }

    return _decodeStatus(rows.first['ActivityStatusJSON']);
  }

  // ==========================================================================
  // COMMIT LOCAL ACTIVITY STATE
  // ==========================================================================

  Future<TaskActivityCommitResult> commitTaskActivities({
    required Task task,
    required Map<String, bool> activityStatus,
  }) async {
    final definitions = await getActivitiesForTask(task.id);

    final normalized = <String, bool>{};

    for (final activity in definitions) {
      normalized[activity.activityCode] =
          activityStatus[activity.activityCode] ?? false;
    }

    final anyCompleted = normalized.values.any((value) => value);

    final requiredActivities = definitions
        .where((activity) => activity.isMandatory)
        .toList();

    final completionActivities = requiredActivities.isNotEmpty
        ? requiredActivities
        : definitions;

    final allRequiredCompleted =
        completionActivities.isNotEmpty &&
            completionActivities.every(
                  (activity) => normalized[activity.activityCode] == true,
            );

    var nextStatus = task.status;

    // ------------------------------------------------------------------------
    // Pending + any activity completed
    // => In Progress
    // ------------------------------------------------------------------------

    if (task.status == TaskStatus.pending && anyCompleted) {
      nextStatus = TaskStatus.started;
    }

    // ------------------------------------------------------------------------
    // All required activities completed
    // => Completed
    // ------------------------------------------------------------------------

    if (allRequiredCompleted) {
      nextStatus = TaskStatus.completed;
    }

    final taskStatusChanged = nextStatus != task.status;

    await _db.transaction((txn) async {
      // ----------------------------------------------------------------------
      // Activity status
      // ----------------------------------------------------------------------

      if (nextStatus == TaskStatus.completed ||
          nextStatus == TaskStatus.cancelledNotRequired) {
        await txn.delete(
          _activityStatusTable,
          where: 'TaskID = ?',
          whereArgs: [task.id],
        );
      } else {
        await txn.insert(
          _activityStatusTable,
          {
            'TaskID': task.id,
            'ActivityStatusJSON': jsonEncode(normalized),
            'TaskActivityUpdatedDate':
            DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // ----------------------------------------------------------------------
      // Task status changed
      //
      // Do NOT determine the table from the TaskID prefix.
      // Find which task-log table actually contains this TaskID.
      // ----------------------------------------------------------------------

      if (taskStatusChanged) {
        String? table;

        // Check WeekDay first.
        final weekDayTask = await txn.query(
          'db_TaskLogWeekDay',
          columns: ['TaskID'],
          where: 'TaskID = ?',
          whereArgs: [task.id],
          limit: 1,
        );

        if (weekDayTask.isNotEmpty) {
          table = 'db_TaskLogWeekDay';
        } else {
          // If not WeekDay, check WeekEnd.
          final weekEndTask = await txn.query(
            'db_TaskLogWeekEnd',
            columns: ['TaskID'],
            where: 'TaskID = ?',
            whereArgs: [task.id],
            limit: 1,
          );

          if (weekEndTask.isNotEmpty) {
            table = 'db_TaskLogWeekEnd';
          }
        }

        // --------------------------------------------------------------------
        // Update the actual table containing the task.
        // --------------------------------------------------------------------

        if (table != null) {
          final values = <String, Object?>{
            'TaskStatus': _taskStatusValue(nextStatus),
          };

          final now = DateTime.now().toIso8601String();

          if (nextStatus == TaskStatus.completed) {
            values['TaskCompletedDate'] = now;
            values['TaskCancelledDate'] = null;
          } else if (nextStatus == TaskStatus.cancelledNotRequired) {
            values['TaskCancelledDate'] = now;
            values['TaskCompletedDate'] = null;
          } else {
            values['TaskCompletedDate'] = null;
            values['TaskCancelledDate'] = null;
          }

          await txn.update(
            table,
            values,
            where: 'TaskID = ?',
            whereArgs: [task.id],
          );
        }
      }
    });

    return TaskActivityCommitResult(
      task: task.copyWith(status: nextStatus),
      activityStatus: normalized,
      taskStatusChanged: taskStatusChanged,
    );
  }
// ==========================================================================
// UPDATE TASK STATUS
//
// Used when TasksScreen changes the task status directly.
// This saves the status to the actual task-log table.
// ==========================================================================

  Future<void> updateTaskStatus(
      String taskId,
      TaskStatus status,
      ) async {
    final now = DateTime.now().toIso8601String();

    final values = <String, Object?>{
      'TaskStatus': _taskStatusValue(status),
    };

    if (status == TaskStatus.completed) {
      values['TaskCompletedDate'] = now;
      values['TaskCancelledDate'] = null;
    } else if (status == TaskStatus.cancelledNotRequired) {
      values['TaskCancelledDate'] = now;
      values['TaskCompletedDate'] = null;
    } else {
      values['TaskCompletedDate'] = null;
      values['TaskCancelledDate'] = null;
    }

    await _db.update(
      'db_TaskLogWeekDay',
      values,
      where: 'TaskID = ?',
      whereArgs: [taskId],
    );
  }
  // ==========================================================================
  // DELETE ACTIVITY STATE
  // ==========================================================================

  Future<void> deleteForTask(String taskId) async {
    await _db.delete(
      _activityStatusTable,
      where: 'TaskID = ?',
      whereArgs: [taskId],
    );
  }

  // ==========================================================================
  // FIND SUBJECT TASK
  // ==========================================================================

  Future<String?> _findSubjectTaskId(String taskId) async {
    final rows = await _db.query(
      'db_SubjectTasks',
      columns: ['SubjectTaskID'],
      where: 'SubjectTaskIsActive = ?',
      whereArgs: ['Yes'],
    );

    final normalizedTaskId = taskId.trim().toUpperCase();

    String? bestMatch;

    for (final row in rows) {
      final subjectTaskId = row['SubjectTaskID']?.toString().trim();

      if (subjectTaskId == null || subjectTaskId.isEmpty) {
        continue;
      }

      final normalizedSubjectTaskId = subjectTaskId.toUpperCase();

      if (!normalizedTaskId.contains(normalizedSubjectTaskId)) {
        continue;
      }

      // Prefer the longest match.
      if (bestMatch == null || subjectTaskId.length > bestMatch.length) {
        bestMatch = subjectTaskId;
      }
    }

    return bestMatch;
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================

  static String _taskStatusValue(TaskStatus status) {
    return switch (status) {
      TaskStatus.pending => 'PENDING',
      TaskStatus.started => 'IN_PROGRESS',
      TaskStatus.completed => 'COMPLETED',
      TaskStatus.cancelledNotRequired => 'CANCELLED / NOT REQUIRED',
    };
  }

  static Map<String, bool> _decodeStatus(Object? value) {
    if (value == null) {
      return {};
    }

    try {
      final decoded = jsonDecode(value.toString());

      if (decoded is! Map) {
        return {};
      }

      final result = <String, bool>{};

      for (final entry in decoded.entries) {
        final key = entry.key.toString();
        final raw = entry.value;

        if (raw is bool) {
          result[key] = raw;
        } else if (raw is num) {
          result[key] = raw != 0;
        } else if (raw is String) {
          final normalized = raw.trim().toLowerCase();

          result[key] =
              normalized == 'true' ||
                  normalized == 'yes' ||
                  normalized == '1';
        }
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  static bool _toBool(Object? value) {
    if (value is bool) {
      return value;
    }

    final normalized = value?.toString().trim().toLowerCase();

    return normalized == 'yes' ||
        normalized == 'true' ||
        normalized == '1';
  }

  static int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }
}