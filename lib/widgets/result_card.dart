import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class ResultCard extends StatelessWidget {
  final String label, value;
  final String? subtitle;
  final IconData? icon;
  final bool highlight;
  const ResultCard({super.key, required this.label, required this.value,
      this.subtitle, this.icon, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    if (highlight) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.2),
              blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: _content(Colors.white, Colors.white70),
      );
    }
    return Card(child: Padding(
      padding: const EdgeInsets.all(16),
      child: _content(Theme.of(context).textTheme.titleLarge!.color!, AppTheme.labelGray),
    ));
  }

  Widget _content(Color primary, Color secondary) => Row(children: [
    if (icon != null) ...[Icon(icon, color: primary.withValues(alpha: 0.8), size: 22), const SizedBox(width: 12)],
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: secondary, fontSize: 12, fontWeight: FontWeight.w500)),
      const SizedBox(height: 2),
      Text(value, style: TextStyle(color: primary, fontSize: 22, fontWeight: FontWeight.bold)),
      if (subtitle != null) Text(subtitle!, style: TextStyle(color: secondary, fontSize: 12)),
    ])),
  ]);
}

class MetricRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const MetricRow({super.key, required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: AppTheme.labelGray, fontSize: 14)),
      Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
          color: valueColor ?? Theme.of(context).textTheme.bodyLarge!.color)),
    ]),
  );
}
