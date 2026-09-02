import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../services/svc_milestones.dart';

class UpcomingMilestoneWidget extends StatefulWidget {
  const UpcomingMilestoneWidget({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  State<UpcomingMilestoneWidget> createState() =>
      _UpcomingMilestoneWidgetState();
}

class _UpcomingMilestoneWidgetState extends State<UpcomingMilestoneWidget> {
// ============================================================
// MILESTONE DATA
// ============================================================

  List<Map<String, Object?>> _upcomingMilestones = [];

  bool _milestonesLoading = true;

// ============================================================
// INITIALIZATION
// ============================================================

  @override
  void initState() {
    super.initState();

    _loadMilestones();
  }

// ============================================================
// LOAD MILESTONES
// ============================================================

  Future<void> _loadMilestones() async {
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
      if (!mounted) return;

      setState(() {
        _upcomingMilestones = [];
        _milestonesLoading = false;
      });
    }
  }

// ============================================================
// UPCOMING MILESTONE PANEL
// ============================================================

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
      return const Text(
        'No upcoming milestone found.',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 9.5,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Upcoming Coaching Milestones',
          style: TextStyle(
            color: gold,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
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

    if (scope is! Map) {
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

// ============================================================
// MILESTONE SUBJECT
// ============================================================

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
          (entry) => entry['chapter_name']?.toString().trim().isNotEmpty == true
              ? entry['chapter_name'].toString()
              : entry['chapter_code']?.toString() ?? '',
        )
        .where((name) => name.isNotEmpty)
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

// ============================================================
// MILESTONE SUBJECT ROW
// ============================================================

  Widget _milestoneSubjectRow(
    BuildContext context,
    String subject,
    String chapters,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2.5,
      ),
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
            child: Text(
              chapters,
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
    );
  }

// ============================================================
// BUILD
// ============================================================

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: widget.onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(
            9,
            8,
            9,
            7,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1C1C1C),
                Color(0xFF0B0B0B),
              ],
            ),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: gold.withValues(alpha: .22),
            ),
          ),
          child: _buildMilestonePanelContent(context),
        ),
      ),
    );
  }
}
