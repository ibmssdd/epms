import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../../models/task_group.dart';
import '../../services/milestone_calendar_svc.dart';
import '../../services/revision_task_generator_svc.dart';
import '../../services/syllabus_coverage_svc.dart';
import '../../services/task_enquiry_svc.dart';
import '../../database/app_database.dart';
import '../../widgets/navigation/left_navigation.dart';
import '../../screens/tasks/tasks_screen.dart';
import '../lectures/lecture_screen.dart';
import '../syllabus/syllabus_screen.dart';
import '../milestones/milestone_calendar_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ============================================================
  // SHELL STATE
  // ============================================================

  bool leftExpanded = true;

  int selectedNavigationIndex = 0;

  String? selectedLectureSubjectCode;

  // ============================================================
  // TASK DATA
  // ============================================================

  List<Task> tasks = [];

  int _dueTodayCount = 0;
  int _pastDueCount = 0;
  int _inProgressCount = 0;

  int _revisionTaskCount = 0;
  int _milestoneTaskCount = 0;

  bool _taskCountersLoading = false;

  // ============================================================
  // SYLLABUS DATA
  // ============================================================

  Map<String, Object?>? _syllabusCoverage;

  bool _syllabusLoading = true;

  // ============================================================
  // MILESTONE DATA
  // ============================================================

  List<Map<String, Object?>> _upcomingMilestones = [];

  bool _milestonesLoading = true;

  // ============================================================
  // SERVICES
  // ============================================================

  final SyllabusCoverageService _syllabusService =
      SyllabusCoverageService.instance;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();

    _loadTasks();
    _loadTaskCounters();
    _loadMilestones();
    _loadSyllabusCoverage();
  }

  // ============================================================
  // TASK COUNTERS
  // ============================================================

  Future<void> _loadTaskCounters() async {
    if (_taskCountersLoading) {
      return;
    }

    _taskCountersLoading = true;

    try {
      final db = await AppDatabase.instance.database;

      final enquiry = TaskEnquirySvc(db);

      final counters = await enquiry.getTaskCounters();

      final rows = await enquiry.getAllTasks();

      int revisionCount = 0;
      int milestoneCount = 0;

      for (final row in rows) {
        final id = row['TaskID']?.toString().trim() ?? '';

        final description =
            row['TaskDescription']?.toString().trim() ?? '';

        final status =
        (row['TaskStatus']?.toString() ?? 'PENDING').toUpperCase();

        if (status == 'CANCELLED' ||
            status == 'CANCELLED / NOT REQUIRED') {
          continue;
        }

        final searchableText =
        '$id $description'.toLowerCase();

        if (searchableText.contains('revision')) {
          revisionCount++;
        }

        if (id.startsWith('WE_')) {
          milestoneCount++;
        }
      }

      if (!mounted) return;

      setState(() {
        _dueTodayCount = counters['dueToday'] ?? 0;
        _pastDueCount = counters['pastDue'] ?? 0;
        _inProgressCount = counters['inProgress'] ?? 0;

        _revisionTaskCount = revisionCount;
        _milestoneTaskCount = milestoneCount;
      });
    } catch (_) {
      // Keep dashboard usable if counter loading fails.
    } finally {
      _taskCountersLoading = false;
    }
  }

  Future<void> _refreshTaskCounters() async {
    if (_taskCountersLoading) {
      return;
    }

    setState(() {
      _taskCountersLoading = true;
    });

    try {
      await _loadTasks();

      final db = await AppDatabase.instance.database;

      final enquiry = TaskEnquirySvc(db);

      final counters = await enquiry.getTaskCounters();

      final rows = await enquiry.getAllTasks();

      int revisionCount = 0;
      int milestoneCount = 0;

      for (final row in rows) {
        final id = row['TaskID']?.toString().trim() ?? '';

        final description =
            row['TaskDescription']?.toString().trim() ?? '';

        final status =
        (row['TaskStatus']?.toString() ?? 'PENDING').toUpperCase();

        if (status == 'CANCELLED' ||
            status == 'CANCELLED / NOT REQUIRED') {
          continue;
        }

        final searchableText =
        '$id $description'.toLowerCase();

        if (searchableText.contains('revision')) {
          revisionCount++;
        }

        if (id.startsWith('WE_')) {
          milestoneCount++;
        }
      }

      if (!mounted) return;

      setState(() {
        _dueTodayCount = counters['dueToday'] ?? 0;
        _pastDueCount = counters['pastDue'] ?? 0;
        _inProgressCount = counters['inProgress'] ?? 0;

        _revisionTaskCount = revisionCount;
        _milestoneTaskCount = milestoneCount;
      });
    } catch (_) {
      // Keep existing values if refresh fails.
    } finally {
      if (mounted) {
        setState(() {
          _taskCountersLoading = false;
        });
      } else {
        _taskCountersLoading = false;
      }
    }
  }

  // ============================================================
  // TASK DATA
  // ============================================================

  Future<void> _loadTasks() async {
    try {
      final db = await AppDatabase.instance.database;

      final rows = await TaskEnquirySvc(db).getAllTasks();

      final loaded =
      rows.map(_taskFromRow).whereType<Task>().toList();

      if (!mounted) return;

      setState(() {
        tasks = loaded;
      });
    } catch (_) {
      // Keep dashboard usable if task loading fails.
    }
  }

  Future<List<Map<String, Object?>>> _generateRevisionTasks() async {
    final db = await AppDatabase.instance.database;

    final generator = RevisionTaskGeneratorSvc(db: db);

    final rows = await generator.generateRevisionTaskRows();

    await _loadTasks();
    await _loadTaskCounters();

    return rows;
  }

  Task? _taskFromRow(Map<String, Object?> row) {
    final id = row['TaskID']?.toString().trim();

    final description =
        row['TaskDescription']?.toString() ?? '';

    final dueText =
    row['TaskDueDate']?.toString();

    if (id == null || id.isEmpty || dueText == null) {
      return null;
    }

    final dueDate = DateTime.tryParse(dueText);

    if (dueDate == null) {
      return null;
    }

    final status = switch (
    (row['TaskStatus']?.toString() ?? 'PENDING').toUpperCase()) {
      'IN_PROGRESS' || 'STARTED' => TaskStatus.started,

      'COMPLETED' => TaskStatus.completed,

      'CANCELLED' ||
      'CANCELLED / NOT REQUIRED' =>
      TaskStatus.cancelledNotRequired,

      _ => TaskStatus.pending,
    };

    final subject = _subjectFromDescription(description);

    return Task(
      id: id,
      title: description,
      subject: subject,
      dueDate: dueDate,
      status: status,
    );
  }

  String _subjectFromDescription(String description) {
    for (final line in description.split('\n')) {
      final trimmed = line.trim();

      if (trimmed.toLowerCase().startsWith('subject -')) {
        return trimmed
            .substring('subject -'.length)
            .trim();
      }
    }

    return 'Task';
  }

  // ============================================================
  // SYLLABUS COVERAGE
  // ============================================================

  Future<void> _loadSyllabusCoverage() async {
    try {
      final coverage =
      await _syllabusService.getOverallCoverage();

      if (!mounted) return;

      setState(() {
        _syllabusCoverage = coverage;
        _syllabusLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _syllabusCoverage = null;
        _syllabusLoading = false;
      });
    }
  }

  // ============================================================
  // MILESTONE DATA
  // ============================================================

  Future<void> _loadMilestones() async {
    try {
      final db =
      await AppDatabase.instance.database;

      final svc =
      MilestoneCalendarSvc(db);

      final rows =
      await svc.getNextSundayMilestonesWithNames();

      if (!mounted) return;

      setState(() {
        _upcomingMilestones = rows;
        _milestonesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _upcomingMilestones = [];
        _milestonesLoading = false;
      });
    }
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  void _selectNavigation(int index) {
    setState(() {
      selectedNavigationIndex = index;

      if (index != 0) {
        leftExpanded = false;
      }

      if (index != 4) {
        selectedLectureSubjectCode = null;
      }
    });

    if (index == 0) {
      _refreshTaskCounters();
    }
  }

  void _toggleLeftNavigation() {
    setState(() {
      leftExpanded = !leftExpanded;
    });
  }

  // ============================================================
  // MILESTONE NAVIGATION
  // ============================================================

  void _openMilestoneCalendar() {
    setState(() {
      selectedNavigationIndex = 5;
      selectedLectureSubjectCode = null;
      leftExpanded = false;
    });
  }

  // ============================================================
  // TASK NAVIGATION
  // ============================================================

  void _openTaskGroup(TaskGroup group) {
    setState(() {
      selectedNavigationIndex = 1;
      leftExpanded = false;
    });
  }

  void _openRevisionTasks() {
    setState(() {
      selectedNavigationIndex = 1;
      leftExpanded = false;
    });
  }

  void _openMilestoneTasks() {
    _openMilestoneCalendar();
  }

  // ============================================================
  // SYLLABUS NAVIGATION
  // ============================================================

  void _openSyllabus() {
    setState(() {
      selectedNavigationIndex = 2;
      selectedLectureSubjectCode = null;
      leftExpanded = false;
    });
  }

  // ============================================================
  // LECTURE NAVIGATION
  // ============================================================

  void _openLectureSubject(String subjectCode) {
    setState(() {
      selectedLectureSubjectCode = subjectCode;
      selectedNavigationIndex = 4;
      leftExpanded = false;
    });
  }

  // ============================================================
  // TASK UPDATE
  // ============================================================

  void _updateTask(Task updated) {
    _persistTaskUpdate(updated);
  }

  Future<void> _persistTaskUpdate(Task updated) async {
    final index =
    tasks.indexWhere((t) => t.id == updated.id);

    if (index == -1) return;

    final db =
    await AppDatabase.instance.database;

    final table = updated.id.startsWith('WE_')
        ? 'db_TaskLogWeekEnd'
        : 'db_TaskLogWeekDay';

    final now =
    DateTime.now().toIso8601String();

    final values = <String, Object?>{
      'TaskStatus': switch (updated.status) {
        TaskStatus.pending => 'PENDING',
        TaskStatus.started => 'IN_PROGRESS',
        TaskStatus.completed => 'COMPLETED',
        TaskStatus.cancelledNotRequired =>
        'CANCELLED / NOT REQUIRED',
      },
    };

    if (updated.status == TaskStatus.completed) {
      values['TaskCompletedDate'] = now;
      values['TaskCancelledDate'] = null;
    } else if (
    updated.status ==
        TaskStatus.cancelledNotRequired) {
      values['TaskCancelledDate'] = now;
      values['TaskCompletedDate'] = null;
    } else {
      values['TaskCompletedDate'] = null;
      values['TaskCancelledDate'] = null;
    }

    await db.update(
      table,
      values,
      where: 'TaskID = ?',
      whereArgs: [updated.id],
    );

    if (!mounted) return;

    setState(() {
      tasks[index] = updated;
    });

    await _refreshTaskCounters();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090909),
      body: SafeArea(
        child: Row(
          children: [
            // ==================================================
            // LEFT NAVIGATION
            // ==================================================

            AnimatedContainer(
              duration:
              const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              width: leftExpanded ? 190 : 60,
              child: LeftNavigation(
                expanded: leftExpanded,
                selectedIndex:
                selectedNavigationIndex,
                onSelected: _selectNavigation,
              ),
            ),

            // ==================================================
            // MAIN AREA
            // ==================================================

            Expanded(
              child: _buildMain(context),
            ),

            // ==================================================
            // RIGHT PANEL
            //
            // IMPORTANT:
            // This panel is now ALWAYS visible.
            // There is no rightExpanded state and no
            // right-side expand/collapse button.
            // ==================================================

            SizedBox(
              width: 270,
              child: Padding(
                padding:
                const EdgeInsets.fromLTRB(
                  0,
                  12,
                  12,
                  12,
                ),
                child:
                _buildRightPanel(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MAIN WORKSPACE
  // ============================================================

  Widget _buildMain(BuildContext context) {
    final Widget content;

    if (selectedNavigationIndex == 1) {
      content = TasksScreen(
        tasks: tasks,
        onTaskUpdated: _updateTask,
        initialExpandedGroup: null,
        onGenerateRevisionTasks:
        _generateRevisionTasks,
      );
    } else if (selectedNavigationIndex == 2) {
      content = const SyllabusScreen();
    } else if (selectedNavigationIndex == 4) {
      content = LectureScreen(
        initialSubjectCode:
        selectedLectureSubjectCode,
      );
    } else if (selectedNavigationIndex == 5) {
      content =
      const MilestoneCalendarScreen();
    } else {
      content =
          _buildDashboardContent(context);
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildTopHeader(context),
          const SizedBox(height: 12),
          Expanded(
            child: content,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SCREEN TITLE
  // ============================================================

  String _getCurrentScreenTitle() {
    switch (selectedNavigationIndex) {
      case 1:
        return 'TASKS';

      case 2:
        return 'SYLLABUS';

      case 4:
        return 'LECTURES';

      case 5:
        return 'MILESTONES';

      case 0:
      default:
        return 'DASHBOARD';
    }
  }

  // ============================================================
  // DAYS LEFT
  // ============================================================

  int _calculateDaysLeft() {
    final today = DateTime.now();

    final targetDate = DateTime(
      2027,
      5,
      1,
    );

    final todayOnly = DateTime(
      today.year,
      today.month,
      today.day,
    );

    final days =
        targetDate.difference(todayOnly).inDays;

    return days < 0 ? 0 : days;
  }

  // ============================================================
  // TOP HEADER
  // ============================================================

  Widget _buildTopHeader(BuildContext context) {
    final daysLeft =
    _calculateDaysLeft();

    final screenTitle =
    _getCurrentScreenTitle();

    const gold =
    Color(0xFFD4AF37);

    const mutedGold =
    Color(0xFFB99A45);

    return Container(
      constraints:
      const BoxConstraints(
        minHeight: 70,
        maxHeight: 76,
      ),
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        gradient:
        const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF171717),
            Color(0xFF0D0D0D),
            Color(0xFF17120A),
          ],
        ),
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color:
          gold.withValues(alpha: .45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: .55),
            blurRadius: 16,
            offset:
            const Offset(0, 6),
          ),
          BoxShadow(
            color: gold
                .withValues(alpha: .08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          // ----------------------------------------------------
          // NAVIGATION BUTTON
          // ----------------------------------------------------

          SizedBox(
            width: 38,
            child: IconButton(
              padding:
              EdgeInsets.zero,
              tooltip: leftExpanded
                  ? 'Collapse navigation'
                  : 'Expand navigation',
              onPressed:
              _toggleLeftNavigation,
              icon: const Icon(
                Icons
                    .keyboard_double_arrow_left,
                color: gold,
                size: 20,
              ),
            ),
          ),

          const SizedBox(width: 4),

          // ----------------------------------------------------
          // GREETING
          // ----------------------------------------------------

          Expanded(
            flex: 3,
            child: Row(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                const Text(
                  '✦',
                  style: TextStyle(
                    color: gold,
                    fontSize: 18,
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'HELLO, MR TANUSH',
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style:
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight:
                      FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // SYSTEM / DASHBOARD
          // ----------------------------------------------------

          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              mainAxisSize:
              MainAxisSize.min,
              children: [
                FittedBox(
                  fit:
                  BoxFit.scaleDown,
                  child: Text(
                    'EXAM PREPARATION SYSTEM',
                    textAlign:
                    TextAlign.center,
                    style:
                    const TextStyle(
                      color: mutedGold,
                      fontSize: 11,
                      fontWeight:
                      FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                FittedBox(
                  fit:
                  BoxFit.scaleDown,
                  child: Text(
                    screenTitle,
                    textAlign:
                    TextAlign.center,
                    maxLines: 1,
                    overflow:
                    TextOverflow.ellipsis,
                    style:
                    const TextStyle(
                      color: gold,
                      fontSize: 20,
                      fontWeight:
                      FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // METRICS
          // ----------------------------------------------------

          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment:
              MainAxisAlignment.end,
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Flexible(
                  child:
                  _headerMetric(
                    label: 'DAYS LEFT',
                    value: '$daysLeft',
                    gold: gold,
                  ),
                ),
                const SizedBox(
                  width: 12,
                ),
                Flexible(
                  child:
                  _headerMetric(
                    label: 'READINESS',
                    value: '20%',
                    gold: gold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerMetric({
    required String label,
    required String value,
    required Color gold,
  }) {
    return Column(
      mainAxisAlignment:
      MainAxisAlignment.center,
      crossAxisAlignment:
      CrossAxisAlignment.end,
      mainAxisSize:
      MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: Colors.white
                  .withValues(alpha: .65),
              fontSize: 8,
              fontWeight:
              FontWeight.w700,
              letterSpacing: .6,
            ),
          ),
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: gold,
              fontSize: 17,
              fontWeight:
              FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DASHBOARD CONTENT
  // ============================================================

  Widget _buildDashboardContent(
      BuildContext context) {
    return LayoutBuilder(
      builder:
          (context, constraints) {
        return SingleChildScrollView(
          padding:
          const EdgeInsets.only(
            bottom: 8,
          ),
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,
            children: [
              _buildLectureSection(
                  context),

              const SizedBox(
                height: 10,
              ),

              // ------------------------------------------------
              // TASKS + SYLLABUS
              // ------------------------------------------------

              if (constraints.maxWidth <
                  620)
                Column(
                  children: [
                    _buildTasksSection(
                        context),
                    const SizedBox(
                      height: 10,
                    ),
                    _buildSyllabusSection(
                        context),
                  ],
                )
              else
                Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child:
                      _buildTasksSection(
                          context),
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Expanded(
                      child:
                      _buildSyllabusSection(
                          context),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // LECTURES
  // ============================================================

  Widget _buildLectureSection(
      BuildContext context) {
    return _dashboardPanel(
      context,
      title: 'LECTURES',
      child:
      _buildLectureSubjectCards(
          context),
    );
  }

  Widget _buildLectureSubjectCards(
      BuildContext context) {
    final lectureSubjects = [
      (
      'Phy',
      'Physics',
      Icons.science_outlined,
      ),
      (
      'Chem',
      'Chemistry',
      Icons.biotech_outlined,
      ),
      (
      'Bio',
      'Biology',
      Icons.eco_outlined,
      ),
    ];

    return Row(
      children: [
        for (var i = 0;
        i < lectureSubjects.length;
        i++) ...[
          Expanded(
            child:
            _lectureSubjectCard(
              context,
              code:
              lectureSubjects[i].$1,
              name:
              lectureSubjects[i].$2,
              icon:
              lectureSubjects[i].$3,
            ),
          ),
          if (i <
              lectureSubjects.length - 1)
            const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _lectureSubjectCard(
      BuildContext context, {
        required String code,
        required String name,
        required IconData icon,
      }) {
    const gold =
    Color(0xFFD4AF37);

    return Material(
      color: Colors.transparent,
      borderRadius:
      BorderRadius.circular(10),
      child: InkWell(
        borderRadius:
        BorderRadius.circular(10),
        onTap: () =>
            _openLectureSubject(
                code),
        child: Ink(
          height: 68,
          decoration:
          BoxDecoration(
            gradient:
            const LinearGradient(
              begin:
              Alignment.topLeft,
              end:
              Alignment.bottomRight,
              colors: [
                Color(0xFF202020),
                Color(0xFF0E0E0E),
              ],
            ),
            borderRadius:
            BorderRadius.circular(10),
            border: Border.all(
              color: gold.withValues(
                  alpha: .28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: .45),
                blurRadius: 8,
                offset:
                const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment:
            MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 21,
                color: gold,
              ),
              const SizedBox(
                width: 7,
              ),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TASKS SECTION
  // ============================================================

  Widget _buildTasksSection(
      BuildContext context) {
    return _dashboardPanel(
      context,
      title: 'TASKS',
      child: _buildTaskCards(
          context),
    );
  }

  Widget _buildTaskCards(
      BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics:
      const NeverScrollableScrollPhysics(),

      itemCount: 6,

      gridDelegate:
      const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 7,
        mainAxisSpacing: 7,
        mainAxisExtent: 66,
      ),

      itemBuilder: (_, index) {
        switch (index) {
          case 0:
            return _taskStatCard(
              context,
              label: "Today's Tasks",
              count:
              _dueTodayCount,
              icon:
              Icons.today_rounded,
              onTap: () =>
                  _openTaskGroup(
                    TaskGroup.dueToday,
                  ),
            );

          case 1:
            return _taskStatCard(
              context,
              label: 'Past Due',
              count:
              _pastDueCount,
              icon:
              Icons.pending_actions_rounded,
              onTap: () =>
                  _openTaskGroup(
                    TaskGroup.pastDue,
                  ),
            );

          case 2:
            return _taskStatCard(
              context,
              label: 'In Progress',
              count:
              _inProgressCount,
              icon:
              Icons.play_circle_outline_rounded,
              onTap: () =>
                  _openTaskGroup(
                    TaskGroup.inProgress,
                  ),
            );

          case 3:
            return _taskStatCard(
              context,
              label: 'Revision Tasks',
              count:
              _revisionTaskCount,
              icon:
              Icons.replay_rounded,
              onTap:
              _openRevisionTasks,
            );

          case 4:
            return _taskStatCard(
              context,
              label: 'Refresh Counters',
              count: null,
              icon:
              _taskCountersLoading
                  ? Icons.sync_rounded
                  : Icons.refresh_rounded,
              onTap:
              _refreshTaskCounters,
              showChevron: false,
              showSpinner:
              _taskCountersLoading,
            );

          case 5:
            return _taskStatCard(
              context,
              label: 'Milestone Tasks',
              count:
              _milestoneTaskCount,
              icon:
              Icons.flag_rounded,
              onTap:
              _openMilestoneTasks,
            );

          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Widget _taskStatCard(
      BuildContext context, {
        required String label,
        required int? count,
        required IconData icon,
        required VoidCallback onTap,
        bool showChevron = true,
        bool showSpinner = false,
      }) {
    const gold =
    Color(0xFFD4AF37);

    return Material(
      color: Colors.transparent,
      borderRadius:
      BorderRadius.circular(9),
      child: InkWell(
        borderRadius:
        BorderRadius.circular(9),
        onTap: onTap,
        child: Ink(
          decoration:
          BoxDecoration(
            gradient:
            const LinearGradient(
              begin:
              Alignment.topLeft,
              end:
              Alignment.bottomRight,
              colors: [
                Color(0xFF242424),
                Color(0xFF0C0C0C),
              ],
            ),
            borderRadius:
            BorderRadius.circular(9),
            border: Border.all(
              color:
              gold.withValues(alpha: .30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: .45),
                blurRadius: 7,
                offset:
                const Offset(0, 3),
              ),
            ],
          ),
          padding:
          const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 7,
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration:
                BoxDecoration(
                  color: gold.withValues(
                      alpha: .10),
                  shape:
                  BoxShape.circle,
                  border: Border.all(
                    color:
                    gold.withValues(
                        alpha: .22),
                  ),
                ),
                child:
                showSpinner
                    ? const SizedBox(
                  width: 15,
                  height: 15,
                  child:
                  CircularProgressIndicator(
                    strokeWidth:
                    1.8,
                  ),
                )
                    : Icon(
                  icon,
                  color: gold,
                  size: 15,
                ),
              ),

              const SizedBox(
                width: 7,
              ),

              Expanded(
                child: Column(
                  mainAxisAlignment:
                  MainAxisAlignment.center,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  mainAxisSize:
                  MainAxisSize.min,
                  children: [
                    if (count != null)
                      Text(
                        '$count',
                        maxLines: 1,
                        style:
                        const TextStyle(
                          color: gold,
                          fontSize: 17,
                          fontWeight:
                          FontWeight.w900,
                        ),
                      )
                    else
                      const SizedBox(
                        height: 20,
                      ),

                    const SizedBox(
                      height: 1,
                    ),

                    Text(
                      label,
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                      style:
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              if (showChevron)
                const SizedBox(
                  width: 2,
                ),

              if (showChevron)
                Icon(
                  Icons
                      .chevron_right_rounded,
                  size: 15,
                  color: Colors.white
                      .withValues(alpha: .40),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SYLLABUS SECTION
  // ============================================================

  Widget _buildSyllabusSection(
      BuildContext context) {
    return _dashboardPanel(
      context,
      title:
      'SYLLABUS COVERAGE',
      child:
      _buildSyllabusCards(context),
    );
  }

  Widget _buildSyllabusCards(
      BuildContext context) {
    if (_syllabusLoading) {
      return const SizedBox(
        height: 139,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child:
            CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    if (_syllabusCoverage == null) {
      return SizedBox(
        height: 139,
        child: Center(
          child: Text(
            'Unable to load syllabus coverage.',
            textAlign:
            TextAlign.center,
            style: TextStyle(
              color: Colors.white
                  .withValues(alpha: .60),
              fontSize: 10,
            ),
          ),
        ),
      );
    }

    final subjects =
        (_syllabusCoverage![
        'subjects']
        as List<
            Map<String,
                Object?>>?) ??
            <Map<String,
                Object?>>[];

    final overallProgress =
    _asDouble(
      _syllabusCoverage![
      'progress'],
    );

    final overallCompletedChapters =
    _asInt(
      _syllabusCoverage![
      'completedChapters'],
    );

    final overallTotalChapters =
    _asInt(
      _syllabusCoverage![
      'totalChapters'],
    );

    final cards = <Widget>[
      _syllabusStatCard(
        context,
        label:
        'Total Syllabus',
        value:
        '${(overallProgress * 100).round()}%',
        detail:
        '$overallCompletedChapters/$overallTotalChapters chapters',
        icon:
        Icons.auto_graph_rounded,
      ),
    ];

    for (final subject
    in subjects.take(3)) {
      final subjectName =
          subject['subjectName']
              ?.toString()
              .trim() ??
              '';

      final completedTopics =
      _asInt(
        subject[
        'completedTopics'],
      );

      final totalTopics =
      _asInt(
        subject['totalTopics'],
      );

      final progress =
      _asDouble(
        subject['progress'],
      );

      cards.add(
        _syllabusStatCard(
          context,
          label: subjectName
              .isEmpty
              ? 'Subject'
              : subjectName,
          value:
          '${(progress * 100).round()}%',
          detail:
          '$completedTopics/$totalTopics topics',
          icon:
          Icons.menu_book_rounded,
        ),
      );
    }

    while (cards.length < 4) {
      cards.add(
        _syllabusStatCard(
          context,
          label: 'Syllabus',
          value: '0%',
          detail: 'No data',
          icon:
          Icons.menu_book_outlined,
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics:
      const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate:
      const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 7,
        mainAxisSpacing: 7,
        mainAxisExtent: 66,
      ),
      itemBuilder: (_, index) =>
      cards[index],
    );
  }

  Widget _syllabusStatCard(
      BuildContext context, {
        required String label,
        required String value,
        required String detail,
        required IconData icon,
      }) {
    const gold =
    Color(0xFFD4AF37);

    return Material(
      color: Colors.transparent,
      borderRadius:
      BorderRadius.circular(9),
      child: InkWell(
        borderRadius:
        BorderRadius.circular(9),
        onTap: _openSyllabus,
        child: Ink(
          decoration:
          BoxDecoration(
            gradient:
            const LinearGradient(
              begin:
              Alignment.topLeft,
              end:
              Alignment.bottomRight,
              colors: [
                Color(0xFF242424),
                Color(0xFF0D0D0D),
              ],
            ),
            borderRadius:
            BorderRadius.circular(9),
            border: Border.all(
              color:
              gold.withValues(alpha: .30),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: .45),
                blurRadius: 7,
                offset:
                const Offset(0, 3),
              ),
            ],
          ),
          padding:
          const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 7,
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration:
                BoxDecoration(
                  color: gold.withValues(
                      alpha: .10),
                  shape:
                  BoxShape.circle,
                  border: Border.all(
                    color:
                    gold.withValues(
                        alpha: .22),
                  ),
                ),
                child: Icon(
                  icon,
                  color: gold,
                  size: 15,
                ),
              ),

              const SizedBox(
                width: 7,
              ),

              Expanded(
                child: Column(
                  mainAxisAlignment:
                  MainAxisAlignment.center,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  mainAxisSize:
                  MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      maxLines: 1,
                      style:
                      const TextStyle(
                        color: gold,
                        fontSize: 16,
                        fontWeight:
                        FontWeight.w900,
                      ),
                    ),
                    const SizedBox(
                      height: 1,
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style:
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),
                    const SizedBox(
                      height: 1,
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow:
                      TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white
                            .withValues(
                            alpha: .52),
                        fontSize: 8,
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 2,
              ),

              Icon(
                Icons
                    .chevron_right_rounded,
                size: 15,
                color: Colors.white
                    .withValues(alpha: .40),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // GENERIC DASHBOARD PANEL
  // ============================================================

  Widget _dashboardPanel(
      BuildContext context, {
        required String title,
        required Widget child,
      }) {
    const gold =
    Color(0xFFD4AF37);

    return Container(
      padding:
      const EdgeInsets.fromLTRB(
        10,
        9,
        10,
        10,
      ),
      decoration:
      BoxDecoration(
        gradient:
        const LinearGradient(
          begin:
          Alignment.topLeft,
          end:
          Alignment.bottomRight,
          colors: [
            Color(0xFF151515),
            Color(0xFF0B0B0B),
          ],
        ),
        borderRadius:
        BorderRadius.circular(12),
        border: Border.all(
          color:
          gold.withValues(alpha: .28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(alpha: .55),
            blurRadius: 12,
            offset:
            const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow:
            TextOverflow.ellipsis,
            style:
            const TextStyle(
              color: gold,
              fontSize: 11,
              fontWeight:
              FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(
            height: 7,
          ),
          child,
        ],
      ),
    );
  }

  // ============================================================
  // RIGHT PANEL
  // ============================================================

  Widget _buildRightPanel(
      BuildContext context) {
    return Container(
      decoration:
      BoxDecoration(
        gradient:
        const LinearGradient(
          begin:
          Alignment.topLeft,
          end:
          Alignment.bottomRight,
          colors: [
            Color(0xFF121212),
            Color(0xFF080808),
          ],
        ),
        borderRadius:
        BorderRadius.circular(14),
        border: Border.all(
          color:
          const Color(0xFFD4AF37)
              .withValues(
              alpha: .25),
        ),
      ),
      child:
      SingleChildScrollView(
        padding:
        const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.stretch,
          children: [
            _buildUpcomingSundaySection(
                context),
            const SizedBox(
              height: 9,
            ),
            _buildActiveWorkspaceSection(
                context),
            const SizedBox(
              height: 9,
            ),
            _buildReservedRightPanelSection(
                context),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UPCOMING SUNDAY MILESTONES
  // ============================================================

  Widget _buildUpcomingSundaySection(
      BuildContext context) {
    const gold =
    Color(0xFFD4AF37);

    return Material(
      color: Colors.transparent,
      borderRadius:
      BorderRadius.circular(11),
      child: InkWell(
        borderRadius:
        BorderRadius.circular(11),
        onTap:
        _openMilestoneCalendar,
        child: Ink(
          padding:
          const EdgeInsets.fromLTRB(
            9,
            8,
            9,
            7,
          ),
          decoration:
          BoxDecoration(
            gradient:
            const LinearGradient(
              colors: [
                Color(0xFF1C1C1C),
                Color(0xFF0B0B0B),
              ],
            ),
            borderRadius:
            BorderRadius.circular(11),
            border: Border.all(
              color:
              gold.withValues(
                  alpha: .22),
            ),
          ),
          child:
          _buildMilestonePanelContent(
              context),
        ),
      ),
    );
  }

  Widget _buildMilestonePanelContent(
      BuildContext context) {
    const gold =
    Color(0xFFD4AF37);

    if (_milestonesLoading) {
      return const SizedBox(
        height: 70,
        child: Center(
          child: SizedBox(
            width: 17,
            height: 17,
            child:
            CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    if (_upcomingMilestones.isEmpty) {
      return Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Upcoming Coaching Milestones',
            maxLines: 1,
            overflow:
            TextOverflow.ellipsis,
            style:
            TextStyle(
              color: gold,
              fontSize: 11,
              fontWeight:
              FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            'No milestone has been defined for the upcoming Sunday.',
            style: TextStyle(
              color: Colors.white
                  .withValues(
                  alpha: .55),
              fontSize: 9.5,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: [
        const Text(
          'Upcoming Coaching Milestones',
          maxLines: 1,
          overflow:
          TextOverflow.ellipsis,
          style:
          TextStyle(
            color: gold,
            fontSize: 11,
            fontWeight:
            FontWeight.w800,
          ),
        ),
        const SizedBox(
          height: 4,
        ),
        for (final milestone
        in _upcomingMilestones)
          _buildMilestoneRow(
            context,
            milestone,
          ),
      ],
    );
  }

  // ============================================================
  // MILESTONE ROW
  // ============================================================

  Widget _buildMilestoneRow(
      BuildContext context,
      Map<String, Object?> milestone,
      ) {
    final scope =
    milestone['scope'];

    if (scope is! Map) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];

    _appendMilestoneSubject(
      context,
      children,
      scope,
      subjectCode: 'Phy',
      subjectName: 'Physics',
    );

    _appendMilestoneSubject(
      context,
      children,
      scope,
      subjectCode: 'Chem',
      subjectName: 'Chemistry',
    );

    _appendMilestoneSubject(
      context,
      children,
      scope,
      subjectCode: 'Bio',
      subjectName: 'Biology',
    );

    if (children.isEmpty) {
      return Padding(
        padding:
        const EdgeInsets.only(
          top: 4,
        ),
        child: Text(
          'No chapter scope defined.',
          style: TextStyle(
            color: Colors.white
                .withValues(
                alpha: .50),
            fontSize: 9.5,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,
      children: children,
    );
  }

  void _appendMilestoneSubject(
      BuildContext context,
      List<Widget> children,
      Map scope, {
        required String subjectCode,
        required String subjectName,
      }) {
    final entries =
    scope[subjectCode];

    if (entries is! List ||
        entries.isEmpty) {
      return;
    }

    final chapterNames =
    entries
        .whereType<Map>()
        .map(
          (entry) =>
      entry['chapter_name']
          ?.toString()
          .trim()
          .isNotEmpty ==
          true
          ? entry[
      'chapter_name']
          .toString()
          : entry[
      'chapter_code']
          ?.toString() ??
          '',
    )
        .where(
            (name) => name.isNotEmpty)
        .join(', ');

    if (chapterNames.isEmpty) {
      return;
    }

    children.add(
      _milestoneSubjectRow(
        context,
        subjectName,
        chapterNames,
      ),
    );
  }

  Widget _milestoneSubjectRow(
      BuildContext context,
      String subject,
      String chapters,
      ) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        vertical: 2.5,
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              subject,
              maxLines: 1,
              overflow:
              TextOverflow.ellipsis,
              style:
              const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              chapters,
              maxLines: 3,
              overflow:
              TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white
                    .withValues(
                    alpha: .55),
                fontSize: 9.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACTIVE WORKSPACE
  // ============================================================

  Widget _buildActiveWorkspaceSection(
      BuildContext context) {
    const gold =
    Color(0xFFD4AF37);

    String workspaceName;

    if (selectedNavigationIndex ==
        1) {
      workspaceName = 'Tasks';
    } else if (selectedNavigationIndex ==
        2) {
      workspaceName = 'Syllabus';
    } else if (selectedNavigationIndex ==
        4) {
      workspaceName = 'Lectures';
    } else if (selectedNavigationIndex ==
        5) {
      workspaceName = 'Milestones';
    } else {
      workspaceName = 'Dashboard';
    }

    return Container(
      decoration:
      BoxDecoration(
        gradient:
        const LinearGradient(
          colors: [
            Color(0xFF1B1B1B),
            Color(0xFF0C0C0C),
          ],
        ),
        borderRadius:
        BorderRadius.circular(11),
        border: Border.all(
          color:
          gold.withValues(
              alpha: .20),
        ),
      ),
      padding:
      const EdgeInsets.fromLTRB(
        9,
        8,
        9,
        9,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Active Workspace',
            maxLines: 1,
            overflow:
            TextOverflow.ellipsis,
            style:
            TextStyle(
              color: gold,
              fontSize: 11,
              fontWeight:
              FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Row(
            children: [
              const Icon(
                Icons
                    .dashboard_customize_outlined,
                size: 15,
                color: gold,
              ),
              const SizedBox(
                width: 5,
              ),
              Expanded(
                child: Text(
                  workspaceName,
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RESERVED RIGHT PANEL
  // ============================================================

  Widget _buildReservedRightPanelSection(
      BuildContext context) {
    const gold =
    Color(0xFFD4AF37);

    return Container(
      decoration:
      BoxDecoration(
        gradient:
        const LinearGradient(
          colors: [
            Color(0xFF181818),
            Color(0xFF0B0B0B),
          ],
        ),
        borderRadius:
        BorderRadius.circular(11),
        border: Border.all(
          color:
          gold.withValues(
              alpha: .16),
        ),
      ),
      padding:
      const EdgeInsets.fromLTRB(
        9,
        8,
        9,
        9,
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          const Text(
            'Reserved',
            maxLines: 1,
            overflow:
            TextOverflow.ellipsis,
            style:
            TextStyle(
              color: gold,
              fontSize: 11,
              fontWeight:
              FontWeight.w800,
            ),
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            'Additional contextual information will be added here later.',
            style: TextStyle(
              color: Colors.white
                  .withValues(
                  alpha: .45),
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }

  double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
      value?.toString() ?? '',
    ) ??
        0.0;
  }
}