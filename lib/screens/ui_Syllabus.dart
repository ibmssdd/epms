import 'package:flutter/material.dart';

import '../services/svc_Syllabus_Coverage.dart';

class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  final SyllabusCoverageService _service = SyllabusCoverageService.instance;

  Map<String, Object?>? _overallCoverage;

  String? _expandedSubjectCode;

  bool _loading = true;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCoverage();
  }

  Future<void> _loadCoverage() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final coverage = await _service.getOverallCoverage();

      if (!mounted) return;

      setState(() {
        _overallCoverage = coverage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_overallCoverage == null) {
      return _buildEmptyState();
    }

    final subjects =
        (_overallCoverage!['subjects'] as List<Map<String, Object?>>?) ??
        <Map<String, Object?>>[];

    if (subjects.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCoverage,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            _buildOverallCard(),
            const SizedBox(height: 16),
            _buildEmptyState(),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCoverage,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          _buildOverallCard(),
          const SizedBox(height: 12),
          _buildSubjectCards(subjects),
        ],
      ),
    );
  }

  // ============================================================
  // OVERALL COVERAGE
  // ============================================================

  Widget _buildOverallCard() {
    final completedTopics = _asInt(_overallCoverage!['completedTopics']);

    final totalTopics = _asInt(_overallCoverage!['totalTopics']);

    final completedChapters = _asInt(_overallCoverage!['completedChapters']);

    final totalChapters = _asInt(_overallCoverage!['totalChapters']);

    final progress = _asDouble(_overallCoverage!['progress']);

    final percent = (progress * 100).round();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE9E7FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_graph_rounded,
                    color: Color(0xFF4F46E5),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Total Syllabus',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 7,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 9),
            Text(
              '$completedChapters/$totalChapters chapters • '
              '$completedTopics/$totalTopics topics completed',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SUBJECTS
  // ============================================================

  Widget _buildSubjectCards(List<Map<String, Object?>> subjects) {
    return Column(
      children: [
        for (final subject in subjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildSubjectSection(subject),
          ),
      ],
    );
  }

  Widget _buildSubjectSection(Map<String, Object?> subject) {
    final subjectCode = subject['subjectCode']?.toString().trim() ?? '';

    final subjectName =
        subject['subjectName']?.toString().trim() ?? subjectCode;

    final chapters =
        (subject['chapters'] as List<Map<String, Object?>>?) ??
        <Map<String, Object?>>[];

    final completedTopics = _asInt(subject['completedTopics']);

    final totalTopics = _asInt(subject['totalTopics']);

    final progress = _asDouble(subject['progress']);

    final expanded = _expandedSubjectCode == subjectCode;

    final color = _subjectColor(subjectCode);

    final background = _subjectBackground(subjectCode);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expandedSubjectCode = expanded ? null : subjectCode;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subjectName.isEmpty ? subjectCode : subjectName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$completedTopics/'
                          '$totalTopics topics completed',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 65,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${(progress * 100).round()}%',
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) _buildChapterList(chapters, color),
        ],
      ),
    );
  }

  // ============================================================
  // CHAPTER LIST
  // ============================================================

  Widget _buildChapterList(
    List<Map<String, Object?>> chapters,
    Color subjectColor,
  ) {
    if (chapters.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No chapter coverage data available.',
          style: TextStyle(fontSize: 12),
        ),
      );
    }

    return Column(
      children: [
        const Divider(height: 1),
        for (final chapter in chapters) _buildChapterRow(chapter, subjectColor),
      ],
    );
  }

  // ============================================================
  // CHAPTER ROW
  // ============================================================

  Widget _buildChapterRow(Map<String, Object?> chapter, Color subjectColor) {
    final chapterCode = chapter['chapterCode']?.toString() ?? '';

    final chapterName = chapter['chapterName']?.toString() ?? '';

    final completedTopics = _asInt(chapter['completedTopics']);

    final totalTopics = _asInt(chapter['totalTopics']);

    final progress = _asDouble(chapter['progress']);

    final chapterState = chapter['chapterState']?.toString() ?? 'NotStarted';

    final allTopicsCompleted = _asBool(chapter['allTopicsCompleted']);

    final pmtCompleted = _asBool(chapter['pmtCompleted']);

    final cmtCompleted = _asBool(chapter['cmtCompleted']);

    final weakAreasCleared = _asBool(chapter['weakAreasCleared']);

    final finalExamReady = _asBool(chapter['finalExamReady']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$chapterCode — $chapterName',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$completedTopics / '
                      '$totalTopics topics completed',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: subjectColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _statusChip(
                label: _chapterStateLabel(chapterState),
                completed: chapterState == 'ExamReady',
                active: chapterState == 'InProgress',
                color: subjectColor,
              ),
              _statusChip(
                label: 'Topics',
                completed: allTopicsCompleted,
                color: subjectColor,
              ),
              _statusChip(
                label: 'PMT',
                completed: pmtCompleted,
                color: subjectColor,
              ),
              _statusChip(
                label: 'CMT',
                completed: cmtCompleted,
                color: subjectColor,
              ),
              _statusChip(
                label: 'Weak Areas',
                completed: weakAreasCleared,
                color: subjectColor,
              ),
              _statusChip(
                label: 'Exam Ready',
                completed: finalExamReady,
                color: subjectColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // STATUS CHIP
  // ============================================================

  Widget _statusChip({
    required String label,
    required bool completed,
    bool active = false,
    required Color color,
  }) {
    final foreground = completed || active ? color : Colors.grey.shade600;

    final background = completed
        ? color.withValues(alpha: .10)
        : active
        ? color.withValues(alpha: .07)
        : Colors.grey.withValues(alpha: .07);

    final icon = completed
        ? Icons.check_rounded
        : active
        ? Icons.circle
        : Icons.circle_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: foreground.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: active ? 7 : 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w800,
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
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();

    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;

    return value?.toString().trim().toLowerCase() == 'yes';
  }

  String _chapterStateLabel(String state) {
    switch (state) {
      case 'InProgress':
        return 'In Progress';

      case 'ExamReady':
        return 'Exam Ready';

      case 'Completed':
        return 'Completed';

      case 'NotStarted':
      default:
        return 'Not Started';
    }
  }

  // Generic subject styling.
  // No subject names/codes are hard-coded here.
  Color _subjectColor(String subjectCode) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF0F766E),
      Color(0xFF7C3AED),
      Color(0xFF15803D),
      Color(0xFFB45309),
      Color(0xFFDB2777),
    ];

    if (subjectCode.isEmpty) {
      return colors.first;
    }

    final index =
        subjectCode.codeUnits.fold<int>(0, (sum, value) => sum + value) %
        colors.length;

    return colors[index];
  }

  Color _subjectBackground(String subjectCode) {
    return _subjectColor(subjectCode).withValues(alpha: .10);
  }

  // ============================================================
  // EMPTY / ERROR
  // ============================================================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 42,
              color: Colors.grey.shade500,
            ),
            const SizedBox(height: 10),
            Text(
              'No syllabus coverage available.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 10),
            const Text(
              'Unable to load syllabus coverage.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadCoverage,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
