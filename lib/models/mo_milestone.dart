class Milestone {
  final String milestoneDate;
  final String milestoneType;
  final String milestonePhyChapters;
  final String milestoneChemChapters;
  final String milestoneBioChapters;

  const Milestone({
    required this.milestoneDate,
    required this.milestoneType,
    required this.milestonePhyChapters,
    required this.milestoneChemChapters,
    required this.milestoneBioChapters,
  });

  factory Milestone.fromMap(Map<String, Object?> row) {
    return Milestone(
      milestoneDate: row['milestone_date']?.toString() ?? '',
      milestoneType: row['milestone_type']?.toString() ?? '',
      milestonePhyChapters: row['milestone_phy_chapters']?.toString() ?? '',
      milestoneChemChapters: row['milestone_chem_chapters']?.toString() ?? '',
      milestoneBioChapters: row['milestone_bio_chapters']?.toString() ?? '',
    );
  }
}
