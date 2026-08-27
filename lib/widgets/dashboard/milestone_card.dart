import 'package:flutter/material.dart';

import '../../models/milestone.dart';

class MilestoneCard extends StatelessWidget {
  final List<Milestone> milestones;

  const MilestoneCard({super.key, required this.milestones});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Milestones this week',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (milestones.isEmpty)
              const Text('No milestones this week.')
            else
              ...milestones.map(
                (milestone) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    milestone.completed
                        ? Icons.check_circle
                        : Icons.flag_outlined,
                  ),
                  title: Text(milestone.title),
                  subtitle: Text(milestone.description),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
