import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import 'package:calcwise_core/calcwise_core.dart';

class ResultCard extends StatelessWidget {
  final String label, value;
  final String? subtitle;
  final IconData? icon;
  final bool highlight;
  const ResultCard(
      {super.key,
      required this.label,
      required this.value,
      this.subtitle,
      this.icon,
      this.highlight = false});

  @override
  Widget build(BuildContext context) {
    if (highlight) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          boxShadow: [
            BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: _content(Colors.white, Colors.white70),
      );
    }
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: _content(
          Theme.of(context).textTheme.titleLarge!.color!, AppTheme.labelGray),
    ));
  }

  Widget _content(Color primary, Color secondary) => Row(children: [
        if (icon != null) ...[
          Icon(icon, color: primary.withValues(alpha: 0.8), size: 22),
          SizedBox(width: AppSpacing.md)
        ],
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: secondary,
                  fontSize: AppTextSize.sm,
                  fontWeight: FontWeight.w500)),
          SizedBox(height: AppSpacing.xxs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    color: primary,
                    fontSize: highlight ? 52 : 22,
                    fontWeight: highlight ? FontWeight.w800 : FontWeight.bold,
                    letterSpacing: highlight ? -1.5 : null)),
          ),
          if (subtitle != null)
            Text(subtitle!,
                style: TextStyle(color: secondary, fontSize: AppTextSize.sm)),
        ])),
      ]);
}

class MetricRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const MetricRow(
      {super.key, required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(label,
              style: TextStyle(
                  color: AppTheme.labelGray, fontSize: AppTextSize.body))),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: AppTextSize.body,
                  color: valueColor ??
                      Theme.of(context).textTheme.bodyLarge!.color)),
        ]),
      );
}
