import 'package:flutter/material.dart';

class NavigationItem {
  final IconData icon;
  final String label;

  const NavigationItem({required this.icon, required this.label});
}

/// Locked EPMS main navigation order and icon mapping.
/// The icons are chosen to closely match the earlier reference image
/// using Flutter's built-in Material Icons.
const epmsNavigationItems = <NavigationItem>[
  NavigationItem(icon: Icons.dashboard_outlined, label: 'Dashboard'),
  NavigationItem(icon: Icons.task_alt_outlined, label: 'Tasks'),
  NavigationItem(icon: Icons.today_outlined, label: 'Today’s Tasks'),
  NavigationItem(icon: Icons.menu_book_outlined, label: 'Current Studies'),
  NavigationItem(icon: Icons.video_library_outlined, label: 'Lectures'),
  NavigationItem(icon: Icons.replay_outlined, label: 'Revision'),
  NavigationItem(icon: Icons.note_alt_outlined, label: 'My Notes'),
  NavigationItem(icon: Icons.fact_check_outlined, label: 'Exam Readiness'),
  NavigationItem(icon: Icons.trending_up_outlined, label: 'Improvements'),
  NavigationItem(icon: Icons.help_outline, label: 'Doubts'),
  NavigationItem(icon: Icons.quiz_outlined, label: 'Practice Tests'),
  NavigationItem(icon: Icons.menu_book_outlined, label: 'Syllabus'),
  NavigationItem(icon: Icons.bar_chart_outlined, label: 'Reports'),
  NavigationItem(icon: Icons.sync_outlined, label: 'Calendar Synch'),
  NavigationItem(icon: Icons.flag_outlined, label: 'Milestone Calendar'),
  NavigationItem(icon: Icons.settings_outlined, label: 'Settings'),
  NavigationItem(icon: Icons.tune_outlined, label: 'Configurations'),
  NavigationItem(icon: Icons.exit_to_app_outlined, label: 'Exit'),
];
