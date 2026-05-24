import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WildPageHeader extends StatelessWidget {
  final String title;

  // Оставлено для совместимости со старыми вызовами.
  // В интерфейсе больше не выводится.
  final String? subtitle;

  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const WildPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.screen,
      20,
      AppSpacing.screen,
      12,
    ),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 38,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 28,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}