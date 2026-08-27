import 'package:flutter/material.dart';

enum TaskStatus { pending, started, completed, cancelledNotRequired }

class Task {
  final String id;
  final String title;
  final String subject;
  final DateTime dueDate;
  final TaskStatus status;

  Task({
    required this.id,
    required this.title,
    required this.subject,
    required this.dueDate,
    required TaskStatus status,
  }) : status = _normaliseStatus(dueDate, status);

  static TaskStatus _normaliseStatus(DateTime dueDate, TaskStatus status) {
    final today = DateUtils.dateOnly(DateTime.now());
    final dueDay = DateUtils.dateOnly(dueDate);

    // A future-dated task must always remain Pending.
    if (dueDay.isAfter(today)) {
      return TaskStatus.pending;
    }

    return status;
  }

  bool get isClosed =>
      status == TaskStatus.completed ||
      status == TaskStatus.cancelledNotRequired;

  bool get statusChangeUnlocked {
    final today = DateUtils.dateOnly(DateTime.now());
    final dueDay = DateUtils.dateOnly(dueDate);
    return !dueDay.isAfter(today);
  }

  bool canTransitionTo(TaskStatus nextStatus) {
    if (nextStatus == status || isClosed) {
      return false;
    }

    if (!statusChangeUnlocked) {
      return false;
    }

    switch (status) {
      case TaskStatus.pending:
        return nextStatus == TaskStatus.started ||
            nextStatus == TaskStatus.completed ||
            nextStatus == TaskStatus.cancelledNotRequired;
      case TaskStatus.started:
        return nextStatus == TaskStatus.completed ||
            nextStatus == TaskStatus.cancelledNotRequired;
      case TaskStatus.completed:
      case TaskStatus.cancelledNotRequired:
        return false;
    }
  }

  Task copyWith({TaskStatus? status}) {
    return Task(
      id: id,
      title: title,
      subject: subject,
      dueDate: dueDate,
      status: status ?? this.status,
    );
  }

  String get statusLabel {
    switch (status) {
      case TaskStatus.pending:
        return 'Pending';
      case TaskStatus.started:
        return 'Started';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.cancelledNotRequired:
        return 'Cancelled / Not Required';
    }
  }
}
