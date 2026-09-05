import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/svc_status_chapters.dart';
import '../services/svc_milestones.dart';
import '../services/svc_task_generator_mt.dart';

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
  });

  final DateTime? initialDate;
  final MilestoneCalendarView initialView;

  final VoidCallback? onReturnToDashboard;

  final ValueChanged<DateTime>? onCmtTaskGenerationStarted;

  final void Function(DateTime, List<Map<String, Object?>>)?
      onCmtTasksGenerated;

  final void Function(DateTime, Object)? onCmtTaskGenerationFailed;

  @override
  State<MilestoneCalendarScreen> createState() =>
      _MilestoneCalendarScreenState();
}

enum MilestoneCalendarView { view, set }

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

  List<Map<String, String>> _buildMTCalendarScope() {
    final scope = <Map<String, String>>[];

    // ------------------------------------------------------------
    // PHYSICS
    // ------------------------------------------------------------
    for (final chapter in _phyChapters) {
      if (_selectedPhy.contains(chapter.code)) {
        scope.add({
          'subjectCode': 'PHY',
          'chapterCode': chapter.code,
          'chapterName': chapter.name,
        });
      }
    }

    // ------------------------------------------------------------
    // CHEMISTRY
    // ------------------------------------------------------------
    for (final chapter in _chemChapters) {
      if (_selectedChem.contains(chapter.code)) {
        scope.add({
          'subjectCode': 'CHEM',
          'chapterCode': chapter.code,
          'chapterName': chapter.name,
        });
      }
    }

    // ------------------------------------------------------------
    // BIOLOGY
    // ------------------------------------------------------------
    for (final chapter in _bioChapters) {
      if (_selectedBio.contains(chapter.code)) {
        scope.add({
          'subjectCode': 'BIO',
          'chapterCode': chapter.code,
          'chapterName': chapter.name,
        });
      }
    }

    return scope;
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
      // 0 Save Milestone Task Calendar scope.

      await svc.saveMTCalender(
        milestoneType: _milestoneType,
        date: _selectedDate,
        scope: _buildMTCalendarScope(),
      );
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
    String statusText(String subject, int subTaskCount) {
      final taskCount = subTaskCount > 0 ? 1 : 0;
      return '$subject : $taskCount Task, '
          '$subTaskCount SubTasks Generated';
    }

    return [
      statusText('Physics', results['PHY'] ?? 0),
      statusText('Chemistry', results['CHEM'] ?? 0),
      statusText('Biology', results['BIO'] ?? 0),
      statusText('Milestone Test', results['PCB'] ?? 0),
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
  // CREATE / EDIT MILESTONE
  // ---------------------------------------------------------------------------

  // Widget _buildSet(BuildContext context)
  // {
  //   return Column(
  //     crossAxisAlignment: CrossAxisAlignment.stretch,
  //     children: [
  //       _buildMilestoneEntryHeader(context),
  //       const SizedBox(height: 8),
  //       _buildSubjectTabs(context),
  //       const SizedBox(height: 6),
  //       _buildSelectedSubjectContent(context),
  //       const SizedBox(height: 10),
  //       SizedBox(
  //         height: 40,
  //         child: FilledButton.icon(
  //           onPressed: _saving ? null : _saveMilestone,
  //           icon: _saving
  //               ? const SizedBox(
  //             width: 17,
  //             height: 17,
  //             child: CircularProgressIndicator(
  //               strokeWidth: 2,
  //               color: Colors.white,
  //             ),
  //           )
  //               : const Icon(Icons.save_outlined),
  //           label: Text(
  //             _saving
  //                 ? 'Saving...'
  //                 : _existingMilestone == null
  //                 ? 'Save Milestone'
  //                 : 'Save Scope',
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }
  Widget _buildSet(BuildContext context) {
    final isEditingExistingMilestone = _existingMilestone != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMilestoneEntryHeader(context),
        const SizedBox(height: 8),
        _buildSubjectTabs(context),
        const SizedBox(height: 6),
        _buildSelectedSubjectContent(context),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SizedBox(
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
                        : isEditingExistingMilestone
                            ? 'Save and Generate Task'
                            : 'Save Milestone',
                  ),
                ),
              ),
            ),
            if (isEditingExistingMilestone) ...[
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() {
                              _view = MilestoneCalendarView.view;
                              _expandedRanges.clear();
                              _scopeChangePending = false;
                              _scopeMessage = null;
                            });

                            await _load();
                          },
                    icon: const Icon(Icons.close_outlined),
                    label: const Text('Cancel'),
                  ),
                ),
              ),
            ],
          ],
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
