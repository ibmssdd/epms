import 'dart:convert';

class TaskActivityStatus {
  const TaskActivityStatus({
    required this.taskId,
    required this.activityStatus,
    this.updatedDate,
  });

  final String taskId;

  /// ActivityCode -> completed/not-completed
  ///
  /// Example:
  /// {
  ///   'SCN': true,
  ///   'URN': false,
  ///   'DPP': true,
  /// }
  final Map<String, bool> activityStatus;

  final DateTime? updatedDate;

  bool isCompleted(String activityCode) {
    return activityStatus[activityCode] ?? false;
  }

  TaskActivityStatus copyWith({
    Map<String, bool>? activityStatus,
    DateTime? updatedDate,
  }) {
    return TaskActivityStatus(
      taskId: taskId,
      activityStatus:
          activityStatus ?? Map<String, bool>.from(this.activityStatus),
      updatedDate: updatedDate ?? this.updatedDate,
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'TaskID': taskId,
      'ActivityStatusJSON': jsonEncode(activityStatus),
      'TaskActivityUpdatedDate': updatedDate?.toIso8601String(),
    };
  }

  factory TaskActivityStatus.fromDatabaseRow(Map<String, Object?> row) {
    final taskId = row['TaskID']?.toString().trim() ?? '';

    final jsonText = row['ActivityStatusJSON']?.toString() ?? '{}';

    final decoded = jsonDecode(jsonText);

    final status = <String, bool>{};

    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final code = entry.key.toString();

        final value = entry.value;

        if (value is bool) {
          status[code] = value;
        } else if (value is num) {
          status[code] = value != 0;
        } else if (value is String) {
          status[code] = value.toLowerCase() == 'true' || value == '1';
        }
      }
    }

    return TaskActivityStatus(
      taskId: taskId,
      activityStatus: status,
      updatedDate: DateTime.tryParse(
        row['TaskActivityUpdatedDate']?.toString() ?? '',
      ),
    );
  }
}
