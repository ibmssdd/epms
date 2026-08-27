import 'package:flutter/material.dart';

import '../../models/subject.dart';

class SubjectProgressCard extends StatelessWidget {
  final Subject subject;

  const SubjectProgressCard({super.key, required this.subject});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subject.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subject.currentChapter,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: subject.chapterProgress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 6),
            Text(
              '${(subject.chapterProgress * 100).round()}% chapter progress',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
