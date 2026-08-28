import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../models/mo_task.dart';
import '../models/mo_task_group.dart';
import '../services/revision_task_generator_svc.dart';
import '../services/task_activity_status_svc.dart';

class TasksScreen extends StatefulWidget {
    final List<Task> tasks;
    final ValueChanged<Task> onTaskUpdated;
    final ValueChanged<Task>? onTaskStateChanged;
    final TaskGroup? initialExpandedGroup;

    final Future<List<Map<String, Object?>>> Function()? onGenerateRevisionTasks;

    const TasksScreen({
        super.key,
        required this.tasks,
        required this.onTaskUpdated,
        this.onTaskStateChanged,
        this.initialExpandedGroup,
        required this.onGenerateRevisionTasks,
    });

    @override
    State<TasksScreen> createState() => _TasksScreenState();
}

//enum _TasksWorkspaceMode { todaysTasks, inProgressTasks, revisionTasks }
//enum _TasksWorkspaceMode { todaysTasks, revisionTasks, milestoneTasks }
enum _TasksWorkspaceMode { todaysTasks, revisionTasks }

class _TasksScreenState extends State<TasksScreen> {
    // ==========================================================================
    // WORKSPACE
    // ==========================================================================
    TaskGroup _selectedGroup = TaskGroup.dueToday;
    _TasksWorkspaceMode _mode = _TasksWorkspaceMode.todaysTasks;
    String? _expandedTaskId;
    Future<void> Function()? _commitExpandedTask;

    // ==========================================================================
    // REVISION GENERATION
    // ==========================================================================

    bool _generating = false;
    bool _revisionViewLoading = false;
    bool _revisionGeneratedToday = false;
    String? _generationError;

    bool _todayRevisionExpanded = true;
    bool _previousRevisionExpanded = false;

    List<Map<String, Object?>> _todayRevisionRows = const [];
    List<Map<String, Object?>> _previousRevisionRows = const [];

    @override
    void initState() {
        super.initState();
        _selectedGroup = widget.initialExpandedGroup ?? TaskGroup.dueToday;
    }

    @override
    void didUpdateWidget(covariant TasksScreen oldWidget) {
        super.didUpdateWidget(oldWidget);

        if (oldWidget.initialExpandedGroup != widget.initialExpandedGroup) {
            _selectedGroup = widget.initialExpandedGroup ?? TaskGroup.dueToday;
        }
    }

    // ==========================================================================
    // TASK FILTERING
    // ==========================================================================

    List<Task> _tasksFor(TaskGroup group) {
        final today = DateUtils.dateOnly(DateTime.now());

        return widget.tasks.where((task) {
            final due = DateUtils.dateOnly(task.dueDate);

            final active =
                task.status == TaskStatus.pending ||
                    task.status == TaskStatus.started;

            return switch (group) {
                TaskGroup.dueToday => due == today && active,

                TaskGroup.pastDue => due.isBefore(today) && active,

                TaskGroup.inProgress =>
                task.status == TaskStatus.started && !due.isAfter(today),

                TaskGroup.completed =>
                task.status == TaskStatus.completed ||
                    task.status == TaskStatus.cancelledNotRequired,
            };
        }).toList();
    }

    // ==========================================================================
    // GROUP PRESENTATION
    // ==========================================================================

    String _groupLabel(TaskGroup group) {
        return switch (group) {
            TaskGroup.pastDue => 'Past Due',
            TaskGroup.dueToday => 'Due Today',
            TaskGroup.inProgress => 'In Progress',
            TaskGroup.completed => 'Completed',
        };
    }

    IconData _groupIcon(TaskGroup group) {
        return switch (group) {
            TaskGroup.pastDue => Icons.warning_amber_rounded,
            TaskGroup.dueToday => Icons.today_outlined,
            TaskGroup.inProgress => Icons.play_circle_outline,
            TaskGroup.completed => Icons.check_circle_outline,
        };
    }

    Color _groupForeground(BuildContext context, TaskGroup group) {
        final colors = Theme.of(context).colorScheme;

        return switch (group) {
            TaskGroup.inProgress => const Color(0xFF35D27F),
            TaskGroup.dueToday   => const Color(0xFFFFB52E),
 //         TaskGroup.pastDue    => colors.error,
            TaskGroup.pastDue    => const Color(0xFFFF5C5C),
            TaskGroup.completed  => const Color(0xFF8E9AAF),
        };
    }

    Color _groupBackground(BuildContext context, TaskGroup group, bool selected) {
        final colors = Theme.of(context).colorScheme;

        final foreground = _groupForeground(context, group);

        return Color.alphaBlend(
            foreground.withValues(alpha: selected ? .30 : .18),
            colors.surface,
        );
    }

    // ==========================================================================
    // STATUS
    // ==========================================================================

    bool _isFuture(Task task) {
        final today = DateUtils.dateOnly(DateTime.now());

        final due = DateUtils.dateOnly(task.dueDate);

        return due.isAfter(today);
    }

    bool _isDue(Task task) {
        return !_isFuture(task);
    }

    bool _canChange(Task task) {
        return _isDue(task) &&
            task.status != TaskStatus.completed &&
            task.status != TaskStatus.cancelledNotRequired;
    }

    // ==========================================================================
    // MANUAL TASK STATUS CHANGE
    // ==========================================================================

    Future<void> _changeStatus(Task task, TaskStatus next) async {
        if (!_canChange(task)) {
            return;
        }

        final valid = switch (task.status) {
            TaskStatus.pending =>
            next == TaskStatus.started ||
                next == TaskStatus.completed ||
                next == TaskStatus.cancelledNotRequired,

            TaskStatus.started =>
            next == TaskStatus.completed || next == TaskStatus.cancelledNotRequired,

            TaskStatus.completed => false,

            TaskStatus.cancelledNotRequired => false,
        };

        if (!valid) {
            return;
        }

        if (next == TaskStatus.completed ||
            next == TaskStatus.cancelledNotRequired) {
            final db = await AppDatabase.instance.database;

            await TaskActivityStatusSvc(db).deleteForTask(task.id);
        }

        widget.onTaskUpdated(task.copyWith(status: next));
    }

    // ==========================================================================
    // EXPANDED TASK COORDINATION
    // ==========================================================================

    void _registerCommit(String taskId, Future<void> Function() commit) {
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

    Future<void> _collapseTask(String taskId) async {
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

    Future<void> _leaveExpandedTask() async {
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

    // ==========================================================================
    // REVISION GENERATION DATABASE STATE
    // ==========================================================================

    Future<void> _loadRevisionGenerationView() async {
        if (_revisionViewLoading) {
            return;
        }

        if (!mounted) {
            return;
        }

        setState(() {
            _revisionViewLoading = true;
        });

        try {
            final db = await AppDatabase.instance.database;

            final view = await RevisionTaskGeneratorSvc(
                db: db,
            ).getRevisionTaskGenerationView();

            if (!mounted) {
                return;
            }

            setState(() {
                _revisionGeneratedToday = view.generatedToday;

                _todayRevisionRows = view.todaysTasks;

                _previousRevisionRows = view.previousTasks;

                _revisionViewLoading = false;
            });
        } catch (_) {
            if (!mounted) {
                return;
            }

            setState(() {
                _revisionViewLoading = false;
                _revisionGeneratedToday = false;
                _todayRevisionRows = const [];
                _previousRevisionRows = const [];
            });
        }
    }

    // ==========================================================================
    // BUILD
    // ==========================================================================

    @override
    Widget build(BuildContext context) {
        return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                    _buildModeSelector(context),

                    const SizedBox(height: 8),
                    switch (_mode)
                    {
                        _TasksWorkspaceMode.todaysTasks => _buildStatusWorkspace(context),
//                      _TasksWorkspaceMode.inProgressTasks => _buildInProgressPanel(context,),
                        _TasksWorkspaceMode.revisionTasks => _buildRevisionTasksPanel(context,),
//                      _TasksWorkspaceMode.milestoneTasks => _buildMilestoneTasksPanel(context,),
                    },
                ],
            ),
        );
    }

    // ==========================================================================
    // STATUS WORKSPACE
    // ==========================================================================

    Widget _buildStatusWorkspace(BuildContext context) {
        return Column(
            children: [
                _buildStatusCards(context),
                const SizedBox(height: 10),
                _buildSelectedGroup(context),
            ],
        );
    }

    Widget _buildSelectedGroup(BuildContext context) {
        final group = _selectedGroup;
        final items = _tasksFor(group);

        final foreground = _groupForeground(context, group);

        return Card(
            margin: EdgeInsets.zero,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Column(
                children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                        child: Row(
                            children: [
                                Icon(_groupIcon(group), size: 19, color: foreground),
                                const SizedBox(width: 7),
                                Expanded(
                                    child: Text(
                                        _groupLabel(group),
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                        ),
                                    ),
                                ),
                                Text(
                                    '${items.length}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: foreground,
                                        fontWeight: FontWeight.w800,
                                    ),
                                ),
                            ],
                        ),
                    ),
                    if (items.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                                'No tasks in this group.',
                                style: TextStyle(fontSize: 12),
                            ),
                        )
                    else
                        Column(
                            children: [
                                for (final task in items)
                                    _TaskRow(
                                        key: ValueKey(task.id),
                                        task: task,
                                        expanded: _expandedTaskId == task.id,
                                        onExpand: _expandTask,
                                        onCollapse: _collapseTask,
                                        registerCommit: _registerCommit,
                                        onChangeStatus: _changeStatus,
                                        onTaskStateChanged: widget.onTaskStateChanged,
                                        onTaskUpdated: widget.onTaskUpdated,
                                    ),
                            ],
                        ),
                ],
            ),
        );
    }

    // ==========================================================================
    // STATUS CARDS
    // ==========================================================================

    Widget _buildStatusCards(BuildContext context) {
        final groups = [
            TaskGroup.inProgress,
            TaskGroup.dueToday,
            TaskGroup.pastDue,
            TaskGroup.completed,
        ];

        return SizedBox(
            height: 68,
            child: Row(
                children: [
                    for (var i = 0; i < groups.length; i++) ...[
                        Expanded(child: _buildStatusCard(context, groups[i])),
                        if (i < groups.length - 1) const SizedBox(width: 7),
                    ],
                ],
            ),
        );
    }

    Widget _buildStatusCard(BuildContext context, TaskGroup group) {
        final selected = _selectedGroup == group;
        final foreground = _groupForeground(context, group);
        final background = _groupBackground(context, group, selected);
        final count = _tasksFor(group).length;

        return Material(
            color: Colors.transparent,
            child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () async {
                    if (_selectedGroup == group) {
                        return;
                    }

                    await _leaveExpandedTask();

                    if (!mounted) {
                        return;
                    }

                    setState(() {
                        _selectedGroup = group;
                    });
                },
                child: Ink(
                    height: 68,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                        color: background,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                            color: selected
                                ? foreground.withValues(alpha: .85)
                                : foreground.withValues(alpha: .20),
                            width: selected ? 1.6 : 1,
                        ),
                        boxShadow: selected
                            ? [
                            BoxShadow(
                                color: foreground.withValues(alpha: .14),
                                blurRadius: 8,
                            ),
                        ]
                            : null,
                    ),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Row(
                                children: [
                                    Icon(_groupIcon(group), size: 17, color: foreground),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(
                                            '$count',
                                            style: const TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w800,
                                                height: 1,
                                            ),
                                        ),
                                    ),
                                ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                                _groupLabel(group),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: foreground,
                                    fontWeight: FontWeight.w700,
                                ),
                            ),
                        ],
                    ),
                ),
            ),
        );
    }

    // ==========================================================================
    // MODE SELECTOR
    // ==========================================================================

    Widget _buildModeSelector(BuildContext context) {
        return Card(
            elevation: 0,
            child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                    children: [
                        Expanded(
                            child: _modeButton(
                                context,
                                "Today's Tasks",
                                Icons.today_outlined,
                                _TasksWorkspaceMode.todaysTasks,
                            ),
                        ),

//                        const SizedBox(width: 5),
//                        Expanded(
//                            child: _modeButton(
//                                context,
//                               'In-Progress',
//                                Icons.play_circle_outline,
//                                _TasksWorkspaceMode.inProgressTasks,
//                            ),
//                        ),

                        const SizedBox(width: 5),
                        Expanded(
                            child: _modeButton(
                                context,
                                'Revision Tasks',
                                Icons.auto_awesome_outlined,
                                _TasksWorkspaceMode.revisionTasks,
                            ),
                        ),
//                        const SizedBox(width: 5),
//                        Expanded(
//                            child: _modeButton(
//                                context,
//                                'Milestone Tasks',
//                                Icons.auto_awesome_outlined,
//                                _TasksWorkspaceMode.milestoneTasks,
//                            ),
//                        ),
                    ],
                ),
            ),
        );
    }

    Widget _modeButton( BuildContext context, String label,IconData icon,
                  _TasksWorkspaceMode mode,)
    {
        final selected = _mode == mode;
        final colors = Theme.of(context).colorScheme;
        return Material(
            color: selected ? colors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                    if (_mode == mode) {
                        if (mode == _TasksWorkspaceMode.revisionTasks) {
                            await _loadRevisionGenerationView();
                        }
                        return;
                    }

                    await _leaveExpandedTask();

                    if (!mounted) {
                        return;
                    }

                    setState(() {
                        _mode = mode;
                    });

                    if (mode == _TasksWorkspaceMode.revisionTasks) {
                        await _loadRevisionGenerationView();
                    }
                },
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            Icon(
                                icon,
                                size: 16,
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                                child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: selected
                                            ? colors.onPrimaryContainer
                                            : colors.onSurfaceVariant,
                                    ),
                                ),
                            ),
                        ],
                    ),
                ),
            ),
        );
    }

    // ==========================================================================
    // IN-PROGRESS PANEL
    // ==========================================================================

//    Widget _buildInProgressPanel(BuildContext context) {
//        final items = _tasksFor(TaskGroup.inProgress);
//
//        return Card(
//            color: Theme.of(context).colorScheme.surfaceContainerLow,
//            child: Column(
//                children: [
//                    Padding(
//                        padding: const EdgeInsets.all(12),
//                        child: Row(
//                            children: [
//                                const Icon(Icons.play_circle_outline, size: 19),
//                                const SizedBox(width: 7),
//                                const Text(
//                                    'In-Progress Tasks',                                   style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
//                                ),
//                                const Spacer(),
//                                Text(
//                                    '${items.length}',
//                                    style: const TextStyle(
//                                        fontSize: 11,
//                                        fontWeight: FontWeight.w800,
//                                   ),
//                               ),
//                           ],
//                       ),
//                   ),
//                    if (items.isEmpty)
//                        const Padding(
//                            padding: EdgeInsets.all(16),
//                            child: Text(
//                                'No tasks are currently in progress.',
//                                style: TextStyle(fontSize: 12),
//                            ),
//                        )
//                    else
//                        Column(
//                            children: [
//                                for (final task in items)
//                                    _TaskRow(
//                                        key: ValueKey(task.id),
//                                        task: task,
//                                        expanded: _expandedTaskId == task.id,
//                                        onExpand: _expandTask,
//                                        onCollapse: _collapseTask,
//                                        registerCommit: _registerCommit,
//                                        onChangeStatus: _changeStatus,
//                                        onTaskStateChanged: widget.onTaskStateChanged,
//                                        onTaskUpdated: widget.onTaskUpdated,
//                                    ),
//                            ],
//                        ),
//               ],
//            ),
//        );
//    }

    // ==========================================================================
    // Milesotne TASKS PANEL
    // ==========================================================================

    Widget _buildMilestonesPanel(BuildContext context) {
        final colors = Theme.of(context).colorScheme;

        return Card(
            color: colors.surfaceContainerLow,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Row(
                            children: [
                                Icon(
                                    Icons.flag_outlined,
                                    size: 19,
                                    color: colors.primary,
                                ),
                                const SizedBox(width: 7),
                                const Text(
                                    'Milestones',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                    ),
                                ),
                            ],
                        ),

                        const SizedBox(height: 12),

                        Text(
                            'Milestone tasks will appear here.',
                            style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                            ),
                        ),
                    ],
                ),
            ),
        );
    }
    // ==========================================================================
    // REVISION TASKS PANEL
    // ==========================================================================

    Widget _buildRevisionTasksPanel(BuildContext context) {
        final todayTasks = _todayRevisionRows
            .map(_taskFromRevisionRow)
            .whereType<Task>()
            .toList();

        final previousTasks = _previousRevisionRows
            .map(_taskFromRevisionRow)
            .whereType<Task>()
            .toList();

        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // ----------------------------------------------------------------------
                // ONLY SHOW GENERATION CARD WHEN TODAY'S TASKS DO NOT EXIST.
                // ----------------------------------------------------------------------
                if (!_revisionGeneratedToday) ...[
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Row(
                                        children: [
                                            Icon(
                                                Icons.auto_awesome_outlined,
                                                color: Theme.of(context).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 7),
                                            const Text(
                                                'Daily Revision Tasks',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                ),
                                            ),
                                        ],
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                        width: double.infinity,
                                        height: 40,
                                        child: FilledButton.icon(
                                            onPressed: _generating ? null : _generateRevisionTasks,
                                            icon: _generating
                                                ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                                : const Icon(Icons.play_arrow_rounded, size: 18),
                                            label: Text(
                                                _generating
                                                    ? 'Generating...'
                                                    : 'Generate Revision Tasks',
                                            ),
                                        ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                        'Please generate today\'s tasks.',
                                        style: TextStyle(fontSize: 10.5),
                                    ),
                                ],
                            ),
                        ),
                    ),
                    const SizedBox(height: 10),
                ],

                // ----------------------------------------------------------------------
                // LOADING
                // ----------------------------------------------------------------------
                if (_revisionViewLoading)
                    const Card(
                        child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                            ),
                        ),
                    ),

                // ----------------------------------------------------------------------
                // TODAY'S TASKS
                // ----------------------------------------------------------------------
                if (!_revisionViewLoading && _revisionGeneratedToday)
                    _buildRevisionSection(
                        context,
                        title: 'Today\'s Tasks',
                        count: todayTasks.length,
                        tasks: todayTasks,
                        expanded: _todayRevisionExpanded,
                        highlighted: true,
                        onTap: () {
                            setState(() {
                                _todayRevisionExpanded = !_todayRevisionExpanded;
                            });
                        },
                    ),

                if (!_revisionViewLoading) const SizedBox(height: 8),

                // ----------------------------------------------------------------------
                // PREVIOUSLY GENERATED TASKS
                // ----------------------------------------------------------------------
                if (!_revisionViewLoading)
                    _buildRevisionSection(
                        context,
                        title: 'Previously Generated Revision Tasks',
                        count: previousTasks.length,
                        tasks: previousTasks,
                        expanded: _previousRevisionExpanded,
                        highlighted: false,
                        onTap: () {
                            setState(() {
                                _previousRevisionExpanded = !_previousRevisionExpanded;
                            });
                        },
                    ),

                // ----------------------------------------------------------------------
                // ERROR
                // ----------------------------------------------------------------------
                if (!_generating && _generationError != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Card(
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                    _generationError!,
                                    style: const TextStyle(fontSize: 10.5),
                                ),
                            ),
                        ),
                    ),
            ],
        );
    }

    Future<void> _generateRevisionTasks() async {
        final generator = widget.onGenerateRevisionTasks;

        if (generator == null) {
            setState(() {
                _generationError =
                'Daily Revision Task Generator is not connected to the Tasks workspace yet.';
            });
            return;
        }

        setState(() {
            _generating = true;
            _generationError = null;
        });

        try {
            await generator();

            if (!mounted) {
                return;
            }

            await _loadRevisionGenerationView();

            if (!mounted) {
                return;
            }

            setState(() {
                _generating = false;
            });
        } catch (e) {
            if (!mounted) {
                return;
            }

            setState(() {
                _generating = false;
                _generationError = 'Unable to generate revision tasks: $e';
            });
        }
    }

    Widget _buildRevisionSection(
        BuildContext context, {
            required String title,
            required int count,
            required List<Task> tasks,
            required bool expanded,
            required bool highlighted,
            required VoidCallback onTap,
        }) {
        final colors = Theme.of(context).colorScheme;

        final background = highlighted
            ? Color.alphaBlend(
            colors.primary.withValues(alpha: .16),
            colors.surfaceContainerHighest,
        )
            : colors.surfaceContainerLow;

        return Card(
            margin: EdgeInsets.zero,
            color: background,
            child: Column(
                children: [
                    InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                            child: Row(
                                children: [
                                    Icon(
                                        highlighted ? Icons.today_outlined : Icons.history_outlined,
                                        size: 19,
                                        color: highlighted
                                            ? colors.primary
                                            : colors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                        child: Text(
                                            title,
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: highlighted ? colors.primary : colors.onSurface,
                                            ),
                                        ),
                                    ),
                                    Text(
                                        '$count',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: highlighted
                                                ? colors.primary
                                                : colors.onSurfaceVariant,
                                        ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                        expanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        size: 19,
                                    ),
                                ],
                            ),
                        ),
                    ),
                    if (expanded)
                        if (tasks.isEmpty)
                            const Padding(
                                padding: EdgeInsets.all(14),
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        'No revision tasks.',
                                        style: TextStyle(fontSize: 11),
                                    ),
                                ),
                            )
                        else
                            Column(
                                children: [
                                    for (final task in tasks)
                                        _TaskRow(
                                            key: ValueKey(task.id),
                                            task: task,
                                            expanded: _expandedTaskId == task.id,
                                            onExpand: _expandTask,
                                            onCollapse: _collapseTask,
                                            registerCommit: _registerCommit,
                                            onChangeStatus: _changeStatus,
                                            onTaskStateChanged: widget.onTaskStateChanged,
                                            onTaskUpdated: widget.onTaskUpdated,
                                        ),
                                ],
                            ),
                ],
            ),
        );
    }

    // ==========================================================================
    // REVISION ROW -> TASK
    // ==========================================================================

    Task? _taskFromRevisionRow(Map<String, Object?> row) {
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

        final status = switch ((row['TaskStatus']?.toString() ?? 'PENDING')
            .toUpperCase()) {
            'IN_PROGRESS' || 'STARTED' => TaskStatus.started,

            'COMPLETED' => TaskStatus.completed,

            'CANCELLED' ||
            'CANCELLED / NOT REQUIRED' => TaskStatus.cancelledNotRequired,

            _ => TaskStatus.pending,
        };

        return Task(
            id: id,
            title: description,
            subject: _subjectFromDescription(description),
            dueDate: dueDate,
            status: status,
        );
    }

    String _subjectFromDescription(String description) {
        final match = RegExp(
            r'^Subject\s*-\s*(.+)$',
            multiLine: true,
            caseSensitive: false,
        ).firstMatch(description);

        return match?.group(1)?.trim() ?? 'Task';
    }
}

// ============================================================================
// TASK ROW
// ============================================================================

class _TaskRow extends StatefulWidget {
    const _TaskRow({
        super.key,
        required this.task,
        required this.expanded,
        required this.onExpand,
        required this.onCollapse,
        required this.registerCommit,
        required this.onChangeStatus,
        required this.onTaskStateChanged,
        required this.onTaskUpdated,
    });

    final Task task;
    final bool expanded;

    final Future<void> Function(String taskId, Future<void> Function() commit)
    onExpand;

    final Future<void> Function(String taskId) onCollapse;

    final void Function(String taskId, Future<void> Function() commit)
    registerCommit;

    final Future<void> Function(Task task, TaskStatus next) onChangeStatus;

    final ValueChanged<Task>? onTaskStateChanged;

    final ValueChanged<Task> onTaskUpdated;

    @override
    State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
    bool _loading = false;

    bool _saving = false;

    bool _dirty = false;

    List<TaskActivityDefinition> _activities = const [];

    Map<String, bool> _activityStatus = {};

    @override
    void initState() {
        super.initState();

        if (widget.expanded) {
            _loadActivities();
        }
    }

    @override
    void didUpdateWidget(covariant _TaskRow oldWidget) {
        super.didUpdateWidget(oldWidget);

        if (!oldWidget.expanded && widget.expanded) {
            _loadActivities();
        }

        if (widget.expanded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || !widget.expanded) {
                    return;
                }

                widget.registerCommit(widget.task.id, _commitIfDirty);
            });
        }
    }

    @override
    Widget build(BuildContext context) {
        final parsed = _parseCompactTask(widget.task);

        final colors = Theme.of(context).colorScheme;

        final closed =
            widget.task.status == TaskStatus.completed ||
                widget.task.status == TaskStatus.cancelledNotRequired;

        return Container(
            margin: const EdgeInsets.only(bottom: 5),
            decoration: widget.expanded
                ? BoxDecoration(
                color: const Color(0xFFF7F8FA),
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
                            padding: const EdgeInsets.fromLTRB(12, 8, 7, 7),
                            child: Row(
                                children: [
                                    Expanded(
                                        child: Text(
                                            '${parsed.dateText}  ${parsed.location}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w400,
                                                color: widget.expanded
                                                    ? Colors.black
                                                    : colors.onSurface,
                                            ),
                                        ),
                                    ),
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

                    if (widget.expanded) _buildExpandedContent(context, closed),
                ],
            ),
        );
    }

    Future<void> _toggleExpanded() async {
        if (widget.expanded) {
            await widget.onCollapse(widget.task.id);
            return;
        }

        await widget.onExpand(widget.task.id, _commitIfDirty);
    }

    // ==========================================================================
    // ACTIVITY LOAD
    // ==========================================================================

    Future<void> _loadActivities() async {
        if (!mounted) {
            return;
        }

        setState(() {
            _loading = true;
        });

        try {
            final db = await AppDatabase.instance.database;

            final svc = TaskActivityStatusSvc(db);

            final definitions = await svc.getActivitiesForTask(widget.task.id);

            final saved = await svc.loadStatus(widget.task.id);

            if (!mounted) {
                return;
            }

            final normalized = <String, bool>{};

            for (final activity in definitions) {
                normalized[activity.activityCode] =
                    saved[activity.activityCode] ?? false;
            }

            setState(() {
                _activities = definitions;
                _activityStatus = normalized;
                _dirty = false;
                _loading = false;
            });

            if (widget.expanded) {
                widget.registerCommit(widget.task.id, _commitIfDirty);
            }
        } catch (_) {
            if (!mounted) {
                return;
            }

            setState(() {
                _activities = const [];
                _activityStatus = {};
                _dirty = false;
                _loading = false;
            });
        }
    }

    // ==========================================================================
    // EXPANDED CONTENT
    // ==========================================================================

    Widget _buildExpandedContent(BuildContext context, bool closed) {
        if (_loading) {
            return const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 9),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 1.7),
                    ),
                ),
            );
        }

        return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    if (_activities.isEmpty)
                        const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                                'No activities assigned.',
                                style: TextStyle(fontSize: 10.5, color: Colors.black54),
                            ),
                        ),

                    if (_activities.isNotEmpty)
                        for (final activity in _activities)
                            _activityRow(context, activity, closed),

                    if (_activities.isNotEmpty) const SizedBox(height: 5),

                    if (!closed && !_isFuture(widget.task)) _buildInlineActions(context),
                ],
            ),
        );
    }

    // ==========================================================================
    // ACTIVITY ROW
    //
    // Whole activity description is tappable.
    //
    // Selected:
    //   subtle yellow background
    //
    // Not selected:
    //   transparent background
    //
    // Closed/future:
    //   display-only
    // ==========================================================================

    Widget _activityRow(
        BuildContext context,
        TaskActivityDefinition activity,
        bool closed,
        ) {
        final completed = _activityStatus[activity.activityCode] ?? false;

        final future = _isFuture(widget.task);

        final enabled = !future && !closed && !_saving;

        return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: enabled ? () => _toggleActivity(activity) : null,
                    child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 29),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                        decoration: BoxDecoration(
                            color: completed ? const Color(0xFFFFF3C4) : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: completed ? const Color(0xFFE5C65C) : Colors.transparent,
                                width: 1,
                            ),
                        ),
                        child: Row(
                            children: [
                                SizedBox(
                                    width: 18,
                                    child: Center(
                                        child: completed
                                            ? const Icon(
                                            Icons.check_circle,
                                            size: 14,
                                            color: Color(0xFF9A7800),
                                        )
                                            : const Icon(
                                            Icons.radio_button_unchecked,
                                            size: 14,
                                            color: Colors.black45,
                                        ),
                                    ),
                                ),

                                const SizedBox(width: 6),

                                Expanded(
                                    child: Text(
                                        '${activity.sequence}. ${activity.activityName}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            height: 1.15,
                                            color: Colors.black,
                                            fontWeight: FontWeight.w400,
                                        ),
                                    ),
                                ),
                            ],
                        ),
                    ),
                ),
            ),
        );
    }

    // ==========================================================================
    // DIRECT TASK ACTIONS
    // ==========================================================================

    Widget _buildInlineActions(BuildContext context) {
        final task = widget.task;

        if (task.status == TaskStatus.pending) {
            return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                    _actionButton(
                        label: 'Start >>',
                        onPressed: _isDue(task)
                            ? () => widget.onChangeStatus(task, TaskStatus.started)
                            : null,
                    ),

                    const SizedBox(width: 6),

                    _actionButton(
                        label: 'X Cancel Task',
                        outlined: true,
                        onPressed: _isDue(task)
                            ? () => widget.onChangeStatus(
                            task,
                            TaskStatus.cancelledNotRequired,
                        )
                            : null,
                    ),
                ],
            );
        }

        if (task.status == TaskStatus.started) {
            return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                    _actionButton(
                        label: 'Set Completed',
                        onPressed: _isDue(task)
                            ? () => widget.onChangeStatus(task, TaskStatus.completed)
                            : null,
                    ),

                    const SizedBox(width: 6),

                    _actionButton(
                        label: 'X Cancel Task',
                        outlined: true,
                        onPressed: _isDue(task)
                            ? () => widget.onChangeStatus(
                            task,
                            TaskStatus.cancelledNotRequired,
                        )
                            : null,
                    ),
                ],
            );
        }

        return const SizedBox.shrink();
    }

    Widget _actionButton({
        required String label,
        required VoidCallback? onPressed,
        bool outlined = false,
    }) {
        return SizedBox(
            height: 30,
            child: outlined
                ? OutlinedButton(
                onPressed: onPressed,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                    ),
                ),
                child: Text(label),
            )
                : FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                    ),
                ),
                child: Text(label),
            ),
        );
    }

    // ==========================================================================
    // ACTIVITY TOGGLE
    // ==========================================================================

    Future<void> _toggleActivity(TaskActivityDefinition activity) async {
        if (_saving ||
            _isFuture(widget.task) ||
            widget.task.status == TaskStatus.completed ||
            widget.task.status == TaskStatus.cancelledNotRequired) {
            return;
        }

        final current = _activityStatus[activity.activityCode] ?? false;

        final next = !current;

        setState(() {
            _activityStatus[activity.activityCode] = next;

            _dirty = true;
        });

        // Pending + first activity ON
        // => In Progress immediately.
        if (widget.task.status == TaskStatus.pending && next) {
            await _commitNow();
            return;
        }

        // All mandatory activities ON
        // => Completed immediately.
        if (_allMandatoryCompleted()) {
            await _commitNow();
        }
    }

    bool _allMandatoryCompleted() {
        final mandatory = _activities
            .where((activity) => activity.isMandatory)
            .toList();

        final required = mandatory.isNotEmpty ? mandatory : _activities;

        if (required.isEmpty) {
            return false;
        }

        return required.every(
                (activity) => _activityStatus[activity.activityCode] == true,
        );
    }

    // ==========================================================================
    // ACTIVITY COMMIT
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

            final result = await TaskActivityStatusSvc(db).commitTaskActivities(
                task: widget.task,
                activityStatus: Map<String, bool>.from(_activityStatus),
            );

            if (!mounted) {
                return;
            }

            setState(() {
                _activityStatus = result.activityStatus;

                _dirty = false;

                _saving = false;
            });

            if (result.taskStatusChanged) {
                final callback = widget.onTaskStateChanged;

                if (callback != null) {
                    callback(result.task);
                } else {
                    widget.onTaskUpdated(result.task);
                }
            }
        } catch (_) {
            if (!mounted) {
                return;
            }

            setState(() {
                _saving = false;
            });
        }
    }

    bool _isFuture(Task task) {
        final today = DateUtils.dateOnly(DateTime.now());

        final due = DateUtils.dateOnly(task.dueDate);

        return due.isAfter(today);
    }

    bool _isDue(Task task) {
        return !_isFuture(task);
    }
}

// ============================================================================
// COMPACT TASK DISPLAY PARSER
// ============================================================================

class _ParsedTaskDisplay {
    const _ParsedTaskDisplay({required this.dateText, required this.location});

    final String dateText;
    final String location;
}

class _ParsedTaskId {
    const _ParsedTaskId({
        required this.subjectCode,
        required this.chapterCode,
        required this.topicCode,
    });

    final String subjectCode;
    final String chapterCode;
    final String topicCode;
}

class _ParsedActivityText {
    const _ParsedActivityText({required this.topic, required this.activity});

    final String topic;
    final String activity;
}

_ParsedTaskDisplay _parseCompactTask(Task task) {
    final id = _parseTaskId(task.id);

    String topic = '';

    for (final rawLine in task.title.split('\n')) {
        final line = rawLine.trim();

        if (line.isEmpty) {
            continue;
        }

        if (line.toLowerCase().startsWith('todo')) {
            final separator = line.indexOf('-');

            if (separator >= 0) {
                final parsed = _parseActivityText(line.substring(separator + 1).trim());

                if (parsed != null) {
                    topic = parsed.topic;
                    break;
                }
            }
        }

        if (RegExp(r'^-\s*\d+\.').hasMatch(line)) {
            final parsed = _parseActivityText(line.substring(1).trim());

            if (parsed != null) {
                topic = parsed.topic;
                break;
            }
        }
    }

    if (topic.isEmpty) {
        topic = id.topicCode;
    }

    final code = [
        id.subjectCode,
        id.chapterCode,
    ].where((value) => value.isNotEmpty).join('-');

    final location = code.isEmpty ? topic : '$code → $topic';

    return _ParsedTaskDisplay(
        dateText: '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
        location: location,
    );
}

_ParsedTaskId _parseTaskId(String taskId) {
    var subject = '';
    var chapter = '';
    var topic = '';

    for (final token in taskId.split('_')) {
        final match = RegExp(
            r'^([A-Za-z]+)-(Ch\d+)-(T\d+)$',
        ).firstMatch(token.trim());

        if (match != null) {
            subject = match.group(1)!;

            chapter = match.group(2)!;

            topic = match.group(3)!;

            break;
        }
    }

    return _ParsedTaskId(
        subjectCode: subject,
        chapterCode: chapter,
        topicCode: topic,
    );
}

_ParsedActivityText? _parseActivityText(String value) {
    final match = RegExp(r'^(\d+)\.\s*(.*?)\s*-\s*(.+)$').firstMatch(value);

    if (match == null) {
        return null;
    }

    final topic = match.group(2)!.trim();

    final activity = match.group(3)!.trim();

    if (topic.isEmpty || activity.isEmpty) {
        return null;
    }

    return _ParsedActivityText(topic: topic, activity: activity);
}
