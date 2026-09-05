//change pixel setting for Tanush-Tab
// Ctrl+F Tanush-Tab-Settings and change below settings.
// For virtual emulator - mainAxisExtent: 78,
// mainAxisExtent: 78,
// For  Tanu Tab SM 200 - mainAxisExtent: 90,
// mainAxisExtent: 90,

import 'package:flutter/material.dart';

import '../models/mo_task.dart';
import '../models/mo_task_group.dart';
import '../services/svc_milestones.dart';
import '../services/svc_task_generator_revision.dart';
import '../services/svc_syllabus_coverage.dart';
import '../services/svc_tasks_enquiry.dart';
import '../database/app_database.dart';
import '../widgets/wn_left_navigation.dart';
import 'ui_tasks.dart';
import 'ui_lectures.dart';
import 'ui_syllabus.dart';
import 'ui_milestones.dart';
import 'ui_milestones_mt.dart';
import 'ui_my_studies.dart';
import '../widgets/wd_topics_InProgress.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // ============================================================
  // SHELL STATE
  // ============================================================

  // bool leftExpanded = false;
  int selectedNavigationIndex = 0;
  String? selectedLectureSubjectCode;
  TaskGroup? _selectedTaskGroup;

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
  bool _milestoneRefreshing = false;

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
      //    int milestoneCount = 0;

      for (final row in rows) {
        final id = row['TaskID']?.toString().trim() ?? '';
        final description = row['TaskDescription']?.toString().trim() ?? '';

        final status =
            (row['TaskStatus']?.toString() ?? 'PENDING').toUpperCase();

        if (status == 'CANCELLED' || status == 'CANCELLED / NOT REQUIRED') {
          continue;
        }

        final searchableText = '$id $description'.toLowerCase();
        if (searchableText.contains('revision')) {
          revisionCount++;
        }
        //        if (id.startsWith('WE_')) { milestoneCount++;}
      }
      // NEW: milestone count from MilestoneCalendarSvc
      final milestoneSvc = MilestoneCalendarSvc(db);
      final milestoneCount =
          await milestoneSvc.getNextAvailableMilestoneTaskCount();

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
      //      int milestoneCount = 0;

      for (final row in rows) {
        final id = row['TaskID']?.toString().trim() ?? '';
        final description = row['TaskDescription']?.toString().trim() ?? '';
        final status =
            (row['TaskStatus']?.toString() ?? 'PENDING').toUpperCase();
        if (status == 'CANCELLED' || status == 'CANCELLED / NOT REQUIRED') {
          continue;
        }

        final searchableText = '$id $description'.toLowerCase();
        if (searchableText.contains('revision')) {
          revisionCount++;
        }
        //        if (id.startsWith('WE_')) { milestoneCount++; }
      }
      // ----------------------------------------------------------
      // MILESTONE TASK COUNT
      final milestoneSvc = MilestoneCalendarSvc(db);
      final milestoneCount =
          await milestoneSvc.getNextAvailableMilestoneTaskCount();
      // ----------------------------------------------------------
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

      final loaded = rows.map(_taskFromRow).whereType<Task>().toList();

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

    final description = row['TaskDescription']?.toString() ?? '';

    final dueText = row['TaskDueDate']?.toString();

    if (id == null || id.isEmpty || dueText == null) {
      return null;
    }

    final dueDate = DateTime.tryParse(dueText);

    if (dueDate == null) {
      return null;
    }

    final status =
        switch ((row['TaskStatus']?.toString() ?? 'PENDING').toUpperCase()) {
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
        return trimmed.substring('subject -'.length).trim();
      }
    }

    return 'Task';
  }

  // ============================================================
  // SYLLABUS COVERAGE
  // ============================================================

  Future<void> _loadSyllabusCoverage() async {
    try {
      final coverage = await _syllabusService.getOverallCoverage();

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
      final db = await AppDatabase.instance.database;
      final svc = MilestoneCalendarSvc(db);

      final rows = await svc.getUpcomingMilestonesForWidget(DateTime.now());

      // ============================================================
      // DEBUG — MILESTONE DATA RECEIVED FROM SERVICE
      // ============================================================
      debugPrint(
          '============================================================');
      debugPrint('[MILESTONE LOAD] Rows returned: ${rows.length}');

      for (final row in rows) {
        debugPrint('[MILESTONE LOAD] COMPLETE ROW: $row');
        debugPrint('[MILESTONE LOAD] Keys: ${row.keys.toList()}');
        debugPrint('[MILESTONE LOAD] milestone_name: ${row['milestone_name']}');
        debugPrint('[MILESTONE LOAD] MilestoneName: ${row['MilestoneName']}');
        debugPrint('[MILESTONE LOAD] milestone_date: ${row['milestone_date']}');
        debugPrint('[MILESTONE LOAD] MilestoneDate: ${row['MilestoneDate']}');
        debugPrint('[MILESTONE LOAD] date: ${row['date']}');
        debugPrint('[MILESTONE LOAD] Date: ${row['Date']}');
        debugPrint('[MILESTONE LOAD] scope: ${row['scope']}');
      }

      debugPrint(
          '============================================================');
      debugPrint(
          '============================================================');
      debugPrint('[MILESTONE LOAD] Rows returned: ${rows.length}');

      for (final milestone in rows) {
        debugPrint('[MILESTONE LOAD] Full milestone row: $milestone');

        final scope = milestone['scope'];

        if (scope is Map) {
          debugPrint('[MILESTONE LOAD] Scope: $scope');

          for (final subjectCode in ['Phy', 'Chem', 'Bio']) {
            final entries = scope[subjectCode];

            debugPrint(
              '[MILESTONE LOAD] $subjectCode entries: $entries',
            );

            if (entries is List) {
              for (final entry in entries) {
                if (entry is Map) {
                  debugPrint(
                    '[MILESTONE LOAD] '
                    '$subjectCode → '
                    'Subject: ${entry['subject_name']} | '
                    'Chapter: ${entry['chapter_name']} | '
                    'Chapter Code: ${entry['chapter_code']} | '
                    'Topic: ${entry['topic_name']}',
                  );
                }
              }
            }
          }
        } else {
          debugPrint('[MILESTONE LOAD] Scope is NOT a Map: $scope');
        }
      }

      debugPrint(
          '============================================================');

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

  Future<void> _refreshMilestones() async {
    if (_milestoneRefreshing) return;

    setState(() {
      _milestoneRefreshing = true;
    });

    try {
      final db = await AppDatabase.instance.database;
      final svc = MilestoneCalendarSvc(db);

      final rows = await svc.getUpcomingMilestonesForWidget(DateTime.now());

      if (!mounted) return;

      setState(() {
        _upcomingMilestones = rows;
        _milestonesLoading = false;
      });
    } catch (_) {
      // Keep the existing milestone data if refresh fails.
    } finally {
      if (mounted) {
        setState(() {
          _milestoneRefreshing = false;
        });
      }
    }
  }
  // ============================================================
  // NAVIGATION
  // ============================================================

  void _selectNavigation(int index) {
    setState(() {
      selectedNavigationIndex = index;
    });
    if (index == 0) {
      _refreshTaskCounters();
    }
  }

  // ============================================================
  // MILESTONE NAVIGATION
  // ============================================================

  void _openMilestoneCalendar() {
    setState(() {
      selectedNavigationIndex = 5;
      selectedLectureSubjectCode = null;
    });
  }

  // ============================================================
  // TASK NAVIGATION
  // ============================================================

  void _openTaskGroup(TaskGroup group) {
    setState(() {
      selectedNavigationIndex = 1;
      _selectedTaskGroup = group;
    });
  }

  void _openRevisionTasks() {
    setState(() {
      selectedNavigationIndex = 1;
    });
  }

  void _openMilestoneTasks() {
    setState(() {
      selectedNavigationIndex = 6;
      selectedLectureSubjectCode = null;
    });
  }
  // ============================================================
  // SYLLABUS NAVIGATION
  // ============================================================

  void _openSyllabus() {
    setState(() {
      selectedNavigationIndex = 2;
      selectedLectureSubjectCode = null;
    });
  }

  // ============================================================
  // LECTURE NAVIGATION
  // ============================================================

  void _openLectureSubject(String subjectCode) {
    setState(() {
      selectedLectureSubjectCode = subjectCode;
      selectedNavigationIndex = 4;
      // leftExpanded = false;
    });
  }

  // ============================================================
  // TASK UPDATE
  // ============================================================

  void _updateTask(Task updated) {
    _persistTaskUpdate(updated);
  }

  Future<void> _persistTaskUpdate(Task updated) async {
    final index = tasks.indexWhere((t) => t.id == updated.id);

    if (index == -1) return;

    final db = await AppDatabase.instance.database;

    final table = updated.id.startsWith('WE_')
        ? 'db_TaskLogWeekEnd'
        : 'db_TaskLogWeekDay';

    final now = DateTime.now().toIso8601String();

    final values = <String, Object?>{
      'TaskStatus': switch (updated.status) {
        TaskStatus.pending => 'PENDING',
        TaskStatus.started => 'IN_PROGRESS',
        TaskStatus.completed => 'COMPLETED',
        TaskStatus.cancelledNotRequired => 'CANCELLED / NOT REQUIRED',
      },
    };

    if (updated.status == TaskStatus.completed) {
      values['TaskCompletedDate'] = now;
      values['TaskCancelledDate'] = null;
    } else if (updated.status == TaskStatus.cancelledNotRequired) {
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
            // ------------------------------------------------------
            // LEFT NAVIGATION
            // ------------------------------------------------------
            SizedBox(
              width: 60,
              child: LeftNavigation(
                expanded: false,
                selectedIndex: selectedNavigationIndex,
                onSelected: _selectNavigation,
              ),
            ),

            // ------------------------------------------------------
            // MAIN WORKSPACE
            // ------------------------------------------------------
            Expanded(child: _buildMain(context)),

            // ------------------------------------------------------
            // FIXED RIGHT MILESTONE PANEL
            // ------------------------------------------------------
            SizedBox(
              width: 270,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
                child: _buildRightPanel(context),
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
        initialExpandedGroup: _selectedTaskGroup,
        onGenerateRevisionTasks: _generateRevisionTasks,
      );
    } else if (selectedNavigationIndex == 2) {
      content = const SyllabusScreen();
    } else if (selectedNavigationIndex == 3) {
      content = const MyStudyScreen();
    } else if (selectedNavigationIndex == 4) {
      content = LectureScreen(initialSubjectCode: selectedLectureSubjectCode);
    } else if (selectedNavigationIndex == 5) {
      content = const MilestoneCalendarScreen();
    } else if (selectedNavigationIndex == 6) {
      content = const MilestonesMtView();
    } else {
      content = _buildDashboardContent(context);
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildTopHeader(context),
          const SizedBox(height: 12),
          Expanded(child: content),
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
        return 'Calender MILESTONES';
      case 6:
        return 'Tasks MILESTONES';
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

    final targetDate = DateTime(2027, 5, 1);

    final todayOnly = DateTime(today.year, today.month, today.day);

    final days = targetDate.difference(todayOnly).inDays;

    return days < 0 ? 0 : days;
  }

  // ============================================================
  // TOP HEADER
  // ============================================================

  Widget _buildTopHeader(BuildContext context) {
    final daysLeft = _calculateDaysLeft();
    final screenTitle = _getCurrentScreenTitle();
    const gold = Color(0xFFD4AF37);
    const mutedGold = Color(0xFFB99A45);
    return Container(
      constraints: const BoxConstraints(minHeight: 70, maxHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF171717), Color(0xFF0D0D0D), Color(0xFF17120A)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: gold.withValues(alpha: .45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .55),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: gold.withValues(alpha: .08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          // ----------------------------------------------------
          // GREETING
          // ----------------------------------------------------
          Expanded(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '✦',
                  style: TextStyle(
                    color: gold,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Hello Dr. TANUSH',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // SYSTEM / DASHBOARD
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'EXAM PREPARATION SYSTEM',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: mutedGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    screenTitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: gold,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
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
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: _headerMetric(
                    label: 'DAYS LEFT',
                    value: '$daysLeft',
                    gold: gold,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: _headerMetric(
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
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .65),
              fontSize: 8,
              fontWeight: FontWeight.w700,
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
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DASHBOARD CONTENT
  Widget _buildDashboardContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Renamed method call here
          _buildStudiesSection(context),

          const SizedBox(height: 10),

          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildTasksSection(context)),
                const SizedBox(width: 10),
                Expanded(child: _buildSyllabusSection(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
// ============================================================
// CONSOLIDATED SUB-WIDGETS
// ============================================================

  Widget _buildConsolidatedLectures() {
    final lectureSubjects = [
      ('Phy', 'Physics', Icons.science_outlined),
      ('Chem', 'Chemistry', Icons.biotech_outlined),
      ('Bio', 'Biology', Icons.eco_outlined),
    ];
    return Row(
      children: [
        for (var i = 0; i < lectureSubjects.length; i++) ...[
          Expanded(
            child: InkWell(
              onTap: () => _openLectureSubject(lectureSubjects[i].$1),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(lectureSubjects[i].$3,
                        size: 18, color: const Color(0xFFD4AF37)),
                    const SizedBox(width: 6),
                    Text(
                      lectureSubjects[i].$2,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (i < lectureSubjects.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildConsolidatedTaskGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _compactTaskChip("Today's Tasks", _dueTodayCount, Icons.today_rounded,
            () => _openTaskGroup(TaskGroup.dueToday)),
        _compactTaskChip(
            "Past Due",
            _pastDueCount,
            Icons.pending_actions_rounded,
            () => _openTaskGroup(TaskGroup.pastDue)),
        _compactTaskChip(
            "In Progress",
            _inProgressCount,
            Icons.play_circle_outline_rounded,
            () => _openTaskGroup(TaskGroup.inProgress)),
        _compactTaskChip("Revision Tasks", _revisionTaskCount,
            Icons.replay_rounded, _openRevisionTasks),
        _compactTaskChip("Milestones", _milestoneTaskCount, Icons.flag_rounded,
            _openMilestoneTasks),
      ],
    );
  }

  Widget _compactTaskChip(
      String label, int count, IconData icon, VoidCallback onTap) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            (constraints.maxWidth - 16) / 3; // Fits 3 items per row neatly
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: itemWidth,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF292929)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, size: 16, color: const Color(0xFFD4AF37)),
                    Text(
                      '$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 10),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConsolidatedSyllabusProgress() {
    if (_syllabusLoading) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Color(0xFFD4AF37))));
    }

    // Fallback defaults if null
    final coveragePercent = _syllabusCoverage?['overall_percent'] as num? ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF292929)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Overall Progress',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              Text('${coveragePercent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (coveragePercent / 100).clamp(0.0, 1.0),
            backgroundColor: const Color(0xFF2C2C2C),
            color: const Color(0xFFD4AF37),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ),
    );
  }

// ============================================================
// CONSOLIDATED SINGLE-ROW MY STUDIES SECTION (1x4 HORIZONTAL)
// ============================================================

  Widget _buildStudiesSection(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    // Configuration for the 4 horizontal options
    final studyItems = [
      (
        'My Lectures',
        Icons.co_present_rounded, // Teacher/Teaching Icon
        const Color(0xFF2196F3), // Vivid Blue
        // () => _openLectureWorkspaceScreen(), // Navigates to Lecture Workspace
        () => _openLectureSubject('Phy'),
      ),
      (
        'Notes & Revisions',
        Icons.edit_note_rounded, // Open book with writing pen
        const Color(0xFF4CAF50), // Emerald Green
        () => _openNotesAndRevisions(),
      ),
      (
        'Books & Registers',
        Icons.menu_book_rounded, // Stacked Books & Registers
        const Color(0xFFFF9800), // Vibrant Amber/Orange
        () => _openBooksAndRegisters(),
      ),
      (
        'Goals & Studies',
        Icons.military_tech_rounded, // Achievement Goal Badge
        gold, // Metallic Gold Accent
        () => _openGoalsAndStudies(),
      ),
    ];

    return Material(
      color: Colors.transparent,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF202020), Color(0xFF0E0E0E)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: gold.withValues(alpha: .28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .45),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Frame Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'MY STUDIES',
                  style: TextStyle(
                    color: gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  'Workspace',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Single Row Layout (1x4 Grid)
            Row(
              children: [
                for (var i = 0; i < studyItems.length; i++) ...[
                  Expanded(child: _build3DStudyCardTile(studyItems[i])),
                  if (i < studyItems.length - 1) const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper tile widget generating 3D depth, glowing borders, and drop shadows
  Widget _build3DStudyCardTile((String, IconData, Color, VoidCallback) item) {
    final title = item.$1;
    final icon = item.$2;
    final color = item.$3;
    final onTap = item.$4;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          // Soft outer color glow matching the theme
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 6,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
          // Deep drop shadow for elevation
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF282828),
                  const Color(0xFF141414),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              // Color-matched glowing card border
              border: Border.all(
                color: color.withValues(alpha: 0.55),
                width: 1.2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Simulated 3D Layered Icon Stack
                SizedBox(
                  height: 24,
                  width: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Ambient Backlight Glow
                      Positioned(
                        top: 2,
                        child: Icon(
                          icon,
                          size: 20,
                          color: color.withValues(alpha: 0.4),
                        ),
                      ),
                      // Drop Shadow Layer
                      Positioned(
                        top: 1,
                        left: 1,
                        child: Icon(
                          icon,
                          size: 19,
                          color: Colors.black87,
                        ),
                      ),
                      // Vibrant Foreground Highlight Icon
                      Icon(
                        icon,
                        size: 19,
                        color: color,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 5),

                // Label Text
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openLectureWorkspaceScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const LectureScreen(), // Replace with your target screen widget class name
      ),
    );
  }

  void _openMyStudyScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            const MyStudyScreen(), // Replace with your target screen widget class name
      ),
    );
  }

  void _openNotesAndRevisions() {
    // Implement navigation for Notes & Revisions
  }

  void _openBooksAndRegisters() {
    // Implement navigation for Books & Registers
  }

  void _openGoalsAndStudies() {
    // Implement navigation for Goals & Studies
  }

  // Helper tile widget for study options
  Widget _buildStudyItemTile((String, IconData, Color, VoidCallback) item) {
    final title = item.$1;
    final icon = item.$2;
    final color = item.$3;
    final onTap = item.$4;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tile helper widget for each resource option
  Widget _buildLectureItemTile((String, IconData, Color, VoidCallback) item) {
    final title = item.$1;
    final icon = item.$2;
    final color = item.$3;
    final onTap = item.$4;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF171717),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ============================================================
  // CONSOLIDATED SINGLE-CARD TASKS SECTION ;
  // ============================================================

  Widget _buildTasksSection(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    return Material(
      color: Colors.transparent,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF202020), Color(0xFF0E0E0E)],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: gold.withValues(alpha: .28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .45),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Row with Refresh Action
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'TASKS SUMMARY',
                  style: TextStyle(
                    color: gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                InkWell(
                  onTap: _refreshTaskCounters,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Row(
                      children: const [
                        Text(
                          'Refresh',
                          style: TextStyle(
                            color: gold,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 3),
                        Icon(Icons.refresh_rounded, size: 12, color: gold),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_taskCountersLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: SizedBox(
                    height: 16,
                    width: 16,
                    child:
                        CircularProgressIndicator(color: gold, strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              // 1. Due Today Row
              _buildTaskRow(
                label: "Today's Tasks",
                count: _dueTodayCount,
                icon: Icons.today_rounded,
                color: const Color(0xFF4CAF50), // Green accent
                onTap: () => _openTaskGroup(TaskGroup.dueToday),
              ),
              const SizedBox(height: 5),

              // 2. Past Due Row
              _buildTaskRow(
                label: 'Past Due',
                count: _pastDueCount,
                icon: Icons.pending_actions_rounded,
                color: const Color(0xFFF44336), // Red accent
                onTap: () => _openTaskGroup(TaskGroup.pastDue),
              ),
              const SizedBox(height: 5),

              // 3. In Progress Row
              _buildTaskRow(
                label: 'In Progress',
                count: _inProgressCount,
                icon: Icons.play_circle_outline_rounded,
                color: const Color(0xFF2196F3), // Blue accent
                onTap: () => _openTaskGroup(TaskGroup.inProgress),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4.0),
                child:
                    Divider(color: Color(0xFF2E2E2E), height: 1, thickness: 1),
              ),

              // 4. Revision Tasks Row
              _buildTaskRow(
                label: 'Revision Tasks',
                count: _revisionTaskCount,
                icon: Icons.replay_rounded,
                color: gold, // Gold accent for Revisions
                isHighlight: true,
                onTap: _openRevisionTasks,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Row helper widget designed for interactive task metrics
  Widget _buildTaskRow({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isHighlight = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
        child: Row(
          children: [
            // Category Icon
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),

            // Task Category Name
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isHighlight ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),

            // Count Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: color.withValues(alpha: 0.4), width: 1),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Arrow Indicator
            const Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCards(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 7,
        mainAxisSpacing: 7,
        //Tanush-Tab-Settings -
        // For virtual emulator change mainAxisExtent to 78
        // For Tanush-Tab SM-200 change mainAxisExtent to 90
        // mainAxisExtent: 78,
        mainAxisExtent: 90,
      ),
      itemBuilder: (_, index) {
        switch (index) {
          case 0:
            return _taskStatCard(
              context,
              label: "Today's Tasks",
              count: _dueTodayCount,
              icon: Icons.today_rounded,
              onTap: () => _openTaskGroup(TaskGroup.dueToday),
            );

          case 1:
            return _taskStatCard(
              context,
              label: 'Past Due',
              count: _pastDueCount,
              icon: Icons.pending_actions_rounded,
              onTap: () => _openTaskGroup(TaskGroup.pastDue),
            );

          case 2:
            return _taskStatCard(
              context,
              label: 'In Progress',
              count: _inProgressCount,
              icon: Icons.play_circle_outline_rounded,
              onTap: () => _openTaskGroup(TaskGroup.inProgress),
            );

          case 3:
            return _taskStatCard(
              context,
              label: 'Revision Tasks',
              count: _revisionTaskCount,
              icon: Icons.replay_rounded,
              onTap: _openRevisionTasks,
            );

          case 4:
            return _taskStatCard(
              context,
              label: 'Refresh Counters',
              count: null,
              icon: _taskCountersLoading
                  ? Icons.sync_rounded
                  : Icons.refresh_rounded,
              onTap: _refreshTaskCounters,
              showChevron: false,
              showSpinner: _taskCountersLoading,
            );

          case 5:
            return _taskStatCard(
              context,
              label: 'Milestone Tasks',
              count: _milestoneTaskCount,
              icon: Icons.flag_rounded,
              onTap: _openMilestoneTasks,
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
    const gold = Color(0xFFD4AF37);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF242424), Color(0xFF0C0C0C)],
            ),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: gold.withValues(alpha: .30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .45),
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: .10),
                  shape: BoxShape.circle,
                  border: Border.all(color: gold.withValues(alpha: .22)),
                ),
                child: showSpinner
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : Icon(icon, color: gold, size: 15),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (count != null)
                      Text(
                        '$count',
                        maxLines: 1,
                        style: const TextStyle(
                          color: gold,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    else
                      const SizedBox(height: 20),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (showChevron) const SizedBox(width: 2),
              if (showChevron)
                Icon(
                  Icons.chevron_right_rounded,
                  size: 15,
                  color: Colors.white.withValues(alpha: .40),
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

// ============================================================
  // CONSOLIDATED SYLLABUS SECTION
  // ============================================================

  // ============================================================
  // CONSOLIDATED SYLLABUS SECTION
  // ============================================================

// ============================================================
  // CONSOLIDATED SINGLE-CARD SYLLABUS SECTION
  // ============================================================

  // ============================================================
  // CONSOLIDATED SINGLE-CARD SYLLABUS SECTION (WITH ICONS)
  // ============================================================

  // ============================================================
  // CONSOLIDATED SINGLE-CARD SYLLABUS SECTION (MATCHED SCALE)
  // ============================================================

// ============================================================
  // CONSOLIDATED SINGLE-CARD SYLLABUS SECTION (MATCHED SCALE)
  // ============================================================

  Widget _buildSyllabusSection(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    final Map<String, dynamic> coverage =
        (_syllabusCoverage ?? {}) as Map<String, dynamic>;

    final bioPercent = (coverage['bio_percent'] as num?)?.toDouble() ?? 0.0;
    final bioDone = (coverage['bio_completed'] as num?)?.toInt() ?? 0;
    final bioTotal = (coverage['bio_total'] as num?)?.toInt() ?? 0;

    final chemPercent = (coverage['chem_percent'] as num?)?.toDouble() ?? 0.0;
    final chemDone = (coverage['chem_completed'] as num?)?.toInt() ?? 0;
    final chemTotal = (coverage['chem_total'] as num?)?.toInt() ?? 0;

    final phyPercent = (coverage['phy_percent'] as num?)?.toDouble() ?? 0.0;
    final phyDone = (coverage['phy_completed'] as num?)?.toInt() ?? 0;
    final phyTotal = (coverage['phy_total'] as num?)?.toInt() ?? 0;

    final overallPercent =
        (coverage['overall_percent'] as num?)?.toDouble() ?? 0.0;
    final overallDone = bioDone + chemDone + phyDone;
    final overallTotal = bioTotal + chemTotal + phyTotal;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openSyllabus,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF202020), Color(0xFF0E0E0E)],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: gold.withValues(alpha: .28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .45),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween, // Distributes height evenly
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'SYLLABUS',
                    style: TextStyle(
                      color: gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Row(
                    children: const [
                      Text(
                        'Details',
                        style: TextStyle(
                          color: gold,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.arrow_forward_ios_rounded,
                          size: 9, color: gold),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (_syllabusLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          color: gold, strokeWidth: 2),
                    ),
                  ),
                )
              else ...[
                // Biology Row
                _buildSyllabusRow(
                  label: 'Biology',
                  icon: Icons.eco_outlined,
                  percent: bioPercent,
                  completed: bioDone,
                  total: bioTotal,
                  color: const Color(0xFF4CAF50),
                ),
                const SizedBox(height: 8), // Increased vertical spacing

                // Chemistry Row
                _buildSyllabusRow(
                  label: 'Chemistry',
                  icon: Icons.biotech_outlined,
                  percent: chemPercent,
                  completed: chemDone,
                  total: chemTotal,
                  color: const Color(0xFF2196F3),
                ),
                const SizedBox(height: 8), // Increased vertical spacing

                // Physics Row
                _buildSyllabusRow(
                  label: 'Physics',
                  icon: Icons.science_outlined,
                  percent: phyPercent,
                  completed: phyDone,
                  total: phyTotal,
                  color: const Color(0xFFFF9800),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6.0),
                  child: Divider(
                      color: Color(0xFF2E2E2E), height: 1, thickness: 1),
                ),

                // Overall Row
                _buildSyllabusRow(
                  label: 'Overall',
                  icon: Icons.auto_awesome,
                  percent: overallPercent,
                  completed: overallDone,
                  total: overallTotal,
                  color: gold,
                  isOverall: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyllabusRow({
    required String label,
    required IconData icon,
    required double percent,
    required int completed,
    required int total,
    required Color color,
    bool isOverall = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: TextStyle(
              color: isOverall ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: isOverall ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 7, // Slightly thicker progress bar
              backgroundColor: const Color(0xFF1B1B1B),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 34,
          child: Text(
            '${percent.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: isOverall ? color : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            ' ($completed/$total)',
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 11,
            ),
          ),
        ),
      ],
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
    const gold = Color(0xFFD4AF37);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF151515), Color(0xFF0B0B0B)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .55),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: gold,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }

  // ============================================================
  // RIGHT PANEL
  // ============================================================
  Widget _buildRightPanel(BuildContext context) {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF121212), Color(0xFF080808)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: .25),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUpcomingSundaySection(context),
            const SizedBox(height: 9),
            _buildActiveWorkspaceSection(context),
            const SizedBox(height: 9),
            _buildReservedRightPanelSection(context),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UPCOMING SUNDAY MILESTONES
  // ============================================================
  Widget _buildUpcomingSundaySection(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1C1C1C), Color(0xFF0B0B0B)],
          ),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: gold.withValues(alpha: .22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Upcoming Coaching Milestones',
                    style: TextStyle(
                      color: gold,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

                // Refresh button
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: 'Refresh milestones',
                    onPressed: _milestoneRefreshing ? null : _refreshMilestones,
                    icon: _milestoneRefreshing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                            ),
                          )
                        : const Icon(
                            Icons.refresh_rounded,
                            size: 18,
                          ),
                    color: gold,
                  ),
                ),
              ],
            ),

            // Milestone content/card area
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _openMilestoneCalendar,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _buildMilestonePanelContent(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestonePanelContent(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    if (_milestonesLoading) {
      return const SizedBox(
        height: 70,
        child: Center(
          child: SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    if (_upcomingMilestones.isEmpty) {
      return Text(
        'No upcoming milestone found.',
        style: TextStyle(
          color: Colors.white.withValues(alpha: .55),
          fontSize: 9.5,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ..._upcomingMilestones.map(
          (milestone) => _buildMilestoneRow(
            context,
            milestone,
          ),
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
    const gold = Color(0xFFD4AF37);

    final scope = milestone['scope'];

    debugPrint('============================================================');
    debugPrint('[MILESTONE WIDGET] Building milestone row');
    debugPrint('[MILESTONE WIDGET] Milestone: ${milestone['milestone_name']}');
    debugPrint('[MILESTONE WIDGET] Scope: $scope');

    if (scope is! Map) {
      debugPrint('[MILESTONE WIDGET] ERROR: scope is not a Map');
      debugPrint(
          '============================================================');
      return const SizedBox.shrink();
    }

    final rawDate = milestone['milestone_date'] ??
        milestone['MilestoneDate'] ??
        milestone['date'] ??
        milestone['Date'];

    String dateText = '';

    if (rawDate != null) {
      final date = DateTime.tryParse(rawDate.toString());

      if (date != null) {
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];

        const weekdays = [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ];

        dateText = '${weekdays[date.weekday - 1]}, '
            '${date.day.toString().padLeft(2, '0')}-'
            '${months[date.month - 1]}-${date.year}';
      }
    }

    final milestoneName = milestone['milestone_name']?.toString() ??
        milestone['MilestoneName']?.toString() ??
        milestone['name']?.toString() ??
        '';

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

    debugPrint(
      '[MILESTONE WIDGET] Subject rows generated: ${children.length}',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dateText.isNotEmpty || milestoneName.isNotEmpty)
            Text(
              [
                if (dateText.isNotEmpty) dateText,
                if (milestoneName.isNotEmpty) milestoneName,
              ].join(' • '),
              softWrap: true,
              style: const TextStyle(
                color: gold,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          const SizedBox(height: 5),
          if (children.isEmpty)
            Text(
              'No chapter scope defined.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .50),
                fontSize: 9.5,
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }

  void _appendMilestoneSubject(
    BuildContext context,
    List<Widget> children,
    Map scope, {
    required String subjectCode,
    required String subjectName,
  }) {
    final entries = scope[subjectCode];

    if (entries is! List || entries.isEmpty) {
      return;
    }

    final chapterNames = entries
        .whereType<Map>()
        .map(
          (entry) {
            final chapterName = entry['chapter_name']?.toString().trim();

            if (chapterName != null && chapterName.isNotEmpty) {
              return chapterName;
            }

            return entry['chapter_code']?.toString().trim() ?? '';
          },
        )
        .where((name) => name.isNotEmpty)
        .toList();

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
    List<String> chapters,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              subject,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final chapter in chapters)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '• $chapter',
                      softWrap: true,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .55),
                        fontSize: 9.5,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACTIVE WORKSPACE
  // ============================================================

  Widget _buildActiveWorkspaceSection(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    String workspaceName;

    if (selectedNavigationIndex == 1) {
      workspaceName = 'Tasks';
    } else if (selectedNavigationIndex == 2) {
      workspaceName = 'Syllabus';
    } else if (selectedNavigationIndex == 4) {
      workspaceName = 'Lectures';
    } else if (selectedNavigationIndex == 5) {
      workspaceName = 'Calender Milestones';
    } else if (selectedNavigationIndex == 6) {
      workspaceName = 'Tasks Milestones ';
    } else {
      workspaceName = 'Dashboard';
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B1B1B), Color(0xFF0C0C0C)],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: gold.withValues(alpha: .20)),
      ),
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active Workspace',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: gold,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.dashboard_customize_outlined,
                size: 15,
                color: gold,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  workspaceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
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

  Widget _buildReservedRightPanelSection(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF181818), Color(0xFF0B0B0B)],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: gold.withValues(alpha: .16)),
      ),
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reserved',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: gold,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Additional contextual information will be added here later.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: .45),
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

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
