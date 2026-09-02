import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/svc_status_chapters.dart';
import '../services/svc_milestones.dart';
import '../services/svc_task_generator_mt.dart';
import '../models/mo_task.dart';
import '../services/svc_Status_Task_Activity.dart';

/// Milestone calendar workspace.
///
/// UI:
/// - Borderless View / New Milestone tabs
/// - Compact CMT / PMT / Date row
/// - Physics / Chemistry / Biology adjacent tabs
/// - Two fixed chapter boxes, 5 chapters each
/// - Horizontal swipe moves both chapter boxes together
/// - Primary color used consistently for selected states
///
/// Database writes remain inside MilestoneCalendarSvc.
class MilestoneCalendarScreen extends StatefulWidget {
  const MilestoneCalendarScreen({
    super.key,
    this.initialDate,
    this.initialView = MilestoneCalendarView.view,
    this.onReturnToDashboard,
    this.onCmtTaskGenerationStarted,
    this.onCmtTasksGenerated,
    this.onCmtTaskGenerationFailed,
    this.onTaskUpdated,
    this.onTaskStateChanged,
  });

  final DateTime? initialDate;
  final MilestoneCalendarView initialView;

  final VoidCallback? onReturnToDashboard;

  final ValueChanged<DateTime>? onCmtTaskGenerationStarted;

  final void Function(DateTime, List<Map<String, Object?>>)?
      onCmtTasksGenerated;

  final void Function(DateTime, Object)? onCmtTaskGenerationFailed;

  final ValueChanged<Task>? onTaskUpdated;
  final ValueChanged<Task>? onTaskStateChanged;

  @override
  State<MilestoneCalendarScreen> createState() =>
      _MilestoneCalendarScreenState();
}

enum MilestoneCalendarView { view, set, tasks }

class _MilestoneCalendarScreenState extends State<MilestoneCalendarScreen> {
  static const List<_SubjectInfo> _subjects = [
    _SubjectInfo('PHY', 'Phy', 'Physics', Icons.bolt_outlined),
    _SubjectInfo('CHEM', 'Chem', 'Chemistry', Icons.science_outlined),
    _SubjectInfo('BIO', 'Bio', 'Biology', Icons.eco_outlined),
  ];

  // Temporary test flag.
  // Keep true while milestone task generation is required.
  static const bool _createTasksAfterMilestoneSave = true;

  // ---------------------------------------------------------------------------
  // UI ONLY
  // ---------------------------------------------------------------------------

  static const int _chaptersPerBox = 5;
  // static const int _boxesPerPage = 2;
  static const int _chaptersPerSwipe = 10;

  int _chapterPage = 0;

  MilestoneCalendarView _view = MilestoneCalendarView.view;

  DateTime _selectedDate = MilestoneCalendarSvc.nextSunday(DateTime.now());

  String _milestoneType = 'CMT';

  // Selected subject tab.
  String _expandedSubject = 'PHY';

  final Set<String> _expandedRanges = {};

  final Set<String> _selectedPhy = {};
  final Set<String> _selectedChem = {};
  final Set<String> _selectedBio = {};

  final Set<String> _pmtLockedPhy = {};
  final Set<String> _pmtLockedChem = {};
  final Set<String> _pmtLockedBio = {};

  List<_ChapterOption> _phyChapters = const [];
  List<_ChapterOption> _chemChapters = const [];
  List<_ChapterOption> _bioChapters = const [];

  List<Map<String, Object?>> _milestones = const [];

  Map<String, Object?>? _expandedMilestone;
  Map<String, Object?>? _existingMilestone;

  String? _scopeMessage;

  bool _scopeChangePending = false;
  bool _loading = true;
  bool _saving = false;

  String? _error;

  MilestoneCalendarSvc? _svc;

  // ---------------------------------------------------------------------------
  // MILESTONE TASKS
  // ---------------------------------------------------------------------------
  bool _milestoneTasksLoading = false;
  bool _milestoneTasksCreationRequired = false;
  //bool _milestoneTasksCreationRequired;
  List<Map<String, Object?>> _openMilestoneTasks = const [];
  String? _milestoneTasksError;
  final Map<String, bool> _milestoneTaskExpanded = {};
  String? _expandedTaskId;
  Future<void> Function()? _commitExpandedTask;

  @override
  void initState() {
    super.initState();

    _view = widget.initialView;
    _selectedDate = _normaliseInitialDate(widget.initialDate);

    _load();
  }

  DateTime _normaliseInitialDate(DateTime? suppliedDate) {
    if (suppliedDate == null) {
      return MilestoneCalendarSvc.nextSunday(DateTime.now());
    }

    final date = _dateOnly(suppliedDate);

    if (date.weekday == DateTime.sunday) {
      return date;
    }

    return MilestoneCalendarSvc.nextSunday(date);
  }

  Future<void> _prepareNewMilestoneEntry() async {
    final svc = _svc;

    if (svc == null || _saving) return;

    final today = _dateOnly(DateTime.now());
    final lastDate = today.add(const Duration(days: 730));

    final occupiedDates = await svc.getOccupiedMilestoneDates(
      from: today,
      to: lastDate,
    );

    final nextAvailableSunday = await _getNextAvailableSunday(
      from: today,
      occupiedDates: occupiedDates,
    );

    if (!mounted) return;

    setState(() {
      _view = MilestoneCalendarView.set;

      _selectedDate = nextAvailableSunday;

      // New milestone defaults to CMT.
      _milestoneType = 'CMT';

      _existingMilestone = null;
      _expandedMilestone = null;

      _scopeMessage = null;
      _scopeChangePending = false;

      _clearSelections();

      _expandedSubject = 'PHY';
      _expandedRanges.clear();

      // UI only.
      _chapterPage = 0;

      _error = null;
    });
  }

  Future<DateTime> _findNextAvailableSunday() async {
    final svc = _svc;

    if (svc == null) {
      return MilestoneCalendarSvc.nextSunday(DateTime.now());
    }

    final today = _dateOnly(DateTime.now());
    final lastDate = today.add(const Duration(days: 730));

    final occupiedDates = await svc.getOccupiedMilestoneDates(
      from: today,
      to: lastDate,
    );

    var candidate = MilestoneCalendarSvc.nextSunday(today);

    while (occupiedDates.contains(MilestoneCalendarSvc.formatDate(candidate))) {
      candidate = candidate.add(const Duration(days: 7));
    }

    return candidate;
  }

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.database;

      final svc = MilestoneCalendarSvc(db);

      _svc = svc;

      await _loadChapterOptions(db);

      if (widget.initialDate == null &&
          widget.initialView == MilestoneCalendarView.set) {
        _selectedDate = await _findNextAvailableSunday();
      }

      final milestones = await svc.getUpcomingMilestones(limit: 100);

      await _loadExistingMilestone();

      if (!mounted) return;

      setState(() {
        _milestones = milestones;
        _loading = false;
        _error = null;
      });

      if (widget.initialView == MilestoneCalendarView.tasks) {
        await _loadMilestoneTasksView();
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<DateTime> _getNextAvailableSundayForType(String milestoneType) async {
    final svc = _svc;

    if (svc == null) {
      return MilestoneCalendarSvc.nextSunday(DateTime.now());
    }

    final today = _dateOnly(DateTime.now());
    final lastDate = today.add(const Duration(days: 730));

    final occupiedDates = <String>{};

    final milestones = await svc.getMilestonesInRange(
      from: today,
      to: lastDate,
    );

    for (final row in milestones) {
      final type = row[MilestoneCalendarSvc.colType]?.toString();

      if (type?.toUpperCase() != milestoneType.toUpperCase()) {
        continue;
      }

      final date = row[MilestoneCalendarSvc.colDate]?.toString();

      if (date != null && date.isNotEmpty) {
        occupiedDates.add(date);
      }
    }

    return _getNextAvailableSunday(from: today, occupiedDates: occupiedDates);
  }

  Future<DateTime> _getNextAvailableSunday({
    required DateTime from,
    required Set<String> occupiedDates,
  }) async {
    var date = MilestoneCalendarSvc.nextSunday(from);

    while (occupiedDates.contains(MilestoneCalendarSvc.formatDate(date))) {
      date = date.add(const Duration(days: 7));
    }

    return date;
  }

  Future<void> _loadChapterOptions(dynamic db) async {
    Future<List<_ChapterOption>> loadSubject(String subjectCode) async {
      final rows = await db.query(
        'db_SyllabusMaster',
        columns: ['chapter_code', 'chapter_name'],
        where: 'UPPER(subject_code) = ?',
        whereArgs: [subjectCode.toUpperCase()],
        orderBy: 'display_order ASC, chapter_code ASC',
      );

      final chapters = <_ChapterOption>[];
      final seen = <String>{};

      for (final row in rows) {
        final code = row['chapter_code']?.toString().trim() ?? '';

        final name = row['chapter_name']?.toString().trim() ?? '';

        if (code.isEmpty) continue;

        final normalisedCode = code.toUpperCase();

        if (!seen.add(normalisedCode)) {
          continue;
        }

        chapters.add(_ChapterOption(code, name.isEmpty ? code : name));
      }

      return chapters;
    }

    _phyChapters = await loadSubject('PHY');
    _chemChapters = await loadSubject('CHEM');
    _bioChapters = await loadSubject('BIO');
  }

  Future<void> _loadExistingMilestone() async {
    final svc = _svc;

    if (svc == null) return;

    final row = await svc.getMilestone(
      milestoneType: _milestoneType,
      date: _selectedDate,
    );

    _existingMilestone = row;

    _scopeChangePending = row != null;

    _scopeMessage =
        row == null ? null : 'Existing milestone found for this Sunday.';

    _loadSelectionsFromMilestone(row);
  }

  void _loadSelectionsFromMilestone(Map<String, Object?>? row) {
    _selectedPhy
      ..clear()
      ..addAll(
        MilestoneCalendarSvc.splitCodes(
          row?[MilestoneCalendarSvc.colPhy]?.toString(),
        ),
      );

    _selectedChem
      ..clear()
      ..addAll(
        MilestoneCalendarSvc.splitCodes(
          row?[MilestoneCalendarSvc.colChem]?.toString(),
        ),
      );

    _selectedBio
      ..clear()
      ..addAll(
        MilestoneCalendarSvc.splitCodes(
          row?[MilestoneCalendarSvc.colBio]?.toString(),
        ),
      );
  }

  // ===========================================================================
  // PMT CHAPTER PRESELECTION
  // ===========================================================================
  //
  // PMT scope is initially based on chapters currently InProgress in
  // db_StatusChapters.
  //
  // StatusChapterService returns the complete StatusChapter records.
  // The UI only extracts SubjectChapterCode and uses the chapter portion
  // to preselect the corresponding syllabus chapters.
  //
  // Example:
  //
  //     PHY-1   -> 1
  //     PHY-4   -> 4
  //     CHEM-2  -> 2
  //     BIO-7   -> 7
  //
  // The user can still manually add/remove chapters after preselection.
  // ===========================================================================

  Future<void> _preselectPmtInProgressChapters() async {
    if (_milestoneType.toUpperCase() != 'PMT') {
      return;
    }

    final statusService = StatusChapterService.instance;

    final phyRows = await statusService.getInProgressChaptersBySubject('PHY');

    final chemRows = await statusService.getInProgressChaptersBySubject('CHEM');

    final bioRows = await statusService.getInProgressChaptersBySubject('BIO');

    final phy = <String>{};
    final chem = <String>{};
    final bio = <String>{};

    void addChapterCodes(List<Map<String, Object?>> rows, Set<String> target) {
      for (final row in rows) {
        final subjectChapterCode =
            row['SubjectChapterCode']?.toString().trim() ?? '';

        if (subjectChapterCode.isEmpty) {
          continue;
        }

        final separatorIndex = subjectChapterCode.indexOf('-');

        if (separatorIndex < 0) {
          continue;
        }

        final chapterCode =
            subjectChapterCode.substring(separatorIndex + 1).trim();

        if (chapterCode.isNotEmpty) {
          target.add(chapterCode);
        }
      }
    }

    addChapterCodes(phyRows, phy);
    addChapterCodes(chemRows, chem);
    addChapterCodes(bioRows, bio);

    if (!mounted) return;

    setState(() {
      _selectedPhy
        ..clear()
        ..addAll(phy);

      _selectedChem
        ..clear()
        ..addAll(chem);

      _selectedBio
        ..clear()
        ..addAll(bio);

      _chapterPage = 0;
    });
  }

  Future<void> _pickSunday() async {
    if (_saving) return;

    final today = _dateOnly(DateTime.now());
    final lastDate = today.add(const Duration(days: 730));

    final svc = _svc;

    if (svc == null) return;

    final occupiedDates = await svc.getOccupiedMilestoneDates(
      from: today,
      to: lastDate,
    );

    if (!mounted) return;

    DateTime initialDate = today;

    while (initialDate.weekday != DateTime.sunday) {
      initialDate = initialDate.add(const Duration(days: 1));
    }

    while (occupiedDates.contains(
      MilestoneCalendarSvc.formatDate(initialDate),
    )) {
      initialDate = initialDate.add(const Duration(days: 7));
    }

    if (initialDate.isAfter(lastDate)) {
      initialDate = MilestoneCalendarSvc.nextSunday(today);
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: lastDate,
      selectableDayPredicate: (date) {
        if (date.weekday != DateTime.sunday) {
          return false;
        }

        final dateKey = MilestoneCalendarSvc.formatDate(date);

        return !occupiedDates.contains(dateKey);
      },
      helpText: 'Select Milestone Sunday',
    );

    if (picked == null || !mounted) return;

    setState(() {
      _selectedDate = _dateOnly(picked);

      _existingMilestone = null;
      _scopeMessage = null;
      _scopeChangePending = false;

      _clearSelections();

      _expandedRanges.clear();

      // UI only.
      _chapterPage = 0;
    });

    await _loadExistingMilestone();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onTypeChanged(String type) async {
    if (_saving || type == _milestoneType) {
      return;
    }

    setState(() {
      _milestoneType = type;

      _existingMilestone = null;
      _expandedMilestone = null;
      _scopeMessage = null;
      _scopeChangePending = false;

      _clearSelections();

      _expandedRanges.clear();

      // UI only.
      _chapterPage = 0;
    });

    // PMT automatically starts with currently InProgress chapters.
    if (type.toUpperCase() == 'PMT') {
      await _preselectPmtInProgressChapters();
    }
  }

  void _clearSelections() {
    _selectedPhy.clear();
    _selectedChem.clear();
    _selectedBio.clear();
  }

  Future<void> _saveMilestone() async {
    if (_saving) return;

    final svc = _svc;

    if (svc == null) return;

    if (_selectedDate.weekday != DateTime.sunday) {
      _showMessage('Milestone date must be a Sunday.');
      return;
    }

    final existing = await svc.getAnyMilestoneForDate(_selectedDate);

    if (existing != null && !_scopeChangePending) {
      setState(() {
        _existingMilestone = existing;

        _scopeMessage =
            'Existing milestone found. Do you want to change its scope?';

        _scopeChangePending = true;
      });

      return;
    }

    final missingSubjects = <String>[];

    if (_selectedPhy.isEmpty) {
      missingSubjects.add('Physics');
    }

    if (_selectedChem.isEmpty) {
      missingSubjects.add('Chemistry');
    }

    if (_selectedBio.isEmpty) {
      missingSubjects.add('Biology');
    }

    if (missingSubjects.isNotEmpty) {
      final proceed = await _confirmMissingSubjects(missingSubjects);

      if (!proceed) return;
    }

    await _persistMilestone();
  }

  Future<bool> _confirmMissingSubjects(List<String> missingSubjects) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No Chapter Selected'),
        content: Text(
          '${missingSubjects.join(', ')} '
          '${missingSubjects.length == 1 ? 'has' : 'have'} '
          'no chapter selected.\n\n'
          'Are you sure you want to continue without '
          '${missingSubjects.length == 1 ? 'it' : 'them'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _persistMilestone() async {
    final svc = _svc;

    if (svc == null || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    bool progressDialogShown = false;

    try {
      // 1. Save milestone.
      await svc.saveMilestone(
        milestoneType: _milestoneType,
        date: _selectedDate,
        phyChapters: _selectedPhy.join(','),
        chemChapters: _selectedChem.join(','),
        bioChapters: _selectedBio.join(','),
      );

      // 2. Generate tasks.
      Map<String, int> taskResults = const {};

      if (_createTasksAfterMilestoneSave) {
        if (!mounted) return;

        progressDialogShown = true;

        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            title: Text('Task Creation'),
            content: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 14),
                Expanded(child: Text('Task creation is in progress...')),
              ],
            ),
          ),
        );

        taskResults = await _generateTasksForSavedMilestone();
      }

      if (!mounted) return;

      if (progressDialogShown) {
        Navigator.of(context, rootNavigator: true).pop();

        progressDialogShown = false;
      }

      final milestones = await svc.getUpcomingMilestones(limit: 100);

      if (!mounted) return;

      final savedType = _milestoneType;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('$savedType Milestone'),
          content: _createTasksAfterMilestoneSave
              ? Text(_buildTaskGenerationMessage(taskResults))
              : const Text('Milestone created successfully.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;

      final today = _dateOnly(DateTime.now());
      final lastDate = today.add(const Duration(days: 730));

      final occupiedDates = await svc.getOccupiedMilestoneDates(
        from: today,
        to: lastDate,
      );

      final nextAvailableSunday = await _getNextAvailableSunday(
        from: today,
        occupiedDates: occupiedDates,
      );

      if (!mounted) return;

      setState(() {
        _milestones = milestones;

        _selectedDate = nextAvailableSunday;

        _existingMilestone = null;
        _expandedMilestone = null;

        _scopeMessage = null;
        _scopeChangePending = false;

        _clearSelections();

        _expandedSubject = 'PHY';
        _expandedRanges.clear();

        // UI only.
        _chapterPage = 0;

        _saving = false;

        _view = MilestoneCalendarView.view;
      });
    } catch (error) {
      if (progressDialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();

        progressDialogShown = false;
      }

      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = error.toString();
      });

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Milestone Save / Task Creation Failed'),
          content: Text(
            'The milestone may have been saved, '
            'but an error occurred during processing.'
            '\n\n$error',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // ===========================================================================
  // TASK GENERATION
  // ===========================================================================
  //
  // Both CMT and PMT now go through MtTaskGenerator.
  //
  // The UI passes the selected milestone type and date.
  // MtTaskGenerator is responsible for deciding what to generate.
  // ===========================================================================

  Future<Map<String, int>> _generateTasksForSavedMilestone() async {
    final db = await AppDatabase.instance.database;

    final generator = MtTaskGenerator(db: db);

    return generator.generateMilestoneTasks(
      mtType: _milestoneType,
      milestoneDate: _selectedDate,
    );
  }

  String _buildTaskGenerationMessage(Map<String, int> results) {
    String statusText(String subject, int status) {
      switch (status) {
        case 1:
          return '$subject: Tasks Created';

        case 2:
          return '$subject: Partially Created';

        case 0:
        default:
          return '$subject: Not Created';
      }
    }

    final commonTaskStatus = results['PCB'] ?? 0;

    final commonTaskText = commonTaskStatus == 1
        ? 'Milestone Test, Analysis and Improvement tasks: Generated'
        : 'Milestone Test, Analysis and Improvement tasks: Not Generated';

    return [
      statusText('Physics', results['PHY'] ?? 0),
      statusText('Chemistry', results['CHEM'] ?? 0),
      statusText('Biology', results['BIO'] ?? 0),
      commonTaskText,
    ].join('\n');
  }

  void _openEditScope() {
    final row = _expandedMilestone;

    if (row == null) return;

    final rawDate = row[MilestoneCalendarSvc.colDate]?.toString();

    final parsedDate = rawDate == null ? null : DateTime.tryParse(rawDate);

    setState(() {
      if (parsedDate != null) {
        _selectedDate = _dateOnly(parsedDate);
      }

      _milestoneType = row[MilestoneCalendarSvc.colType]?.toString() ?? 'CMT';

      _loadSelectionsFromMilestone(row);

      _scopeMessage =
          'Existing scope loaded. Tap chapters to select or unselect.';

      _scopeChangePending = true;

      _expandedRanges.clear();

      // UI only.
      _chapterPage = 0;

      _view = MilestoneCalendarView.set;
    });
  }

  bool _sameMilestone(
    Map<String, Object?>? first,
    Map<String, Object?> second,
  ) {
    if (first == null) return false;

    final firstDate = first[MilestoneCalendarSvc.colDate]?.toString();

    final secondDate = second[MilestoneCalendarSvc.colDate]?.toString();

    final firstType = first[MilestoneCalendarSvc.colType]?.toString();

    final secondType = second[MilestoneCalendarSvc.colType]?.toString();

    return firstDate == secondDate && firstType == secondType;
  }

  void _openMilestone(Map<String, Object?> row) {
    setState(() {
      _expandedMilestone = _sameMilestone(_expandedMilestone, row) ? null : row;
    });
  }

  void _toggleSubject(String code) {
    setState(() {
      if (_expandedSubject == code) {
        return;
      }

      _expandedSubject = code;

      _expandedRanges.removeWhere((key) => !key.startsWith('$code:'));

      // UI only.
      _chapterPage = 0;
    });
  }

  void _toggleRange(String subjectCode, int start) {
    final key = '$subjectCode:$start';

    setState(() {
      if (_expandedRanges.contains(key)) {
        _expandedRanges.remove(key);
      } else {
        _expandedRanges.add(key);
      }
    });
  }

  void _toggleChapter(String subjectCode, String chapterCode) {
    final selected = _selectionFor(subjectCode);

    setState(() {
      if (selected.contains(chapterCode)) {
        selected.remove(chapterCode);
      } else {
        selected.add(chapterCode);
      }
    });
  }

  Set<String> _selectionFor(String subjectCode) {
    switch (subjectCode) {
      case 'PHY':
        return _selectedPhy;

      case 'CHEM':
        return _selectedChem;

      case 'BIO':
        return _selectedBio;

      default:
        return _selectedBio;
    }
  }

  Set<String> _lockedSelectionFor(String subjectCode) {
    switch (subjectCode) {
      case 'PHY':
        return _pmtLockedPhy;

      case 'CHEM':
        return _pmtLockedChem;

      case 'BIO':
        return _pmtLockedBio;

      default:
        return {};
    }
  }

  List<_ChapterOption> _chaptersFor(String subjectCode) {
    switch (subjectCode) {
      case 'PHY':
        return _phyChapters;

      case 'CHEM':
        return _chemChapters;

      case 'BIO':
        return _bioChapters;

      default:
        return const [];
    }
  }

  int? _chapterNumber(String code) {
    final match = RegExp(r'(\d+)').firstMatch(code);

    if (match == null) return null;

    return int.tryParse(match.group(1)!);
  }

  List<_ChapterOption> _rangeChapters(String subjectCode, int start) {
    return _chaptersFor(subjectCode).where((chapter) {
      final number = _chapterNumber(chapter.code);

      return number != null && number >= start && number <= start + 9;
    }).toList();
  }

  String _rangeLabel(int start) {
    return 'Chapter $start-${start + 9}';
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _dateText(DateTime date) {
    return MilestoneCalendarSvc.formatDisplayDate(date);
  }

  String _typeLabel(String type) {
    switch (type.toUpperCase()) {
      case 'CMT':
        return 'Coaching Milestone';

      case 'PMT':
        return 'Personal Milestone';

      default:
        return type;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ===========================================================================
  // UI
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModeSelector(context),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _buildError(context)
          else
            switch (_view) {
              MilestoneCalendarView.view => _buildView(context),
              MilestoneCalendarView.set => _buildSet(context),
              MilestoneCalendarView.tasks => _buildMilestoneTasks(context),
            },
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // COMMON UI SEGMENT BORDER
  // ---------------------------------------------------------------------------

  BoxDecoration _segmentDecoration({
    required BuildContext context,
    required bool selected,
    double radius = 8,
  }) {
    final colors = Theme.of(context).colorScheme;

    return BoxDecoration(
      color: selected ? colors.primary : Colors.transparent,
      border: Border.all(color: Colors.black, width: 0.7),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  // ---------------------------------------------------------------------------
  // VIEW / NEW MILESTONE TABS
  // ---------------------------------------------------------------------------

  Widget _buildModeSelector(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeButton(
              context,
              'View Milestones',
              Icons.event_available_outlined,
              MilestoneCalendarView.view,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _modeButton(
              context,
              'New Milestone',
              Icons.add_outlined,
              MilestoneCalendarView.set,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _modeButton(
              context,
              'Milestone Tasks',
              Icons.task_alt_outlined,
              MilestoneCalendarView.tasks,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(
    BuildContext context,
    String label,
    IconData icon,
    MilestoneCalendarView value,
  ) {
    final selected = _view == value;

    final colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _saving
            ? null
            : () async {
                if (value == MilestoneCalendarView.set) {
                  await _prepareNewMilestoneEntry();
                } else if (value == MilestoneCalendarView.tasks) {
                  if (!mounted) return;
                  setState(() {
                    _view = value;
                  });
                  await _loadMilestoneTasksView();
                } else {
                  if (!mounted) return;

                  setState(() {
                    _view = value;
                  });
                }
              },
        child: Container(
          height: double.infinity,
          decoration: _segmentDecoration(
            context: context,
            selected: selected,
            radius: 8,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color:
                        selected ? colors.onPrimary : colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VIEW MILESTONES
  // ---------------------------------------------------------------------------

  Widget _buildView(BuildContext context) {
    if (_milestones.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              Icons.event_busy_outlined,
              size: 34,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            const Text(
              'No upcoming milestones are set.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Use New Milestone to create one.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 7),
            child: Text(
              'Upcoming Milestones',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (var i = 0; i < _milestones.length; i++) ...[
            _milestoneRow(context, _milestones[i]),
            if (i < _milestones.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _milestoneRow(BuildContext context, Map<String, Object?> row) {
    final colors = Theme.of(context).colorScheme;

    final rawDate = row[MilestoneCalendarSvc.colDate]?.toString();

    final date = rawDate == null ? null : DateTime.tryParse(rawDate);

    final type = row[MilestoneCalendarSvc.colType]?.toString() ?? 'CMT';

    final expanded = _sameMilestone(_expandedMilestone, row);

    return Material(
      color: expanded ? colors.primaryContainer : colors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openMilestone(row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: expanded
              ? _expandedMilestoneView(context, row, date, type)
              : Row(
                  children: [
                    Icon(Icons.flag_outlined, size: 18, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${type.toUpperCase()}  •  '
                        '${date == null ? rawDate ?? '' : _dateText(date)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 19,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _expandedMilestoneView(
    BuildContext context,
    Map<String, Object?> row,
    DateTime? date,
    String type,
  ) {
    final colors = Theme.of(context).colorScheme;

    final dateText = date == null
        ? row[MilestoneCalendarSvc.colDate]?.toString() ?? ''
        : _dateText(date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flag_outlined, size: 19, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$dateText, ${type.toUpperCase()} - '
                '${_typeLabel(type)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_up, size: 19),
          ],
        ),
        const SizedBox(height: 9),
        _viewScope(context, 'Physics', row[MilestoneCalendarSvc.colPhy], 'PHY'),
        _viewScope(
          context,
          'Chemistry',
          row[MilestoneCalendarSvc.colChem],
          'CHEM',
        ),
        _viewScope(context, 'Biology', row[MilestoneCalendarSvc.colBio], 'BIO'),
        const SizedBox(height: 8),
        Row(
          children: [
            if (widget.onReturnToDashboard != null)
              Expanded(
                child: TextButton.icon(
                  onPressed: widget.onReturnToDashboard,
                  icon: const Icon(Icons.arrow_back_outlined, size: 17),
                  label: const Text('Return'),
                ),
              ),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _openEditScope,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Edit Scope'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _viewScope(
    BuildContext context,
    String subject,
    Object? raw,
    String subjectCode,
  ) {
    final codes = MilestoneCalendarSvc.splitCodes(raw?.toString());

    if (codes.isEmpty) {
      return const SizedBox.shrink();
    }

    final chapters = _chaptersFor(subjectCode);

    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              subject,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final code in codes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2, left: 2),
                    child: Text(
                      '$code - '
                      '${_chapterName(chapters, code)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
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

  String _chapterName(List<_ChapterOption> chapters, String code) {
    for (final chapter in chapters) {
      if (chapter.code.toUpperCase() == code.toUpperCase()) {
        return chapter.name;
      }
    }

    return code;
  }

  // ---------------------------------------------------------------------------
  // MILESTONE TASKS
  // ---------------------------------------------------------------------------

  Future<void> _loadMilestoneTasksView() async {
    if (_milestoneTasksLoading || !mounted) return;

    setState(() {
      _milestoneTasksLoading = true;
      _milestoneTasksError = null;
    });

    try {
      final db = await AppDatabase.instance.database;
      final milestoneSvc = MilestoneCalendarSvc(db);
      final creationRequired = await milestoneSvc.tasksCreationRequired();
      final rows = await milestoneSvc.getAllOpenMTasks();

      if (!mounted) return;

      setState(() {
        _milestoneTasksCreationRequired = creationRequired;
        _openMilestoneTasks = rows;
        _milestoneTasksLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _milestoneTasksLoading = false;
        _milestoneTasksCreationRequired = false;
        _openMilestoneTasks = const [];
        _milestoneTasksError = 'Unable to load milestone tasks.';
      });
    }
  }

  Map<String, List<Task>> _groupMilestoneTasksByDate() {
    final grouped = <String, List<Task>>{};

    for (final row in _openMilestoneTasks) {
      final task = _taskFromMilestoneRow(row);
      if (task == null) continue;

      final date = DateUtils.dateOnly(task.dueDate);
      final key = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

      grouped.putIfAbsent(key, () => []).add(task);
    }

    return grouped;
  }

  Widget _buildMilestoneTasks(BuildContext context) {
    if (_milestoneTasksLoading) {
      return const Card(
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
      );
    }

    if (_milestoneTasksError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            _milestoneTasksError!,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      );
    }

    final grouped = _groupMilestoneTasksByDate();
    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    if (dates.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'No milestone tasks pending or scheduled.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < dates.length; i++) ...[
          _buildMilestoneTaskDateSection(
            context,
            dateKey: dates[i],
            tasks: grouped[dates[i]]!,
          ),
          if (i < dates.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildMilestoneTaskDateSection(
    BuildContext context, {
    required String dateKey,
    required List<Task> tasks,
  }) {
    final colors = Theme.of(context).colorScheme;
    final date = DateTime.parse(dateKey);
    final today = DateUtils.dateOnly(DateTime.now());
    final isToday = DateUtils.isSameDay(date, today);
    final expanded = _milestoneTaskExpanded[dateKey] ?? true;

    final title = 'Coaching Milestone - '
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';

    return Card(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _milestoneTaskExpanded[dateKey] = !expanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    isToday ? Icons.today_outlined : Icons.flag_outlined,
                    size: 19,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    '${tasks.length}',
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
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Column(
              children: [
                for (final task in tasks)
                  _MilestoneTaskRow(
                    key: ValueKey(task.id),
                    task: task,
                    expanded: _expandedTaskId == task.id,
                    onExpand: _expandTask,
                    onCollapse: _collapseTask,
                    registerCommit: _registerCommit,
                    onChangeStatus: _changeStatus,
                    onTaskStateChanged: widget.onTaskStateChanged,
                    onTaskUpdated: _notifyTaskUpdated,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Task? _taskFromMilestoneRow(Map<String, Object?> row) {
    final id = row['TaskID']?.toString().trim();
    final description = row['TaskDescription']?.toString() ?? '';
    final dueText = row['TaskDueDate']?.toString();

    if (id == null || id.isEmpty || dueText == null || dueText.isEmpty) {
      return null;
    }

    final dueDate = DateTime.tryParse(dueText);
    if (dueDate == null) return null;

    final status =
        switch ((row['TaskStatus']?.toString() ?? 'PENDING').toUpperCase()) {
      'IN_PROGRESS' || 'STARTED' => TaskStatus.started,
      'COMPLETED' => TaskStatus.completed,
      'CANCELLED' ||
      'CANCELLED / NOT REQUIRED' =>
        TaskStatus.cancelledNotRequired,
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
      r'^Subject\s*\-\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(description);

    return match?.group(1)?.trim() ?? 'Task';
  }

  bool _isFutureTask(Task task) => DateUtils.dateOnly(task.dueDate)
      .isAfter(DateUtils.dateOnly(DateTime.now()));

  bool _isDueTask(Task task) => !_isFutureTask(task);

  bool _canChangeTask(Task task) {
    return _isDueTask(task) &&
        task.status != TaskStatus.completed &&
        task.status != TaskStatus.cancelledNotRequired;
  }

  Future<void> _changeStatus(Task task, TaskStatus next) async {
    if (!_canChangeTask(task)) return;

    final valid = switch (task.status) {
      TaskStatus.pending => next == TaskStatus.started ||
          next == TaskStatus.completed ||
          next == TaskStatus.cancelledNotRequired,
      TaskStatus.started =>
        next == TaskStatus.completed || next == TaskStatus.cancelledNotRequired,
      TaskStatus.completed => false,
      TaskStatus.cancelledNotRequired => false,
    };

    if (!valid) return;

    if (next == TaskStatus.completed ||
        next == TaskStatus.cancelledNotRequired) {
      final db = await AppDatabase.instance.database;
      await TaskActivityStatusSvc(db).deleteForTask(task.id);
    }

    final updated = task.copyWith(status: next);
    final stateCallback = widget.onTaskStateChanged;
    if (stateCallback != null) {
      stateCallback(updated);
    } else {
      _notifyTaskUpdated(updated);
    }

    await _loadMilestoneTasksView();
  }

  void _notifyTaskUpdated(Task task) {
    widget.onTaskUpdated?.call(task);
  }

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
      if (oldCommit != null) await oldCommit();
    }

    if (!mounted) return;

    setState(() {
      _expandedTaskId = taskId;
      _commitExpandedTask = commit;
    });
  }

  Future<void> _collapseTask(String taskId) async {
    if (_expandedTaskId != taskId) return;

    final commit = _commitExpandedTask;
    if (commit != null) await commit();

    if (!mounted) return;

    setState(() {
      _expandedTaskId = null;
      _commitExpandedTask = null;
    });
  }

  // ---------------------------------------------------------------------------
  // CREATE / EDIT MILESTONE
  // ---------------------------------------------------------------------------

  Widget _buildSet(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMilestoneEntryHeader(context),
        const SizedBox(height: 8),
        _buildSubjectTabs(context),
        const SizedBox(height: 6),
        _buildSelectedSubjectContent(context),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveMilestone,
            icon: _saving
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              _saving
                  ? 'Saving...'
                  : _existingMilestone == null
                      ? 'Save Milestone'
                      : 'Save Scope',
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // COMPACT TOP ROW
  // ---------------------------------------------------------------------------

  Widget _buildMilestoneEntryHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _typeChoice(
              context,
              'CMT',
              'Coaching',
              Icons.school_outlined,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _typeChoice(
              context,
              'PMT',
              'Personal',
              Icons.person_outline,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(child: _dateChoice(context)),
        ],
      ),
    );
  }

  Widget _typeChoice(
    BuildContext context,
    String value,
    String title,
    IconData icon,
  ) {
    final selected = _milestoneType == value;

    final colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _saving ? null : () => _onTypeChanged(value),
        child: Container(
          height: double.infinity,
          decoration: _segmentDecoration(
            context: context,
            selected: selected,
            radius: 8,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: selected ? colors.onPrimary : colors.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateChoice(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _saving ? null : _pickSunday,
        child: Container(
          height: double.infinity,
          decoration: _segmentDecoration(
            context: context,
            selected: false,
            radius: 8,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_month_outlined,
                size: 18,
                color: colors.primary,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  _compactDateText(_selectedDate),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _compactDateText(DateTime date) {
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

    return '${date.day.toString().padLeft(2, '0')}-'
        '${months[date.month - 1]}-'
        '${date.year}';
  }

  // ---------------------------------------------------------------------------
  // SUBJECT TABS
  // ---------------------------------------------------------------------------

  Widget _buildSubjectTabs(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _subjects.length; i++) ...[
            Expanded(child: _subjectTab(context, _subjects[i])),
            if (i < _subjects.length - 1) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }

  Widget _subjectTab(BuildContext context, _SubjectInfo subject) {
    final colors = Theme.of(context).colorScheme;

    final selected = _expandedSubject == subject.code;

    final selectedCount = _selectionFor(subject.code).length;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _saving ? null : () => _toggleSubject(subject.code),
        child: Container(
          height: double.infinity,
          decoration: _segmentDecoration(
            context: context,
            selected: selected,
            radius: 8,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                subject.icon,
                size: 17,
                color: selected ? colors.onPrimary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  subject.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? colors.onPrimary : colors.onSurface,
                  ),
                ),
              ),
              if (selectedCount > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '$selectedCount',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: selected ? colors.onPrimary : colors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SELECTED SUBJECT CONTENT
  // ---------------------------------------------------------------------------

  Widget _buildSelectedSubjectContent(BuildContext context) {
    final subject = _subjects.firstWhere(
      (item) => item.code == _expandedSubject,
      orElse: () => _subjects.first,
    );

    final chapters = _chaptersFor(subject.code);

    return _subjectContent(context, subject, chapters);
  }

  Widget _subjectContent(
    BuildContext context,
    _SubjectInfo subject,
    List<_ChapterOption> chapters,
  ) {
    return _chapterSwipeArea(context, subject, chapters);
  }

  // ---------------------------------------------------------------------------
  // TWO-BOX CHAPTER SWIPE AREA
  // ---------------------------------------------------------------------------

  Widget _chapterSwipeArea(
    BuildContext context,
    _SubjectInfo subject,
    List<_ChapterOption> chapters,
  ) {
    final totalPages = (chapters.length / _chaptersPerSwipe).ceil();

    if (chapters.isEmpty) {
      return _emptyChapterArea(context, 'No chapters found.');
    }

    final safePageCount = totalPages < 1 ? 1 : totalPages;

    if (_chapterPage >= safePageCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          _chapterPage = safePageCount - 1;
        });
      });
    }

    return SizedBox(
      height: 260,
      child: PageView.builder(
        key: PageStorageKey('chapter-page-${subject.code}'),
        controller: PageController(initialPage: _chapterPage),
        itemCount: safePageCount,
        onPageChanged: (page) {
          if (!mounted) return;

          setState(() {
            _chapterPage = page;
          });
        },
        itemBuilder: (context, pageIndex) {
          final start = pageIndex * _chaptersPerSwipe;

          final firstBox = chapters.skip(start).take(_chaptersPerBox).toList();

          final secondBox = chapters
              .skip(start + _chaptersPerBox)
              .take(_chaptersPerBox)
              .toList();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _chapterBox(context, subject, firstBox)),
                const SizedBox(width: 5),
                Expanded(child: _chapterBox(context, subject, secondBox)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chapterBox(
    BuildContext context,
    _SubjectInfo subject,
    List<_ChapterOption> chapters,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: Colors.black, width: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _chaptersPerBox; i++) ...[
            SizedBox(
              height: 42,
              child: i < chapters.length
                  ? _chapterRow(context, subject, chapters[i])
                  : const SizedBox(),
            ),
            if (i < _chaptersPerBox - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _emptyChapterArea(BuildContext context, String message) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 310,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: Colors.black, width: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        message,
        style: TextStyle(
          fontSize: 11.5,
          color: colors.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CHAPTER ROW
  // ---------------------------------------------------------------------------

  Widget _chapterRow(
    BuildContext context,
    _SubjectInfo subject,
    _ChapterOption chapter,
  ) {
    final colors = Theme.of(context).colorScheme;

    final selected = _selectionFor(subject.code).contains(chapter.code);

    final locked = _lockedSelectionFor(subject.code).contains(chapter.code);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black, width: 0.7),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: (_saving || locked)
              ? null
              : () => _toggleChapter(subject.code, chapter.code),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${chapter.code} - '
                    '${_truncateChapterName(chapter.name)}',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: locked ? colors.onSurfaceVariant : null,
                    ),
                  ),
                ),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Icon(
                      Icons.lock_outline,
                      size: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CHAPTER NAME TRUNCATION
  // ---------------------------------------------------------------------------

  String _truncateChapterName(String name) {
    final trimmed = name.trim();

    if (trimmed.length <= 32) {
      return trimmed;
    }

    return '${trimmed.substring(0, 30)}..';
  }

  // ---------------------------------------------------------------------------
  // ERROR
  // ---------------------------------------------------------------------------

  Widget _buildError(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Unable to load milestone calendar.\n$_error',
        style: TextStyle(fontSize: 12, color: colors.onErrorContainer),
      ),
    );
  }
}

// =============================================================================
// DATA CLASSES
// =============================================================================

class _SubjectInfo {
  const _SubjectInfo(this.code, this.shortCode, this.label, this.icon);

  final String code;
  final String shortCode;
  final String label;
  final IconData icon;
}

class _ChapterOption {
  const _ChapterOption(this.code, this.name);

  final String code;
  final String name;
}

class _MilestoneTaskRow extends StatefulWidget {
  const _MilestoneTaskRow({
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
  State<_MilestoneTaskRow> createState() => _MilestoneTaskRowState();
}

class _MilestoneTaskRowState extends State<_MilestoneTaskRow> {
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
  void didUpdateWidget(covariant _MilestoneTaskRow oldWidget) {
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
    final parsed = _parseMilestoneTaskDisplay(widget.task);

    final colors = Theme.of(context).colorScheme;

    final closed = widget.task.status == TaskStatus.completed ||
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
                        color:
                            widget.expanded ? Colors.black : colors.onSurface,
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
    if (_allMandatoryCompleted() && _isDue(widget.task)) {
      await _commitNow();
    }
  }

  bool _allMandatoryCompleted() {
    final mandatory =
        _activities.where((activity) => activity.isMandatory).toList();

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

class _MilestoneParsedTaskDisplay {
  const _MilestoneParsedTaskDisplay(
      {required this.dateText, required this.location});

  final String dateText;
  final String location;
}

class _MilestoneParsedTaskId {
  const _MilestoneParsedTaskId({
    required this.subjectCode,
    required this.chapterCode,
    required this.topicCode,
  });

  final String subjectCode;
  final String chapterCode;
  final String topicCode;
}

class _MilestoneParsedActivityText {
  const _MilestoneParsedActivityText(
      {required this.topic, required this.activity});

  final String topic;
  final String activity;
}

_MilestoneParsedTaskDisplay _parseMilestoneTaskDisplay(Task task) {
  final id = _parseMilestoneTaskId(task.id);

  String topic = '';

  for (final rawLine in task.title.split('\n')) {
    final line = rawLine.trim();

    if (line.isEmpty) {
      continue;
    }
    if (line.toLowerCase().startsWith('todo')) {
      final separator = line.indexOf('-');
      if (separator >= 0) {
        final parsed =
            _parseMilestoneActivityText(line.substring(separator + 1).trim());
        if (parsed != null) {
          topic = parsed.topic;
          break;
        }
      }
    }
    if (RegExp(r'^-\s*\d+\.').hasMatch(line)) {
      final parsed = _parseMilestoneActivityText(line.substring(1).trim());
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
  return _MilestoneParsedTaskDisplay(
    dateText: '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
    location: location,
  );
}

_MilestoneParsedTaskId _parseMilestoneTaskId(String taskId) {
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
  return _MilestoneParsedTaskId(
    subjectCode: subject,
    chapterCode: chapter,
    topicCode: topic,
  );
}

_MilestoneParsedActivityText? _parseMilestoneActivityText(String value) {
  final match = RegExp(r'^(\d+)\.\s*(.*?)\s*-\s*(.+)$').firstMatch(value);
  if (match == null) {
    return null;
  }
  final topic = match.group(2)!.trim();
  final activity = match.group(3)!.trim();
  if (topic.isEmpty || activity.isEmpty) {
    return null;
  }
  return _MilestoneParsedActivityText(topic: topic, activity: activity);
}
