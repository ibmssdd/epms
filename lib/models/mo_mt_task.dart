import 'package:flutter/material.dart';

enum MtTaskStatus {
  pending,
  started,
  completed,
  cancelledNotRequired,
}

class MtTask {
  final String id;
  final String title;
  final String subject;
  final DateTime dueDate;
  final MtTaskStatus status;

  const MtTask({
    required this.id,
    required this.title,
    required this.subject,
    required this.dueDate,
    required this.status,
  });

  bool get isClosed =>
      status == MtTaskStatus.completed ||
      status == MtTaskStatus.cancelledNotRequired;

  bool get isFuture {
    final today = DateUtils.dateOnly(DateTime.now());
    final dueDay = DateUtils.dateOnly(dueDate);
    return dueDay.isAfter(today);
  }

  bool get isDue => !isFuture;

  bool canTransitionTo(MtTaskStatus nextStatus) {
    if (nextStatus == status || isClosed) {
      return false;
    }

    switch (status) {
      case MtTaskStatus.pending:
        return nextStatus == MtTaskStatus.started ||
            nextStatus == MtTaskStatus.completed ||
            nextStatus == MtTaskStatus.cancelledNotRequired;

      case MtTaskStatus.started:
        return nextStatus == MtTaskStatus.completed ||
            nextStatus == MtTaskStatus.cancelledNotRequired;

      case MtTaskStatus.completed:
      case MtTaskStatus.cancelledNotRequired:
        return false;
    }
  }

  MtTask copyWith({
    MtTaskStatus? status,
  }) {
    return MtTask(
      id: id,
      title: title,
      subject: subject,
      dueDate: dueDate,
      status: status ?? this.status,
    );
  }

  String get statusLabel {
    switch (status) {
      case MtTaskStatus.pending:
        return 'Pending';

      case MtTaskStatus.started:
        return 'Started';

      case MtTaskStatus.completed:
        return 'Completed';

      case MtTaskStatus.cancelledNotRequired:
        return 'Cancelled / Not Required';
    }
  }
}
