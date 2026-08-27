import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final items = <_NavigationItem>[
      const _NavigationItem(icon: Icons.dashboard_outlined, label: 'Dashboard'),
      const _NavigationItem(icon: Icons.task_alt_outlined, label: 'Tasks'),
      const _NavigationItem(icon: Icons.menu_book_outlined, label: 'Syllabus'),
      const _NavigationItem(
        icon: Icons.calendar_month_outlined,
        label: 'Calendar',
      ),
      const _NavigationItem(icon: Icons.note_alt_outlined, label: 'Notes'),
      const _NavigationItem(
        icon: Icons.video_library_outlined,
        label: 'Lectures',
      ),
      const _NavigationItem(icon: Icons.replay_outlined, label: 'Revision'),
      const _NavigationItem(icon: Icons.settings_outlined, label: 'Settings'),
    ];

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
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = index == selectedIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Tooltip(
                    message: item.label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onSelected(index),
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

class _NavigationItem {
  final IconData icon;
  final String label;

  const _NavigationItem({required this.icon, required this.label});
}
