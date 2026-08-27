class SyllabusProgress {
  final int completedItems;
  final int totalItems;

  const SyllabusProgress({
    required this.completedItems,
    required this.totalItems,
  });

  double get percentage {
    if (totalItems == 0) {
      return 0;
    }

    return completedItems / totalItems;
  }
}
