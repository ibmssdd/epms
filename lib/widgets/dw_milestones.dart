import 'package:flutter/material.dart';
import '../models/mo_milestone.dart';

class MilestoneCard extends StatelessWidget {
  final Milestone? milestone;

  const MilestoneCard({super.key, required this.milestone});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Next Milestone',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (milestone == null)
              const Text('No upcoming milestone.')
            else
              _buildMilestoneContent(milestone!),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneContent(Milestone milestone) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          milestone.milestoneDate,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          milestone.milestoneType,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        if (milestone.milestonePhyChapters.isNotEmpty)
          _buildSubjectRow(
            subject: 'Physics',
            chapters: milestone.milestonePhyChapters,
          ),
        if (milestone.milestoneChemChapters.isNotEmpty)
          _buildSubjectRow(
            subject: 'Chemistry',
            chapters: milestone.milestoneChemChapters,
          ),
        if (milestone.milestoneBioChapters.isNotEmpty)
          _buildSubjectRow(
            subject: 'Biology',
            chapters: milestone.milestoneBioChapters,
          ),
      ],
    );
  }

  Widget _buildSubjectRow({required String subject, required String chapters}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              subject,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(chapters)),
        ],
      ),
    );
  }
}
