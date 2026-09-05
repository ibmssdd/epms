import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../models/mo_mt_task.dart';
import '../services/svc_milestones.dart';

/// Milestone Tasks workspace.
///
/// Hierarchy:
///   Milestone Header
///     -> Task Header
///       -> Subtask rows
///
/// Parent milestone tasks come from db_TaskLogWeekEnd through
/// MilestoneCalendarSvc.getAllOpenMTasks().
///
/// Subtasks come directly from db_SubTasksMT.
///
/// The relationship is:
///
///   db_TaskLogWeekEnd.TaskID = db_SubTasksMT.SubTaskID
///
/// Therefore no TaskID parsing is required to find the subtasks.
///
/// TaskID parsing is only used to identify the subject code when the PCB
/// business rule needs to be applied.
///
/// Subtask status changes are held in memory while the task is being edited.
/// They are committed when:
///   - the task is collapsed,
///   - another task is selected,
///   - the milestone header is collapsed,
///   - or a tap occurs outside the current task editing region.
class MilestonesMtView extends StatefulWidget {
  const MilestonesMtView({
    super.key,
    this.onTaskUpdated,
    this.onTaskStateChanged,
  });

  final ValueChanged<MtTask>? onTaskUpdated;
  final ValueChanged<MtTask>? onTaskStateChanged;

  @override
  State<MilestonesMtView> createState() => _MilestonesMtViewState();
}

class _MilestonesMtViewState extends State<MilestonesMtView> {
  bool _milestoneTasksLoading = false;
  String? _milestoneTasksError;

  List<Map<String, Object?>> _openMilestoneTasks = const [];

  /// Milestone header expansion state.
  ///
  /// Key = YYYY-MM-DD.
  final Map<String, bool> _milestoneTaskExpanded = {};

  /// Temporary parent-task status overrides while the current workspace
  /// is being edited.
  final Map<String, MtTask> _taskOverrides = {};

  /// Only one parent task is expanded at a time.
  String? _expandedTaskId;

  /// Commit callback belonging to the currently expanded task.
  Future<void> Function()? _commitExpandedTask;

  @override
  void initState() {
    super.initState();
    _loadMilestoneTasksView();
  }

  Future<void> _loadMilestoneTasksView() async {
    if (_milestoneTasksLoading || !mounted) {
      return;
    }

    setState(() {
      _milestoneTasksLoading = true;
      _milestoneTasksError = null;
    });

    try {
      final db = await AppDatabase.instance.database;
      final milestoneSvc = MilestoneCalendarSvc(db);

      final rows = await milestoneSvc.getAllOpenMTasks();

      if (!mounted) {
        return;
      }

      setState(() {
        _openMilestoneTasks = rows;
        _milestoneTasksLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _milestoneTasksLoading = false;
        _openMilestoneTasks = const [];
        _milestoneTasksError = 'Unable to load milestone tasks.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadMilestoneTasksView,
      child: _buildMilestoneTasks(context),
    );
  }

  Widget _buildMilestoneTasks(BuildContext context) {
    if (_milestoneTasksLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      );
    }

    if (_milestoneTasksError != null) {
      return ListView(
        padding: const EdgeInsets.all(4),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _milestoneTasksError!,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      );
    }

    final grouped = _groupMilestoneTasksByDate();

    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    if (dates.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(4),
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'No milestone tasks pending or scheduled.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(4),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (var i = 0; i < dates.length; i++) ...[
          _buildMilestoneHeader(
            context,
            dateKey: dates[i],
            rows: grouped[dates[i]]!,
          ),
          if (i < dates.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  // ==========================================================================
  // MILESTONE GROUPING
  // ==========================================================================

  Map<String, List<Map<String, Object?>>> _groupMilestoneTasksByDate() {
    final grouped = <String, List<Map<String, Object?>>>{};

    for (final row in _openMilestoneTasks) {
      final dueText = row['TaskDueDate']?.toString();

      if (dueText == null || dueText.isEmpty) {
        continue;
      }

      final date = DateTime.tryParse(dueText);

      if (date == null) {
        continue;
      }

      final dateKey = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

      grouped.putIfAbsent(dateKey, () => []).add(row);
    }

    return grouped;
  }

  // ==========================================================================
  // MILESTONE HEADER
  // ==========================================================================

  Widget _buildMilestoneHeader(
    BuildContext context, {
    required String dateKey,
    required List<Map<String, Object?>> rows,
  }) {
    final colors = Theme.of(context).colorScheme;

    final date = DateTime.parse(dateKey);

    final expanded = _milestoneTaskExpanded[dateKey] ?? true;

    final milestoneType = rows.isNotEmpty
        ? rows.first['MilestoneType']?.toString().trim().toUpperCase()
        : null;

    final milestoneTitle = switch (milestoneType) {
      'CMT' => 'Coaching Milestone',
      'PMT' => 'Personal Milestone',
      _ => 'Milestone',
    };

    final dateText = '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';

    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              if (expanded && _expandedTaskId != null) {
                final commit = _commitExpandedTask;

                if (commit != null) {
                  await commit();
                }
              }

              if (!mounted) {
                return;
              }

              setState(() {
                _milestoneTaskExpanded[dateKey] = !expanded;

                if (expanded) {
                  _expandedTaskId = null;
                  _commitExpandedTask = null;
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.flag_outlined,
                    size: 19,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '$milestoneTitle — $dateText',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${rows.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 19,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                7,
                0,
                7,
                5,
              ),
              child: Column(
                children: [
                  for (final row in rows)
                    _buildMilestoneTaskFromRow(
                      context,
                      row,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMilestoneTaskFromRow(
    BuildContext context,
    Map<String, Object?> row,
  ) {
    final baseTask = _taskFromMilestoneRow(row);

    if (baseTask == null) {
      return const SizedBox.shrink();
    }

    final task = _taskOverrides[baseTask.id] ?? baseTask;

    return _MilestoneTaskRow(
      key: ValueKey(task.id),
      task: task,
      expanded: _expandedTaskId == task.id,
      onExpand: _expandTask,
      onCollapse: _collapseTask,
      registerCommit: _registerCommit,
      onTaskStatusChanged: _handleTaskStatusChanged,
      onTaskUpdated: _notifyTaskUpdated,
    );
  }

  // ==========================================================================
  // TASK MODEL
  // ==========================================================================

  MtTask? _taskFromMilestoneRow(
    Map<String, Object?> row,
  ) {
    final id = row['TaskID']?.toString().trim();

    final description = row['TaskDescription']?.toString() ?? '';

    final dueText = row['TaskDueDate']?.toString();

    if (id == null || id.isEmpty || dueText == null || dueText.isEmpty) {
      return null;
    }

    final dueDate = DateTime.tryParse(dueText);

    if (dueDate == null) {
      return null;
    }

    final status =
        switch ((row['TaskStatus']?.toString() ?? 'PENDING').toUpperCase()) {
      'IN_PROGRESS' || 'STARTED' => MtTaskStatus.started,
      'COMPLETED' => MtTaskStatus.completed,
      'CANCELLED' ||
      'CANCELLED / NOT REQUIRED' =>
        MtTaskStatus.cancelledNotRequired,
      _ => MtTaskStatus.pending,
    };

    return MtTask(
      id: id,
      title: description,

      // Subject is taken only from the established
      // MT TaskID structure.
      subject: _subjectCodeFromTaskId(id),

      dueDate: dueDate,
      status: status,
    );
  }

  /// Established TaskID format:
  ///
  /// MT_20260906_1_PHY_CMT_FSR
  /// │   │       │ │   │   │
  /// │   │       │ │   │   └─ Task Code - ignored
  /// │   │       │ │   └───── Milestone Type
  /// │   │       │ └───────── Subject Code
  /// │   │       └─────────── Task Creation Rule ID
  /// │   └─────────────────── Milestone Date
  /// └─────────────────────── Milestone record
  ///
  /// Only the Subject Code is required here.
  String _subjectCodeFromTaskId(String taskId) {
    final parts = taskId.split('_');

    if (parts.length > 3) {
      final subject = parts[3].trim().toUpperCase();

      if (subject == 'PHY' ||
          subject == 'CHE' ||
          subject == 'BIO' ||
          subject == 'PCB') {
        return subject;
      }
    }

    return '';
  }

  // ==========================================================================
  // PARENT TASK STATUS
  // ==========================================================================

  bool _isFutureTask(MtTask task) {
    return DateUtils.dateOnly(
      task.dueDate,
    ).isAfter(
      DateUtils.dateOnly(
        DateTime.now(),
      ),
    );
  }

  bool _isDueTask(MtTask task) {
    return !_isFutureTask(task);
  }

  Future<void> _handleTaskStatusChanged(
    MtTask task,
  ) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _taskOverrides[task.id] = task;
    });

    _notifyTaskStateChanged(task);
  }

  // ==========================================================================
  // TASK EXPANSION / COMMIT MANAGEMENT
  // ==========================================================================

  void _registerCommit(
    String taskId,
    Future<void> Function() commit,
  ) {
    if (_expandedTaskId == taskId) {
      _commitExpandedTask = commit;
    }
  }

  Future<void> _expandTask(
    String taskId,
    Future<void> Function() commit,
  ) async {
    if (_expandedTaskId != null && _expandedTaskId != taskId) {
      final oldCommit = _commitExpandedTask;

      if (oldCommit != null) {
        await oldCommit();
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _expandedTaskId = taskId;
      _commitExpandedTask = commit;
    });
  }

  Future<void> _collapseTask(
    String taskId,
  ) async {
    if (_expandedTaskId != taskId) {
      return;
    }

    final commit = _commitExpandedTask;

    if (commit != null) {
      await commit();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _expandedTaskId = null;
      _commitExpandedTask = null;
    });
  }

  void _notifyTaskUpdated(MtTask task) {
    widget.onTaskUpdated?.call(task);
  }

  void _notifyTaskStateChanged(
    MtTask task,
  ) {
    final callback = widget.onTaskStateChanged;

    if (callback != null) {
      callback(task);
    } else {
      widget.onTaskUpdated?.call(task);
    }
  }
}

// =============================================================================
// TASK ROW
// =============================================================================

class _MilestoneTaskRow extends StatefulWidget {
  const _MilestoneTaskRow({
    super.key,
    required this.task,
    required this.expanded,
    required this.onExpand,
    required this.onCollapse,
    required this.registerCommit,
    required this.onTaskStatusChanged,
    required this.onTaskUpdated,
  });

  final MtTask task;
  final bool expanded;

  final Future<void> Function(
    String taskId,
    Future<void> Function() commit,
  ) onExpand;

  final Future<void> Function(
    String taskId,
  ) onCollapse;

  final void Function(
    String taskId,
    Future<void> Function() commit,
  ) registerCommit;

  final Future<void> Function(
    MtTask task,
  ) onTaskStatusChanged;

  final ValueChanged<MtTask> onTaskUpdated;

  @override
  State<_MilestoneTaskRow> createState() => _MilestoneTaskRowState();
}

class _MilestoneTaskRowState extends State<_MilestoneTaskRow> {
  bool _loading = false;
  bool _saving = false;
  bool _dirty = false;

  List<Map<String, Object?>> _subtasks = const [];

  /// Temporary subtask status values.
  ///
  /// Key:
  ///   SubTaskID|SubTaskSubjectCode|SubTaskChapterCode
  ///
  /// This keeps the status of every individual
  /// subtask independently in memory.
  final Map<String, String> _subtaskStatus = {};

  /// Status values loaded from the database.
  final Map<String, String> _originalSubtaskStatus = {};

  @override
  void initState() {
    super.initState();

    if (widget.expanded) {
      _loadSubtasks();
    }
  }

  @override
  void didUpdateWidget(
    covariant _MilestoneTaskRow oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (!oldWidget.expanded && widget.expanded) {
      _loadSubtasks();
    }

    if (widget.expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.expanded) {
          return;
        }

        widget.registerCommit(
          widget.task.id,
          _commitIfDirty,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final closed = widget.task.status == MtTaskStatus.completed ||
        widget.task.status == MtTaskStatus.cancelledNotRequired;

    return TapRegion(
      groupId: widget.task.id,

      // Tapping outside the current task means
      // the current edit context has ended.
      onTapOutside: (_) {
        if (_dirty) {
          _commitIfDirty();
        }
      },

      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        decoration: widget.expanded
            ? BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: colors.primary.withValues(alpha: .75),
                  width: 1.3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: .10),
                    blurRadius: 7,
                  ),
                ],
              )
            : null,
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: _toggleExpanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  12,
                  8,
                  7,
                  7,
                ),
                child: Row(
                  children: [
                    _buildTaskStatusText(
                      context,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      widget.expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 19,
                      color: widget.expanded
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (widget.expanded)
              _buildExpandedContent(
                context,
                closed,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskStatusText(
    BuildContext context,
  ) {
    final status = widget.task.status;

    final text = switch (status) {
      MtTaskStatus.pending => 'Pending',
      MtTaskStatus.started => 'In Progress',
      MtTaskStatus.completed => 'Completed',
      MtTaskStatus.cancelledNotRequired => 'Cancelled',
    };

    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: _statusColor(
          context,
          status,
        ),
      ),
    );
  }

  Color _statusColor(
    BuildContext context,
    MtTaskStatus status,
  ) {
    final colors = Theme.of(context).colorScheme;

    return switch (status) {
      MtTaskStatus.pending => colors.onSurfaceVariant,
      MtTaskStatus.started => colors.primary,
      MtTaskStatus.completed => colors.primary,
      MtTaskStatus.cancelledNotRequired => colors.error,
    };
  }

  Future<void> _toggleExpanded() async {
    if (widget.expanded) {
      await widget.onCollapse(
        widget.task.id,
      );
      return;
    }

    await widget.onExpand(
      widget.task.id,
      _commitIfDirty,
    );
  }

  // ==========================================================================
  // SUBTASK LOAD
  // ==========================================================================

  Future<void> _loadSubtasks() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final db = await AppDatabase.instance.database;

      // Direct relationship:
      //
      // db_TaskLogWeekEnd.TaskID
      // =
      // db_SubTasksMT.SubTaskID
      //
      // No TaskID parsing is needed here.
      final rows = await db.query(
        'db_SubTasksMT',
        where: 'SubTaskID = ?',
        whereArgs: [
          widget.task.id,
        ],
        orderBy: 'SubTaskSubjectCode ASC, '
            'SubTaskChapterCode ASC',
      );

      if (!mounted) {
        return;
      }

      _subtaskStatus.clear();
      _originalSubtaskStatus.clear();

      for (final row in rows) {
        final key = _subtaskKey(row);

        final status = _normalizeStatus(
          row['SubTaskStatus'],
        );

        _subtaskStatus[key] = status;
        _originalSubtaskStatus[key] = status;
      }

      setState(() {
        _subtasks = rows;
        _dirty = false;
        _loading = false;
      });

      if (widget.expanded) {
        widget.registerCommit(
          widget.task.id,
          _commitIfDirty,
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _subtasks = const [];
        _subtaskStatus.clear();
        _originalSubtaskStatus.clear();
        _dirty = false;
        _loading = false;
      });
    }
  }

  String _subtaskKey(
    Map<String, Object?> row,
  ) {
    final id = row['SubTaskID']?.toString() ?? '';

    final subject = row['SubTaskSubjectCode']?.toString() ?? '';

    final chapter = row['SubTaskChapterCode']?.toString() ?? '';

    return '$id|$subject|$chapter';
  }

  String _normalizeStatus(
    Object? value,
  ) {
    final status = (value?.toString() ?? 'PENDING').trim().toUpperCase();

    return switch (status) {
      'IN_PROGRESS' || 'STARTED' => 'IN_PROGRESS',
      'COMPLETED' || 'STOPPED' => 'COMPLETED',
      'CANCELLED' || 'CANCELLED / NOT REQUIRED' => 'CANCELLED',
      _ => 'PENDING',
    };
  }

  // ==========================================================================
  // TASK EXPANDED CONTENT
  // ==========================================================================

  Widget _buildExpandedContent(
    BuildContext context,
    bool closed,
  ) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          10,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
            ),
          ),
        ),
      );
    }

    if (_subtasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          10,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'No subtasks assigned.',
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.black54,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        12,
        0,
        12,
        10,
      ),
      child: Column(
        children: [
          for (final row in _subtasks)
            _buildSubtaskRow(
              context,
              row,
            ),
        ],
      ),
    );
  }

  // ==========================================================================
  // SUBTASK ROW
  // ==========================================================================

  Widget _buildSubtaskRow(
    BuildContext context,
    Map<String, Object?> row,
  ) {
    final key = _subtaskKey(row);

    final status = _subtaskStatus[key] ?? 'PENDING';

    final colors = Theme.of(context).colorScheme;

    final interactive = _subtaskIsInteractive();

    final locked = !interactive ||
        widget.task.status == MtTaskStatus.completed ||
        widget.task.status == MtTaskStatus.cancelledNotRequired;

    final description = row['SubTaskDescription']?.toString().trim() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          color: status == 'CANCELLED'
              ? colors.errorContainer.withValues(alpha: .35)
              : colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: status == 'CANCELLED'
                ? colors.error.withValues(alpha: .30)
                : colors.outlineVariant.withValues(alpha: .55),
          ),
        ),
        child: Row(
          children: [
            _SubtaskStatusBox(
              status: status,
              enabled: !locked && !_saving,
              onStatusSelected: (next) => _selectSubtaskStatus(
                row,
                next,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.15,
                  color: locked && status == 'PENDING'
                      ? colors.onSurfaceVariant
                      : colors.onSurface,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // SUBTASK INTERACTIVITY
  // ==========================================================================

  bool _subtaskIsInteractive() {
    final subject = _subjectCodeFromTaskId(
      widget.task.id,
    );

    // PCB is the special case.
    //
    // PCB subtasks are displayed before
    // the due date, but cannot be changed
    // until today is the due date or later.
    if (subject == 'PCB') {
      return !_isFuture(widget.task);
    }

    // PHY / CHE / BIO subtasks may be
    // worked on before the due date.
    return true;
  }

  String _subjectCodeFromTaskId(
    String taskId,
  ) {
    final parts = taskId.split('_');

    if (parts.length > 3) {
      final subject = parts[3].trim().toUpperCase();

      if (subject == 'PHY' ||
          subject == 'CHE' ||
          subject == 'BIO' ||
          subject == 'PCB') {
        return subject;
      }
    }

    return '';
  }

  bool _isFuture(MtTask task) {
    return DateUtils.dateOnly(
      task.dueDate,
    ).isAfter(
      DateUtils.dateOnly(
        DateTime.now(),
      ),
    );
  }

  // ==========================================================================
  // SUBTASK STATUS TRANSITIONS
  // ==========================================================================

  Future<void> _selectSubtaskStatus(
    Map<String, Object?> row,
    String next,
  ) async {
    if (_saving || !_subtaskIsInteractive()) {
      return;
    }

    final key = _subtaskKey(row);

    final current = _subtaskStatus[key] ?? 'PENDING';

    // Closed subtasks cannot be
    // changed again.
    if (current == 'COMPLETED' || current == 'CANCELLED') {
      return;
    }

    // PENDING -> PENDING has no effect.
    if (current == 'PENDING' && next == 'PENDING') {
      return;
    }

    // PENDING can only move forward
    // to IN_PROGRESS or CANCELLED.
    if (current == 'PENDING' && next != 'IN_PROGRESS' && next != 'CANCELLED') {
      return;
    }

    // IN_PROGRESS can never go back
    // to PENDING.
    if (current == 'IN_PROGRESS' && next == 'PENDING') {
      return;
    }

    // IN_PROGRESS can only move to
    // COMPLETED or CANCELLED.
    if (current == 'IN_PROGRESS' &&
        next != 'COMPLETED' &&
        next != 'CANCELLED') {
      return;
    }

    if (current == next) {
      return;
    }

    setState(() {
      _subtaskStatus[key] = next;
      _dirty = true;
    });

    // Starting ANY subtask moves the
    // parent task from PENDING to
    // IN_PROGRESS.
    //
    // This is an in-memory parent change.
    // It is committed together with the
    // subtask changes when the edit
    // context ends.
    if (next == 'IN_PROGRESS' && widget.task.status == MtTaskStatus.pending) {
      await widget.onTaskStatusChanged(
        widget.task.copyWith(
          status: MtTaskStatus.started,
        ),
      );
    }

    // PCB parent completion is special:
    // all three PCB subtasks must be
    // closed before the parent can close.
    if (next == 'COMPLETED' || next == 'CANCELLED') {
      await _evaluatePcbParentCompletion();
    }
  }

  // ==========================================================================
  // PCB PARENT RULE
  // ==========================================================================

  Future<void> _evaluatePcbParentCompletion() async {
    final subject = _subjectCodeFromTaskId(
      widget.task.id,
    );

    if (subject != 'PCB') {
      return;
    }

    // PCB has exactly three subtasks
    // according to the business rule.
    if (!_isFuture(widget.task) && _subtasks.length == 3) {
      final allClosed = _subtasks.every((row) {
        final key = _subtaskKey(row);

        final status = _subtaskStatus[key] ?? 'PENDING';

        return status == 'COMPLETED' || status == 'CANCELLED';
      });

      if (allClosed && widget.task.status != MtTaskStatus.completed) {
        await widget.onTaskStatusChanged(
          widget.task.copyWith(
            status: MtTaskStatus.completed,
          ),
        );
      }
    }
  }

  // ==========================================================================
  // DEFERRED COMMIT
  // ==========================================================================

  Future<void> _commitIfDirty() async {
    if (!_dirty) {
      return;
    }

    await _commitNow();
  }

  Future<void> _commitNow() async {
    if (_saving || !_dirty) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final db = await AppDatabase.instance.database;

      await db.transaction((txn) async {
        // ------------------------------------------------------------
        // SUBTASK STATUS UPDATES
        // ------------------------------------------------------------

        for (final row in _subtasks) {
          final key = _subtaskKey(row);

          final original = _originalSubtaskStatus[key] ?? 'PENDING';

          final current = _subtaskStatus[key] ?? original;

          if (original == current) {
            continue;
          }

          await txn.update(
            'db_SubTasksMT',
            {
              'SubTaskStatus': current,
              'SubTaskStatusUpdateTime': DateTime.now().toIso8601String(),
            },
            where: 'SubTaskID = ? '
                'AND SubTaskSubjectCode = ? '
                'AND SubTaskChapterCode = ?',
            whereArgs: [
              row['SubTaskID'],
              row['SubTaskSubjectCode'],
              row['SubTaskChapterCode'],
            ],
          );
        }

        // ------------------------------------------------------------
        // PARENT TASK STATUS
        // ------------------------------------------------------------

        // Once ANY subtask has moved out
        // of PENDING, the parent is no
        // longer PENDING.
        final hasStarted = _subtaskStatus.values.any(
          (status) =>
              status == 'IN_PROGRESS' ||
              status == 'COMPLETED' ||
              status == 'CANCELLED',
        );

        if (hasStarted && widget.task.status == MtTaskStatus.pending) {
          await txn.update(
            'db_TaskLogWeekEnd',
            {
              'TaskStatus': 'IN_PROGRESS',
            },
            where: 'TaskID = ?',
            whereArgs: [
              widget.task.id,
            ],
          );
        }

        // ------------------------------------------------------------
        // PCB PARENT COMPLETION
        // ------------------------------------------------------------

        final isPcb = _subjectCodeFromTaskId(
              widget.task.id,
            ) ==
            'PCB';

        final allPcbClosed = isPcb &&
            _subtasks.length == 3 &&
            _subtasks.every((row) {
              final key = _subtaskKey(row);

              final status = _subtaskStatus[key] ?? 'PENDING';

              return status == 'COMPLETED' || status == 'CANCELLED';
            });

        // PCB parent can close only on
        // the due date or later.
        if (allPcbClosed &&
            _isDueDateOrPast(
              widget.task,
            )) {
          await txn.update(
            'db_TaskLogWeekEnd',
            {
              'TaskStatus': 'COMPLETED',
            },
            where: 'TaskID = ?',
            whereArgs: [
              widget.task.id,
            ],
          );
        }
      });

      if (!mounted) {
        return;
      }

      // Determine the final parent
      // status reflected by the UI.
      final parentStarted = _subtaskStatus.values.any(
        (status) =>
            status == 'IN_PROGRESS' ||
            status == 'COMPLETED' ||
            status == 'CANCELLED',
      );

      final isPcb = _subjectCodeFromTaskId(
            widget.task.id,
          ) ==
          'PCB';

      final pcbClosed = isPcb &&
          _subtasks.length == 3 &&
          _subtasks.every((row) {
            final key = _subtaskKey(row);

            final status = _subtaskStatus[key] ?? 'PENDING';

            return status == 'COMPLETED' || status == 'CANCELLED';
          });

      var updatedTask = widget.task;

      if (pcbClosed &&
          _isDueDateOrPast(
            updatedTask,
          )) {
        updatedTask = updatedTask.copyWith(
          status: MtTaskStatus.completed,
        );
      } else if (parentStarted && updatedTask.status == MtTaskStatus.pending) {
        updatedTask = updatedTask.copyWith(
          status: MtTaskStatus.started,
        );
      }

      // Current status is now the
      // committed baseline.
      for (final row in _subtasks) {
        final key = _subtaskKey(row);

        _originalSubtaskStatus[key] = _subtaskStatus[key] ?? 'PENDING';
      }

      setState(() {
        _dirty = false;
        _saving = false;
      });

      if (updatedTask.status != widget.task.status) {
        await widget.onTaskStatusChanged(
          updatedTask,
        );
      } else {
        widget.onTaskUpdated(
          updatedTask,
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to save subtask status: '
            '$error',
          ),
        ),
      );
    }
  }

  bool _isDueDateOrPast(
    MtTask task,
  ) {
    return !DateUtils.dateOnly(
      task.dueDate,
    ).isAfter(
      DateUtils.dateOnly(
        DateTime.now(),
      ),
    );
  }
}

// =============================================================================
// SUBTASK STATUS BOX
// =============================================================================

class _SubtaskStatusBox extends StatelessWidget {
  const _SubtaskStatusBox({
    required this.status,
    required this.enabled,
    required this.onStatusSelected,
  });

  final String status;
  final bool enabled;
  final ValueChanged<String> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: colors.outlineVariant,
          width: .7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusButton(
            context,
            icon: Icons.radio_button_unchecked,
            value: 'PENDING',
            tooltip: 'Pending',
          ),
          _statusButton(
            context,
            icon: Icons.play_arrow_rounded,
            value: 'IN_PROGRESS',
            tooltip: 'In Progress',
          ),
          _statusButton(
            context,
            icon: Icons.stop_rounded,
            value: 'COMPLETED',
            tooltip: 'Completed',
          ),
          _statusButton(
            context,
            icon: Icons.close_rounded,
            value: 'CANCELLED',
            tooltip: 'Cancel',
            isCancel: true,
          ),
        ],
      ),
    );
  }

  Widget _statusButton(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String tooltip,
    bool isCancel = false,
  }) {
    final colors = Theme.of(context).colorScheme;

    final selected = status == value;

    final activeBackground =
        isCancel ? colors.errorContainer : colors.primaryContainer;

    final activeForeground = isCancel ? colors.error : colors.primary;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled
            ? () => onStatusSelected(
                  value,
                )
            : null,
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(
            milliseconds: 120,
          ),
          width: 28,
          height: 27,
          decoration: BoxDecoration(
            color: selected ? activeBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: selected
                ? Border.all(
                    color: activeForeground.withValues(
                      alpha: .75,
                    ),
                    width: 1.1,
                  )
                : null,
          ),
          child: Icon(
            icon,
            size: isCancel ? 20 : 18,
            color: !enabled
                ? colors.onSurfaceVariant.withValues(
                    alpha: .45,
                  )
                : selected
                    ? activeForeground
                    : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
