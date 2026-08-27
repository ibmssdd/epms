import 'package:flutter/material.dart';

import '../../models/task.dart';

class UpcomingTasksCard extends StatelessWidget {
  final List<Task> tasks;

  const UpcomingTasksCard({super.key, required this.tasks});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upcoming tasks',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (tasks.isEmpty)
              const Text('No upcoming tasks.')
            else
              ...tasks.map(
                (task) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.task_alt_outlined),
                  title: Text(task.title),
                  subtitle: Text(task.subject),
                  trailing: Text('${task.dueDate.day}/${task.dueDate.month}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
