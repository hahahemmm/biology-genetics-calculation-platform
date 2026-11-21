// 计算页统一空态：告诉学生下一步，而不是留下整块空白。

import 'package:flutter/material.dart';

import '../../theme.dart';

class CalculationEmptyState extends StatelessWidget {
  const CalculationEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 34, color: AppColors.teal),
          const SizedBox(height: 12),
          Text(title, style: AppText.sectionTitle),
          const SizedBox(height: 6),
          Text(
            description,
            style: AppText.body.copyWith(color: AppColors.graphite),
          ),
        ],
      ),
    );
  }
}
