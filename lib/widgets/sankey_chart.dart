import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';

/// A single outflow from gross pay (a tax, deduction, or net pay).
class SankeyFlow {
  final String label;
  final double value;
  final Color color;
  const SankeyFlow({
    required this.label,
    required this.value,
    required this.color,
  });
}

/// A lightweight, dependency-free Sankey-style diagram showing how a gross
/// paycheck flows into its outflows (taxes, deductions, net pay).
///
/// Layout:
///   - Left bar  : full-height column representing [gross].
///   - Right bars: stacked vertically; each height is proportional to the
///                 outflow's share of gross.
///   - Ribbons   : cubic Bezier curves connecting the left bar to each right
///                 bar, drawn with the outflow color at low opacity.
class SankeyChart extends StatelessWidget {
  final double gross;
  final List<SankeyFlow> outflows;
  final String currencySymbol;

  /// Label shown above the left bar (default: "Gross").
  final String grossLabel;

  const SankeyChart({
    super.key,
    required this.gross,
    required this.outflows,
    this.currencySymbol = '\$',
    this.grossLabel = 'Gross',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AspectRatio(
      aspectRatio: 1.6,
      child: CustomPaint(
        painter: _SankeyPainter(
          gross: gross,
          outflows: outflows,
          textColor: theme.colorScheme.onSurface,
          mutedColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          primary: theme.colorScheme.primary,
          currencySymbol: currencySymbol,
          grossLabel: grossLabel,
        ),
      ),
    );
  }
}

class _SankeyPainter extends CustomPainter {
  final double gross;
  final List<SankeyFlow> outflows;
  final Color textColor;
  final Color mutedColor;
  final Color primary;
  final String currencySymbol;
  final String grossLabel;

  _SankeyPainter({
    required this.gross,
    required this.outflows,
    required this.textColor,
    required this.mutedColor,
    required this.primary,
    required this.currencySymbol,
    required this.grossLabel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (gross <= 0 || outflows.isEmpty) return;

    // Filter out non-positive flows
    final flows = outflows.where((f) => f.value > 0).toList();
    if (flows.isEmpty) return;

    final totalOut = flows.fold<double>(0, (s, f) => s + f.value);
    if (totalOut <= 0) return;

    // Layout constants
    const double leftX = 20;
    const double barW = 28;
    const double rightLabelW = 110;
    const double topPad = 8;
    const double bottomPad = 8;
    const double rightGap = 2; // vertical gap between right bars

    final double rightX = size.width - rightLabelW - barW;
    final double availH = size.height - topPad - bottomPad;
    final double leftH = availH;
    final double leftTop = topPad;

    // Scale right bars so total height (incl. gaps) == leftH
    final double gapTotal = rightGap * (flows.length - 1);
    final double rightTotalH = (leftH - gapTotal).clamp(0.0, leftH);

    // 1) Draw left bar (gross)
    final leftRect = Rect.fromLTWH(leftX, leftTop, barW, leftH);
    final leftPaint = Paint()..color = primary;
    canvas.drawRRect(
      RRect.fromRectAndRadius(leftRect, const Radius.circular(4)),
      leftPaint,
    );

    // 2) Compute right bar rects (top-to-bottom in flow order)
    final rightRects = <Rect>[];
    double cursor = leftTop;
    for (final f in flows) {
      final h = rightTotalH * (f.value / totalOut);
      rightRects.add(Rect.fromLTWH(rightX, cursor, barW, h));
      cursor += h + rightGap;
    }

    // 3) Draw ribbons (Bezier curves) from left bar to each right bar.
    //    Each ribbon's slice on the left side is proportional to its share
    //    of TOTAL outflow (so the left bar is fully covered by ribbons).
    double leftCursor = leftTop;
    for (var i = 0; i < flows.length; i++) {
      final f = flows[i];
      final r = rightRects[i];
      final share = f.value / totalOut;
      final leftSliceH = leftH * share;
      final leftTopY = leftCursor;
      final leftBottomY = leftCursor + leftSliceH;
      leftCursor += leftSliceH;

      final path = Path()
        ..moveTo(leftX + barW, leftTopY)
        ..cubicTo(
          leftX + barW + (rightX - leftX - barW) * 0.5,
          leftTopY,
          leftX + barW + (rightX - leftX - barW) * 0.5,
          r.top,
          rightX,
          r.top,
        )
        ..lineTo(rightX, r.bottom)
        ..cubicTo(
          leftX + barW + (rightX - leftX - barW) * 0.5,
          r.bottom,
          leftX + barW + (rightX - leftX - barW) * 0.5,
          leftBottomY,
          leftX + barW,
          leftBottomY,
        )
        ..close();

      final ribbonPaint = Paint()
        ..color = f.color.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, ribbonPaint);
    }

    // 4) Draw right bars on top of ribbons
    for (var i = 0; i < flows.length; i++) {
      final f = flows[i];
      final r = rightRects[i];
      final p = Paint()..color = f.color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(3)),
        p,
      );
    }

    // 5) Labels on the right of each right bar — with collision avoidance
    final labels = <TextPainter>[];
    final idealYs = <double>[];
    for (var i = 0; i < flows.length; i++) {
      final f = flows[i];
      final r = rightRects[i];
      final pct = (f.value / gross * 100).toStringAsFixed(1);
      final amount = _formatAmount(f.value);

      final label = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '${f.label}  $pct%\n',
              style: TextStyle(
                fontSize: AppTextSize.xs,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            TextSpan(
              text: amount,
              style: TextStyle(
                fontSize: AppTextSize.xs,
                color: mutedColor,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: rightLabelW - 6);
      labels.add(label);
      idealYs.add(r.center.dy - label.height / 2);
    }

    // Resolve overlaps: push labels down when they collide
    final resolvedYs = List<double>.from(idealYs);
    const labelGap = 2.0;
    for (var i = 1; i < resolvedYs.length; i++) {
      final prevBottom = resolvedYs[i - 1] + labels[i - 1].height + labelGap;
      if (resolvedYs[i] < prevBottom) {
        resolvedYs[i] = prevBottom;
      }
    }
    // If last label overflows bottom, shift all up proportionally
    if (resolvedYs.isNotEmpty) {
      final lastBottom =
          resolvedYs.last + labels.last.height;
      if (lastBottom > size.height) {
        final shift = lastBottom - size.height;
        for (var i = 0; i < resolvedYs.length; i++) {
          resolvedYs[i] = (resolvedYs[i] - shift).clamp(0.0, size.height);
        }
        // Re-resolve after shifting up
        for (var i = 1; i < resolvedYs.length; i++) {
          final prevBottom =
              resolvedYs[i - 1] + labels[i - 1].height + labelGap;
          if (resolvedYs[i] < prevBottom) {
            resolvedYs[i] = prevBottom;
          }
        }
      }
    }

    for (var i = 0; i < labels.length; i++) {
      labels[i].paint(canvas, Offset(rightX + barW + 6, resolvedYs[i]));
    }

    // 6) "Gross" label above the left bar
    final grossLabelPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$grossLabel\n',
            style: TextStyle(
              fontSize: AppTextSize.xs,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          TextSpan(
            text: _formatAmount(gross),
            style: TextStyle(fontSize: AppTextSize.xs, color: mutedColor),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 80);
    grossLabelPainter.paint(
      canvas,
      Offset(leftX + barW / 2 - grossLabelPainter.width / 2, 0),
    );
  }

  String _formatAmount(double v) {
    // Simple thousands separator without pulling intl into the painter.
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '$currencySymbol${buf.toString()}';
  }

  @override
  bool shouldRepaint(covariant _SankeyPainter old) =>
      old.gross != gross ||
      old.outflows != outflows ||
      old.textColor != textColor;
}
