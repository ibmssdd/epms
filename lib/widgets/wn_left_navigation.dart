import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NavigationItem {
  final IconData icon;
  final String label;

  const NavigationItem({required this.icon, required this.label});
}

const List<NavigationItem> epmsNavigationItems = [
  NavigationItem(icon: Icons.dashboard_outlined, label: 'Dashboard'),
  NavigationItem(icon: Icons.task_alt_outlined, label: 'Tasks'),
  NavigationItem(icon: Icons.menu_book_outlined, label: 'Syllabus'),
  NavigationItem(icon: Icons.replay_outlined, label: 'Revision & Tests'),
  NavigationItem(icon: Icons.video_library_outlined, label: 'Notes & Lectures'),
  NavigationItem(icon: Icons.flag_outlined, label: 'Milestone Calendar'),
  NavigationItem(icon: Icons.checklist_rtl_outlined, label: 'Milestone Tasks',),
  NavigationItem(icon: Icons.exit_to_app_outlined, label: 'Exit'),
  //  NavigationItem(icon: Icons.note_alt_outlined, label: 'My Notes'),
  //  NavigationItem(icon: Icons.fact_check_outlined, label: 'Exam Readiness'),
  //  NavigationItem(icon: Icons.trending_up_outlined, label: 'Improvements'),
  //  NavigationItem(icon: Icons.help_outline, label: 'Doubts'),
  //  NavigationItem(icon: Icons.quiz_outlined, label: 'Practice Tests'),
  //  NavigationItem(icon: Icons.bar_chart_outlined, label: 'Reports'),
  //  NavigationItem(icon: Icons.sync_outlined, label: 'Calendar Synch'),
  //  NavigationItem(icon: Icons.menu_book_outlined, label: 'Current Studies'),
  //  NavigationItem(icon: Icons.settings_outlined, label: 'Settings'),
  //  NavigationItem(icon: Icons.today_outlined, label: 'Today’s Tasks'),
  //  NavigationItem(icon: Icons.tune_outlined, label: 'Configurations'),
];

class LeftNavigation extends StatelessWidget {
  final bool expanded;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const LeftNavigation({
    super.key,
    required this.expanded,
    required this.selectedIndex,
    required this.onSelected,
  });

  static const double expandedWidth = 190;
  static const double collapsedWidth = 60;

  // ==========================================================================
  // EXIT APP
  // ==========================================================================

  Future<void> _confirmExit(BuildContext context) async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Exit App'),
          content: const Text(
            'Are you sure you want to close the application?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Close App'),
            ),
          ],
        );
      },
    );

    if (shouldExit == true) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: expanded ? expandedWidth : collapsedWidth,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Icon(Icons.school_outlined, size: 30),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: epmsNavigationItems.length,
              itemBuilder: (context, index) {
                final item = epmsNavigationItems[index];
                final selected = index == selectedIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Tooltip(
                    message: item.label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        // ----------------------------------------------------
                        // Exit is handled here and does NOT become a
                        // navigation page.
                        // ----------------------------------------------------
                        if (item.label == 'Exit') {
                          _confirmExit(context);
                          return;
                        }

                        onSelected(index);
                      },
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: selected
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: expanded ? 42 : 48,
                              child: Icon(
                                item.icon,
                                size: 22,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                            if (expanded)
                              Expanded(
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
