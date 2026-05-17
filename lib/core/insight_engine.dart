import 'package:calcwise_core/calcwise_core.dart' show Insight, InsightSeverity;

// ── Engine ────────────────────────────────────────────────────────────────────

class InsightEngine {
  InsightEngine._();

  /// Returns up to [maxCount] salary insights (alerts first) derived from
  /// the US-flavor SalaryResult fields.
  static List<Insight> generate({
    required double grossAnnual,
    required double netAnnual,
    required double federalTax,
    required double stateTax,
    required double ficaTax, // SS + Medicare combined
    required double
        federalBracketPct, // top bracket rate as decimal (e.g. 0.22)
    bool isEs = false,
    bool isFr = false,
    int maxCount = 3,
  }) {
    if (grossAnnual <= 0) return [];
    final insights = <Insight>[];

    final totalTaxes = federalTax + stateTax + ficaTax;
    final effectivePct = totalTaxes / grossAnnual * 100;

    // ── 1. Effective tax rate alert ───────────────────────────────────────────
    if (effectivePct > 35) {
      insights.add(Insight(
        severity: InsightSeverity.alert,
        title: isFr
            ? 'Fardeau fiscal élevé'
            : isEs
                ? 'Alta carga fiscal'
                : 'High Tax Burden',
        body: isFr
            ? 'Votre taux effectif de ${effectivePct.toStringAsFixed(1)}% — médiane canadienne ~27% pour revenu moyen. Envisagez des déductions supplémentaires.'
            : isEs
                ? 'Su tasa efectiva de ${effectivePct.toStringAsFixed(1)}% — mediana EE.UU. ~24% para ingresos medios. Considera maximizar deducciones.'
                : 'Your effective rate of ${effectivePct.toStringAsFixed(1)}% — US median is ~24% for middle-income earners. Consider maximizing deductions.',
      ));
    } else if (effectivePct >= 25) {
      insights.add(Insight(
        severity: InsightSeverity.warning,
        title: isFr
            ? 'Charge fiscale modérée'
            : isEs
                ? 'Carga fiscal moderada'
                : 'Moderate Tax Burden',
        body: isFr
            ? 'Votre taux effectif de ${effectivePct.toStringAsFixed(1)}% — médiane canadienne ~27% pour revenu moyen.'
            : isEs
                ? 'Su tasa efectiva de ${effectivePct.toStringAsFixed(1)}% — mediana EE.UU. ~24% para ingresos medios.'
                : 'Your effective rate of ${effectivePct.toStringAsFixed(1)}% — US median is ~24% for middle-income earners.',
      ));
    } else {
      insights.add(Insight(
        severity: InsightSeverity.good,
        title: isFr
            ? 'Taux d\'imposition sain'
            : isEs
                ? 'Tasa fiscal saludable'
                : 'Healthy Tax Rate',
        body: isFr
            ? 'Votre taux effectif de ${effectivePct.toStringAsFixed(1)}% — médiane canadienne ~27% pour revenu moyen. Bonne position fiscale.'
            : isEs
                ? 'Su tasa efectiva de ${effectivePct.toStringAsFixed(1)}% — mediana EE.UU. ~24% para ingresos medios. Buena posición fiscal.'
                : 'Your effective rate of ${effectivePct.toStringAsFixed(1)}% — US median is ~24% for middle-income earners. Healthy position.',
      ));
    }

    // ── 2. Take-home percentage ───────────────────────────────────────────────
    final takeHomePct = (netAnnual / grossAnnual * 100).roundToDouble();
    insights.add(Insight(
      severity: InsightSeverity.good,
      title: isFr
          ? 'Salaire net conservé'
          : isEs
              ? 'Salario neto retenido'
              : 'Take-Home Share',
      body: isFr
          ? 'Vous conservez ${takeHomePct.toStringAsFixed(0)}% de votre salaire brut comme revenu net.'
          : isEs
              ? 'Conservas el ${takeHomePct.toStringAsFixed(0)}% de tu salario bruto como ingreso neto.'
              : 'You keep ${takeHomePct.toStringAsFixed(0)}% of your gross pay as take-home.',
    ));

    // ── 3. Top federal bracket tip ────────────────────────────────────────────
    if (federalBracketPct >= 0.24) {
      final bracketPct = (federalBracketPct * 100).round();
      insights.add(Insight(
        severity: InsightSeverity.warning,
        title: isFr
            ? 'Tranche marginale élevée'
            : isEs
                ? 'Tramo federal alto'
                : 'High Federal Bracket',
        body: isFr
            ? 'Vous êtes dans le tranche à $bracketPct% — envisagez de maximiser vos contributions REER pour réduire le revenu imposable.'
            : isEs
                ? 'Estás en el tramo federal del $bracketPct% — considera maximizar contribuciones al 401(k) para reducir tu ingreso gravable.'
                : 'You\'re in the $bracketPct% federal bracket — consider maximizing 401(k) contributions to reduce taxable income.',
      ));
    }

    // ── 4. Annual vs monthly vs hourly perspective ────────────────────────────
    if (grossAnnual >= 20000) {
      final monthly = (netAnnual / 12).roundToDouble();
      final hourly = (netAnnual / 2080);
      insights.add(Insight(
        severity: InsightSeverity.good,
        title: isFr
            ? 'Décomposition du revenu net'
            : isEs
                ? 'Desglose de ingreso neto'
                : 'Net Pay Breakdown',
        body: isFr
            ? 'Votre revenu net de ${_fmt(netAnnual)}/an = ${_fmt(monthly)}/mois = ${_fmtDec(hourly)}/h (base 2 080 h/an).'
            : isEs
                ? 'Tu ingreso neto de ${_fmt(netAnnual)}/año = ${_fmt(monthly)}/mes = ${_fmtDec(hourly)}/hora (base 2 080 h/año).'
                : 'Your net pay of ${_fmt(netAnnual)}/year = ${_fmt(monthly)}/month = ${_fmtDec(hourly)}/hour (based on 2,080 work hours).',
      ));
    }

    // ── 5. FICA breakdown ─────────────────────────────────────────────────────
    if (ficaTax > 0 && grossAnnual > 0) {
      final ficaPct = (ficaTax / grossAnnual * 100).toStringAsFixed(1);
      insights.add(Insight(
        severity: InsightSeverity.good,
        title: isFr
            ? 'FICA (RAS + Assurance maladie)'
            : isEs
                ? 'Contribuciones FICA'
                : 'FICA Contributions',
        body: isFr
            ? 'Sécurité sociale + Medicare = ${_fmt(ficaTax)}/an ($ficaPct% du brut).'
            : isEs
                ? 'Seguridad Social + Medicare = ${_fmt(ficaTax)}/año ($ficaPct% del bruto).'
                : 'Social Security + Medicare = ${_fmt(ficaTax)}/year ($ficaPct% of gross).',
      ));
    }

    // Prioritise alerts > warnings > good, cap at maxCount
    final alerts =
        insights.where((i) => i.severity == InsightSeverity.alert).toList();
    final warnings =
        insights.where((i) => i.severity == InsightSeverity.warning).toList();
    final goods =
        insights.where((i) => i.severity == InsightSeverity.good).toList();
    final ordered = [...alerts, ...warnings, ...goods];
    if (ordered.isEmpty) {
      ordered.add(Insight(
        severity: InsightSeverity.good,
        title: isFr
            ? 'Calcul Terminé'
            : isEs
                ? 'Cálculo Completado'
                : 'Calculation Complete',
        body: isFr
            ? 'Faites défiler vers le bas pour voir le détail complet.'
            : isEs
                ? 'Desplázate hacia abajo para ver el desglose completo.'
                : 'Scroll down to see the full breakdown.',
      ));
    }
    return ordered.take(maxCount).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  /// Derive the top US federal bracket rate (as decimal) from gross annual income.
  static double usFederalBracketPct(double grossAnnual) {
    if (grossAnnual <= 11600) return 0.10;
    if (grossAnnual <= 47150) return 0.12;
    if (grossAnnual <= 100525) return 0.22;
    if (grossAnnual <= 191950) return 0.24;
    if (grossAnnual <= 243725) return 0.32;
    if (grossAnnual <= 609350) return 0.35;
    return 0.37;
  }

  static String _fmt(double amount) {
    final abs = amount.abs();
    String str;
    if (abs >= 1000000) {
      str = '\$${(abs / 1000000).toStringAsFixed(2)}M';
    } else if (abs >= 1000) {
      str = '\$${(abs / 1000).toStringAsFixed(1)}K';
    } else {
      str = '\$${abs.toStringAsFixed(0)}';
    }
    return amount < 0 ? '-$str' : str;
  }

  static String _fmtDec(double amount) {
    return '\$${amount.toStringAsFixed(2)}';
  }
}
