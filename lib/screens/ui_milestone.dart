import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../services/cmt_weekend_task_generator_svc.dart';
import '../services/milestone_calendar_svc.dart';

/// Milestone calendar workspace.
///
/// Supports:
/// - View Milestones
/// - New Milestone Entry / Edit Scope
/// - CMT / PMT
/// - Sunday-only milestone dates
/// - Physics / Chemistry / Biology collapsible subject rows
/// - Chapter 1-10 / 11-20 / 21-30 ranges
/// - Chapter code/name selection
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

  static const List<int> _chapterRangeStarts = [1, 11, 21];

  MilestoneCalendarView _view = MilestoneCalendarView.view;

  DateTime _selectedDate = MilestoneCalendarSvc.nextSunday(DateTime.now());

  String _milestoneType = 'CMT';

  String? _expandedSubject;
  final Set<String> _expandedRanges = {};

  final Set<String> _selectedPhy = {};
  final Set<String> _selectedChem = {};
  final Set<String> _selectedBio = {};

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

  Future<void> _load() async {
    try {
      final db = await AppDatabase.instance.database;
      final svc = MilestoneCalendarSvc(db);

      _svc = svc;

      await _loadChapterOptions(db);

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

  Future<void> _loadChapterOptions(dynamic db) async {
    Future<List<_ChapterOption>> loadSubject(String subjectCode) async {
      final rows = await db.query(
        'db_SyllabusMaster',
        columns: ['chapter_code', 'chapter_name'],
        where: 'UPPER(subject_code) = ?',
        whereArgs: [subjectCode],
        orderBy: 'display_order ASC, chapter_code ASC',
      );

      final chapters = <_ChapterOption>[];
      final seen = <String>{};

      for (final row in rows) {
        final code = row['chapter_code']?.toString().trim() ?? '';

        final name = row['chapter_name']?.toString().trim() ?? '';

        if (code.isEmpty) continue;

        final normalisedCode = code.toUpperCase();

        if (!seen.add(normalisedCode)) continue;

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

    _scopeMessage = row == null
        ? null
        : 'Existing milestone found for this Sunday.';

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

  Future<void> _pickSunday() async {
    if (_saving) return;

    final today = _dateOnly(DateTime.now());

    final initialDate = _selectedDate.isBefore(today)
        ? MilestoneCalendarSvc.nextSunday(today)
        : _selectedDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      selectableDayPredicate: (date) {
        return date.weekday == DateTime.sunday;
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
    });

    await _loadExistingMilestone();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onTypeChanged(String type) async {
    if (_saving || type == _milestoneType) return;

    setState(() {
      _milestoneType = type;
      _existingMilestone = null;
      _scopeMessage = null;
      _scopeChangePending = false;

      _clearSelections();
    });

    await _loadExistingMilestone();

    if (mounted) {
      setState(() {});
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

    final existing = await svc.getMilestone(
      milestoneType: _milestoneType,
      date: _selectedDate,
    );

    if (existing != null && !_scopeChangePending) {
      setState(() {
        _existingMilestone = existing;
        _scopeMessage =
            'Existing milestone found. Do you want to change its scope?';
        _scopeChangePending = true;
      });

      return;
    }

    await _persistMilestone();
  }

  Future<void> _persistMilestone() async {
    final svc = _svc;

    if (svc == null || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await svc.saveMilestone(
        milestoneType: _milestoneType,
        date: _selectedDate,
        phyChapters: _selectedPhy.join(','),
        chemChapters: _selectedChem.join(','),
        bioChapters: _selectedBio.join(','),
      );

      await _generateCmtTasksIfRequired();

      final milestones = await svc.getUpcomingMilestones(limit: 100);

      final saved = await svc.getMilestone(
        milestoneType: _milestoneType,
        date: _selectedDate,
      );

      if (!mounted) return;

      final taskGenerationFailed =
          _scopeMessage?.startsWith(
            'Milestone saved, but CMT task generation failed:',
          ) ??
          false;

      setState(() {
        _milestones = milestones;
        _existingMilestone = saved;
        _expandedMilestone = saved;

        if (!taskGenerationFailed) {
          _scopeMessage = 'Milestone saved successfully.';
        }

        _scopeChangePending = false;
        _saving = false;
        _view = MilestoneCalendarView.view;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _generateCmtTasksIfRequired() async {
    if (_milestoneType.toUpperCase() != 'CMT') {
      return;
    }

    widget.onCmtTaskGenerationStarted?.call(_selectedDate);

    try {
      final db = await AppDatabase.instance.database;

      final generator = CmtWeekendTaskGeneratorSvc(db: db);

      await generator.generateCmtTasks(milestoneDate: _selectedDate);

      final taskRows = await generator.getCmtTaskRowsForDate(
        milestoneDate: _selectedDate,
      );

      widget.onCmtTasksGenerated?.call(_selectedDate, taskRows);
    } catch (error) {
      widget.onCmtTaskGenerationFailed?.call(_selectedDate, error);

      if (mounted) {
        setState(() {
          _scopeMessage =
              'Milestone saved, but CMT task generation failed: $error';
        });
      }
    }
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
      _expandedSubject = null;
      _expandedRanges.clear();
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
        _expandedSubject = null;
        _expandedRanges.clear();
        return;
      }

      _expandedSubject = code;

      _expandedRanges.removeWhere((key) => !key.startsWith('$code:'));
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

  List<_SubjectInfo> _orderedSubjects() {
    final expanded = _expandedSubject;

    if (expanded == null) {
      return _subjects;
    }

    final first = _subjects.firstWhere((subject) => subject.code == expanded);

    return [first, ..._subjects.where((subject) => subject.code != expanded)];
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
        return 'Coaching Milestone (CMT)';
      case 'PMT':
        return 'Personal Milestone (PMT)';
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModeSelector(context),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _buildError(context)
          else if (_view == MilestoneCalendarView.view)
            _buildView(context)
          else
            _buildSet(context),
        ],
      ),
    );
  }

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
                'View Milestones',
                Icons.event_available_outlined,
                MilestoneCalendarView.view,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _modeButton(
                context,
                'New Milestone Entry',
                Icons.add_task_outlined,
                MilestoneCalendarView.set,
              ),
            ),
          ],
        ),
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
      color: selected ? colors.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _view = value;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
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

  Widget _buildView(BuildContext context) {
    if (_milestones.isEmpty) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.event_busy_outlined,
                size: 36,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              const Text(
                'No upcoming milestones are set.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 5),
              Text(
                'Use New Milestone Entry to create one.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upcoming Milestones',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap a milestone row to expand or collapse it.',
              style: TextStyle(
                fontSize: 10.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 9),
            for (var i = 0; i < _milestones.length; i++) ...[
              _milestoneRow(context, _milestones[i]),
              if (i < _milestones.length - 1) const Divider(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _milestoneRow(BuildContext context, Map<String, Object?> row) {
    final colors = Theme.of(context).colorScheme;

    final rawDate = row[MilestoneCalendarSvc.colDate]?.toString();

    final date = rawDate == null ? null : DateTime.tryParse(rawDate);

    final type = row[MilestoneCalendarSvc.colType]?.toString() ?? 'CMT';

    final expanded = _sameMilestone(_expandedMilestone, row);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: expanded
          ? colors.surfaceContainerHighest
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: expanded
              ? colors.primary.withValues(alpha: .45)
              : colors.outlineVariant,
        ),
      ),
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
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onReturnToDashboard,
                icon: const Icon(Icons.arrow_back_outlined, size: 17),
                label: const Text('Return'),
              ),
            ),
            const SizedBox(width: 8),
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
      padding: const EdgeInsets.only(bottom: 7),
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
                      '$code - ${_chapterName(chapters, code)}',
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

  Widget _buildSet(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMilestoneEntryCard(context),
        const SizedBox(height: 10),
        _subjectStack(context),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveMilestone,
            icon: _saving
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              _saving
                  ? 'Saving...'
                  : _existingMilestone == null
                  ? 'Save / Set Milestone'
                  : 'Set Milestone Scope',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMilestoneEntryCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New Milestone Entry',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _typeChoice(
                    context,
                    'CMT',
                    'Coaching Milestone',
                    Icons.school_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _typeChoice(
                    context,
                    'PMT',
                    'Personal Milestone',
                    Icons.person_outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Milestone Date',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _pickSunday,
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _dateText(_selectedDate),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (_scopeMessage != null) ...[
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  _scopeMessage!,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ),
            ],
            if (_scopeChangePending) ...[
              const SizedBox(height: 7),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Change scope of the existing milestone?',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _scopeChangePending = false;
                            });
                          },
                    child: const Text('No'),
                  ),
                  FilledButton.tonal(
                    onPressed: _saving ? null : _enableExistingScopeEdit,
                    child: const Text('Yes'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _enableExistingScopeEdit() {
    if (_existingMilestone == null) return;

    _loadSelectionsFromMilestone(_existingMilestone);

    setState(() {
      _scopeChangePending = true;
      _scopeMessage =
          'Existing scope loaded. Tap chapters to select or unselect.';
    });
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
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _saving ? null : () => _onTypeChanged(value),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.3 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 17, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subjectStack(BuildContext context) {
    final orderedSubjects = _orderedSubjects();

    return Column(
      children: [
        for (var i = 0; i < orderedSubjects.length; i++) ...[
          _subjectSection(context, orderedSubjects[i]),
          if (i < orderedSubjects.length - 1) const SizedBox(height: 7),
        ],
      ],
    );
  }

  Widget _subjectSection(BuildContext context, _SubjectInfo subject) {
    final colors = Theme.of(context).colorScheme;

    final expanded = _expandedSubject == subject.code;

    final selected = _selectionFor(subject.code);

    final chapters = _chaptersFor(subject.code);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: expanded
          ? colors.surfaceContainerHighest
          : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: expanded
              ? colors.primary.withValues(alpha: .45)
              : colors.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _toggleSubject(subject.code),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    subject.icon,
                    size: 19,
                    color: expanded ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${subject.shortCode} - ${subject.label}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (selected.isNotEmpty)
                    Text(
                      '${selected.length} selected',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                  const SizedBox(width: 7),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 9),
              child: Column(
                children: [
                  for (final start in _chapterRangeStarts)
                    _rangeSection(context, subject, start, chapters),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rangeSection(
    BuildContext context,
    _SubjectInfo subject,
    int start,
    List<_ChapterOption> all,
  ) {
    final colors = Theme.of(context).colorScheme;

    final key = '${subject.code}:$start';

    final expanded = _expandedRanges.contains(key);

    final chapters = _rangeChapters(subject.code, start);

    return Container(
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _toggleRange(subject.code, start),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.folder_open_outlined
                        : Icons.folder_outlined,
                    size: 17,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _rangeLabel(start),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${chapters.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 17,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 7),
              child: Column(
                children: [
                  if (chapters.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          all.isEmpty
                              ? 'No chapters found.'
                              : 'No chapters in this range.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final chapter in chapters)
                      _chapterRow(context, subject, chapter),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _chapterRow(
    BuildContext context,
    _SubjectInfo subject,
    _ChapterOption chapter,
  ) {
    final colors = Theme.of(context).colorScheme;

    final selected = _selectionFor(subject.code).contains(chapter.code);

    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: .55)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: _saving
            ? null
            : () => _toggleChapter(subject.code, chapter.code),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${chapter.code} - ${chapter.name}',
                  style: TextStyle(
                    fontSize: 10.8,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Unable to load milestone calendar.\n$_error',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

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
