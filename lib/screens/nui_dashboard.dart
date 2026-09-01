import 'package:flutter/material.dart';

const Color dashboardGold = Color(0xFFD4AF37);
const Color dashboardMutedGold = Color(0xFFB99A45);

class NewDashboardScreen extends StatelessWidget {
  const NewDashboardScreen({super.key});

  //static const Color gold = Color(0xFFD4AF37);
  //static const Color mutedGold = Color(0xFFB99A45);
  // const Color dashboardGold = Color(0xFFD4AF37);
  // const Color dashboardMutedGold = Color(0xFFB99A45);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF090909),
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: _DashboardLeftNavigation(),
            ),
            Expanded(
              child: _DashboardMainArea(),
            ),
            SizedBox(
              width: 270,
              child: Padding(
                padding: EdgeInsets.only(
                  top: 12,
                  right: 12,
                  bottom: 12,
                ),
                child: _DashboardRightPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// LEFT NAVIGATION
// ============================================================================

class _DashboardLeftNavigation extends StatelessWidget {
  const _DashboardLeftNavigation();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF090909),
      child: Column(
        children: [
          const SizedBox(height: 14),
          _navigationIcon(Icons.dashboard_outlined, selected: true),
          _navigationIcon(Icons.check_circle_outline),
          _navigationIcon(Icons.menu_book_outlined),
          _navigationIcon(Icons.flag_outlined),
          _navigationIcon(Icons.school_outlined),
          _navigationIcon(Icons.settings_outlined),
        ],
      ),
    );
  }

  Widget _navigationIcon(
    IconData icon, {
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected
              ? dashboardGold.withValues(alpha: .12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? dashboardGold.withValues(alpha: .35)
                : Colors.transparent,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: selected ? dashboardGold : Colors.white.withValues(alpha: .55),
        ),
      ),
    );
  }
}

// ============================================================================
// MAIN AREA
// ============================================================================

class _DashboardMainArea extends StatelessWidget {
  const _DashboardMainArea();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const _DashboardHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DashboardPanel(
                    title: 'LECTURES',
                    child: _LectureSection(),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 620) {
                        return const Column(
                          children: [
                            _DashboardPanel(
                              title: 'TASKS',
                              child: _TasksSection(),
                            ),
                            SizedBox(height: 10),
                            _DashboardPanel(
                              title: 'SYLLABUS COVERAGE',
                              child: _SyllabusSection(),
                            ),
                          ],
                        );
                      }

                      return const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _DashboardPanel(
                              title: 'TASKS',
                              child: _TasksSection(),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _DashboardPanel(
                              title: 'SYLLABUS COVERAGE',
                              child: _SyllabusSection(),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HEADER
// ============================================================================

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 70,
        maxHeight: 76,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF171717),
            Color(0xFF0D0D0D),
            Color(0xFF17120A),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.fromBorderSide(
          BorderSide(
            color: dashboardGold,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .55),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: dashboardGold.withValues(alpha: .08),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '✦',
                  style: TextStyle(
                    color: dashboardGold,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Hello Dr. TANUSH',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
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
          const Expanded(
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
                    style: TextStyle(
                      color: dashboardMutedGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'DASHBOARD',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      color: dashboardGold,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: _HeaderMetric(
                    label: 'DAYS LEFT',
                    value: '242',
                  ),
                ),
                SizedBox(width: 12),
                Flexible(
                  child: _HeaderMetric(
                    label: 'READINESS',
                    value: '20%',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
            style: const TextStyle(
              color: dashboardGold,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// GENERIC PANEL
// ============================================================================

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF151515),
            Color(0xFF0B0B0B),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.fromBorderSide(
          BorderSide(
            color: dashboardGold.withValues(alpha: .28),
          ),
        ),
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
              color: dashboardGold,
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
}

// ============================================================================
// LECTURES
// ============================================================================

class _LectureSection extends StatelessWidget {
  const _LectureSection();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _LectureCard(
            name: 'Physics',
            icon: Icons.science_outlined,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _LectureCard(
            name: 'Chemistry',
            icon: Icons.biotech_outlined,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _LectureCard(
            name: 'Biology',
            icon: Icons.eco_outlined,
          ),
        ),
      ],
    );
  }
}

class _LectureCard extends StatelessWidget {
  const _LectureCard({
    required this.name,
    required this.icon,
  });

  final String name;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF202020),
            Color(0xFF0E0E0E),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dashboardGold.withValues(alpha: .28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .45),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 21,
            color: dashboardGold,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TASKS
// ============================================================================

class _TasksSection extends StatelessWidget {
  const _TasksSection();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Today\'s Tasks', '0', Icons.today_rounded),
      ('Past Due', '0', Icons.pending_actions_rounded),
      ('In Progress', '0', Icons.play_circle_outline_rounded),
      ('Revision Tasks', '0', Icons.replay_rounded),
      ('Refresh Counters', '', Icons.refresh_rounded),
      ('Milestone Tasks', '0', Icons.flag_rounded),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 7,
        mainAxisSpacing: 7,
        mainAxisExtent: 78,
      ),
      itemBuilder: (_, index) {
        final item = items[index];

        return _TaskCard(
          label: item.$1,
          count: item.$2,
          icon: item.$3,
        );
      },
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.label,
    required this.count,
    required this.icon,
  });

  final String label;
  final String count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final hasCount = count.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF242424),
            Color(0xFF0C0C0C),
          ],
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: dashboardGold.withValues(alpha: .30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .45),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 7,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: dashboardGold.withValues(alpha: .10),
              shape: BoxShape.circle,
              border: Border.all(
                color: dashboardGold.withValues(alpha: .22),
              ),
            ),
            child: Icon(
              icon,
              color: dashboardGold,
              size: 15,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasCount)
                  Text(
                    count,
                    maxLines: 1,
                    style: const TextStyle(
                      color: dashboardGold,
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
          if (hasCount)
            Icon(
              Icons.chevron_right_rounded,
              size: 15,
              color: Colors.white.withValues(alpha: .40),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// SYLLABUS
// ============================================================================

class _SyllabusSection extends StatelessWidget {
  const _SyllabusSection();

  @override
  Widget build(BuildContext context) {
    const cards = [
      (
        'Total Syllabus',
        '0%',
        '0/80 chapters',
        Icons.auto_graph_rounded,
      ),
      (
        'Biology',
        '0%',
        '0/161 topics',
        Icons.menu_book_rounded,
      ),
      (
        'Chemistry',
        '0%',
        '0 topics',
        Icons.menu_book_rounded,
      ),
      (
        'Physics',
        '0%',
        '0 topics',
        Icons.menu_book_rounded,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 7,
        mainAxisSpacing: 7,
        mainAxisExtent: 78,
      ),
      itemBuilder: (_, index) {
        final card = cards[index];

        return _SyllabusCard(
          label: card.$1,
          value: card.$2,
          detail: card.$3,
          icon: card.$4,
        );
      },
    );
  }
}

class _SyllabusCard extends StatelessWidget {
  const _SyllabusCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF242424),
            Color(0xFF0D0D0D),
          ],
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: dashboardGold.withValues(alpha: .30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .45),
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 7,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: dashboardGold.withValues(alpha: .10),
              shape: BoxShape.circle,
              border: Border.all(
                color: dashboardGold.withValues(alpha: .22),
              ),
            ),
            child: Icon(
              icon,
              color: dashboardGold,
              size: 15,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    color: dashboardGold,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .52),
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 15,
            color: Colors.white.withValues(alpha: .40),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// RIGHT PANEL
// ============================================================================

class _DashboardRightPanel extends StatelessWidget {
  const _DashboardRightPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF121212),
            Color(0xFF080808),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dashboardGold.withValues(alpha: .25),
        ),
      ),
      child: const SingleChildScrollView(
        padding: EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _UpcomingMilestoneCard(),
            SizedBox(height: 9),
            _ActiveWorkspaceCard(),
            SizedBox(height: 9),
            _ReservedCard(),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// UPCOMING MILESTONE
// ============================================================================

class _UpcomingMilestoneCard extends StatelessWidget {
  const _UpcomingMilestoneCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1C1C1C),
            Color(0xFF0B0B0B),
          ],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: dashboardGold.withValues(alpha: .22),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upcoming Coaching Milestones',
            style: TextStyle(
              color: dashboardGold,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 7),
          Text(
            'No upcoming milestone found.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ACTIVE WORKSPACE
// ============================================================================

class _ActiveWorkspaceCard extends StatelessWidget {
  const _ActiveWorkspaceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1B1B1B),
            Color(0xFF0C0C0C),
          ],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: dashboardGold.withValues(alpha: .20),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Workspace',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dashboardGold,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.dashboard_customize_outlined,
                size: 15,
                color: dashboardGold,
              ),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Dashboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
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
}

// ============================================================================
// RESERVED
// ============================================================================

class _ReservedCard extends StatelessWidget {
  const _ReservedCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF181818),
            Color(0xFF0B0B0B),
          ],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: dashboardGold.withValues(alpha: .16),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reserved',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dashboardGold,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'Additional contextual information will be added here later.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}
