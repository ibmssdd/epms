import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/mo_mt_task.dart';

/// Activity definition used only by Milestone Tasks.
class MtTaskActivityDefinition {
  const MtTaskActivityDefinition({
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

/// Result returned after committing Milestone Task activity state.
class MtTaskActivityCommitResult {
  const MtTaskActivityCommitResult({
    required this.task,
    required this.activityStatus,
    required this.taskStatusChanged,
  });

  final MtTask task;
  final Map<String, bool> activityStatus;
  final bool taskStatusChanged;
}

/// Activity-status service dedicated to Milestone Tasks.
///
/// This service intentionally uses MtTask / MtTaskStatus and must not be
/// mixed with the normal Task / TaskStatus activity service.
class MtTaskActivityStatusSvc {
  MtTaskActivityStatusSvc(this._db);

  final Database _db;

  static const String _activityStatusTable = 'db_TaskActivityStatus';

// ==========================================================================
// LOAD ACTIVITY DEFINITIONS
// ==========================================================================

  Future<List<MtTaskActivityDefinition>> getActivitiesForTask(
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
        .map(
          (row) => MtTaskActivityDefinition(
            activityId: row['ActivityID']?.toString() ?? '',
            activityCode: row['ActivityCode']?.toString() ?? '',
            activityName: row['ActivityDisplayName']?.toString() ?? '',
            sequence: _toInt(row['ActivitySequence']) ?? 0,
            isMandatory: _toBool(row['IsMandatory']),
          ),
        )
        .where(
          (item) =>
              item.activityCode.isNotEmpty &&
              item.activityName.isNotEmpty &&
              item.sequence > 0,
        )
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
// COMMIT MILESTONE TASK ACTIVITY STATE
//
// IMPORTANT:
//
// MT activity JSON is retained even when an individual MT task becomes
// completed. It is cleared only through clearMilestoneTaskActivities().
//
// FSR tasks use chapter names as ActivityStatusJSON keys.
// Other MT tasks use configured activity codes.
// ==========================================================================

  Future<MtTaskActivityCommitResult> commitMilestoneTaskActivities({
    required MtTask task,
    required Map<String, bool> activityStatus,
  }) async {
    final isFsrTask = task.id.trim().toUpperCase().contains('_FSR');

    Map<String, bool> normalized;

    if (isFsrTask) {
// ----------------------------------------------------------------------
// FSR / SUBJECT SYLLABUS REVISION
//
// FSR ActivityStatusJSON is chapter-based:
//
// {
//   "Evolution": false,
//   "Human Reproduction": true,
//   "Molecular Basis Of Inheritance": false
// }
//
// Preserve the chapter names exactly as supplied by the UI/generator.
// ----------------------------------------------------------------------

      normalized = <String, bool>{};

      for (final entry in activityStatus.entries) {
        final chapterName = entry.key.trim();

        if (chapterName.isEmpty) {
          continue;
        }

        normalized[chapterName] = entry.value;
      }
    } else {
// ----------------------------------------------------------------------
// PCB / OTHER MT TASKS
//
// These use the configured SubjectTask activity definitions.
// ----------------------------------------------------------------------

      final definitions = await getActivitiesForTask(task.id);

      normalized = <String, bool>{};

      for (final activity in definitions) {
        normalized[activity.activityCode] =
            activityStatus[activity.activityCode] ?? false;
      }
    }

// ==========================================================================
// DETERMINE NEXT MT TASK STATUS
// ==========================================================================

    final anyCompleted = normalized.values.any((value) => value);

    final allRequiredCompleted =
        normalized.isNotEmpty && normalized.values.every((value) => value);

    var nextStatus = task.status;

// Pending + at least one completed activity
// => Started.
    if (task.status == MtTaskStatus.pending && anyCompleted) {
      nextStatus = MtTaskStatus.started;
    }

// All activities completed
// => Completed.
    if (allRequiredCompleted) {
      nextStatus = MtTaskStatus.completed;
    }

    final taskStatusChanged = nextStatus != task.status;

// ==========================================================================
// DATABASE TRANSACTION
// ==========================================================================

    await _db.transaction((txn) async {
// ------------------------------------------------------------------------
// ALWAYS retain MT ActivityStatusJSON.
// ------------------------------------------------------------------------

      await txn.insert(
        _activityStatusTable,
        {
          'TaskID': task.id,
          'ActivityStatusJSON': jsonEncode(normalized),
          'TaskActivityUpdatedDate': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

// ------------------------------------------------------------------------
// Update MT task status if required.
//
// MT tasks are stored in db_TaskLogWeekEnd.
// ------------------------------------------------------------------------

      if (taskStatusChanged) {
        final values = <String, Object?>{
          'TaskStatus': _mtTaskStatusValue(nextStatus),
        };

        final now = DateTime.now().toIso8601String();

        if (nextStatus == MtTaskStatus.completed) {
          values['TaskCompletedDate'] = now;
          values['TaskCancelledDate'] = null;
        } else if (nextStatus == MtTaskStatus.cancelledNotRequired) {
          values['TaskCancelledDate'] = now;
          values['TaskCompletedDate'] = null;
        } else {
          values['TaskCompletedDate'] = null;
          values['TaskCancelledDate'] = null;
        }

        await txn.update(
          'db_TaskLogWeekEnd',
          values,
          where: 'TaskID = ?',
          whereArgs: [task.id],
        );
      }
    });

    return MtTaskActivityCommitResult(
      task: task.copyWith(status: nextStatus),
      activityStatus: normalized,
      taskStatusChanged: taskStatusChanged,
    );
  }

// ==========================================================================
// UPDATE MT TASK STATUS DIRECTLY
// ==========================================================================

  Future<void> updateTaskStatus(
    String taskId,
    MtTaskStatus status,
  ) async {
    final values = <String, Object?>{
      'TaskStatus': _mtTaskStatusValue(status),
    };

    final now = DateTime.now().toIso8601String();

    if (status == MtTaskStatus.completed) {
      values['TaskCompletedDate'] = now;
      values['TaskCancelledDate'] = null;
    } else if (status == MtTaskStatus.cancelledNotRequired) {
      values['TaskCancelledDate'] = now;
      values['TaskCompletedDate'] = null;
    } else {
      values['TaskCompletedDate'] = null;
      values['TaskCancelledDate'] = null;
    }

    await _db.update(
      'db_TaskLogWeekEnd',
      values,
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

      if (bestMatch == null || subjectTaskId.length > bestMatch.length) {
        bestMatch = subjectTaskId;
      }
    }

    return bestMatch;
  }

// ==========================================================================
// CLEAR ALL MT ACTIVITY STATE
//
// Use ONLY when the complete MT activity lifecycle has ended, e.g. after
// the final PCB/Common task has been closed.
// ==========================================================================

  Future<void> clearMilestoneTaskActivities() async {
    await _db.delete(
      _activityStatusTable,
      where: 'TaskID LIKE ?',
      whereArgs: ['MT_%'],
    );
  }

// ==========================================================================
// DELETE ACTIVITY STATE FOR ONE MT TASK
//
// Normally NOT used when an individual MT task is completed.
// ==========================================================================

  Future<void> deleteForTask(String taskId) async {
    await _db.delete(
      _activityStatusTable,
      where: 'TaskID = ?',
      whereArgs: [taskId],
    );
  }

// ==========================================================================
// HELPERS
// ==========================================================================

  static String _mtTaskStatusValue(MtTaskStatus status) {
    return switch (status) {
      MtTaskStatus.pending => 'PENDING',
      MtTaskStatus.started => 'IN_PROGRESS',
      MtTaskStatus.completed => 'COMPLETED',
      MtTaskStatus.cancelledNotRequired => 'CANCELLED / NOT REQUIRED',
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
              normalized == 'true' || normalized == 'yes' || normalized == '1';
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

    return normalized == 'yes' || normalized == 'true' || normalized == '1';
  }

  static int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }
}
