import 'package:flutter/material.dart';

class SprintCounterWidget extends StatelessWidget {
  final DateTime sprintStartDate;
  final int totalSprintDays;

  const SprintCounterWidget({
    super.key,
    required this.sprintStartDate,
    this.totalSprintDays = 15,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final difference = today.difference(sprintStartDate).inDays;
    final currentDayIndex = difference.clamp(0, totalSprintDays);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05), // Updated here
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(totalSprintDays, (index) {
            final dayNumber = index + 1;
            final isPassed = dayNumber < currentDayIndex;
            final isToday = dayNumber == currentDayIndex;

            Color dateColor;
            if (dayNumber <= 5) {
              dateColor = Colors.green;
            } else if (dayNumber <= 10) {
              dateColor = Colors.amber.shade700;
            } else {
              dateColor = Colors.red.shade800;
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isToday
                              ? dateColor.withValues(alpha: 0.15)
                              : Colors.transparent, // Updated here
                          border: isToday
                              ? Border.all(color: dateColor, width: 2)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'D$dayNumber',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isPassed ? Colors.grey.shade400 : dateColor,
                          ),
                        ),
                      ),
                      if (isPassed)
                        Positioned.fill(
                          child: CustomPaint(
                            painter:
                                StrikeThroughArrowPainter(color: dateColor),
                          ),
                        ),
                    ],
                  ),
                  if (isToday) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Today',
                      style: TextStyle(
                          fontSize: 10,
                          color: dateColor,
                          fontWeight: FontWeight.bold),
                    ),
                  ]
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

class StrikeThroughArrowPainter extends CustomPainter {
  final Color color;
  StrikeThroughArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5) // Updated here
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final start = Offset(4, size.height - 4);
    final end = Offset(size.width - 4, 4);
    canvas.drawLine(start, end, paint);

    final path = Path();
    path.moveTo(end.dx, end.dy);
    path.lineTo(end.dx - 5, end.dy + 1);
    path.lineTo(end.dx - 1, end.dy + 5);
    path.close();

    final arrowPaint = Paint()
      ..color = color.withValues(alpha: 0.7) // Updated here
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
