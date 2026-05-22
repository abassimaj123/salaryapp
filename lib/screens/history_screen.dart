import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/analytics/analytics_service.dart';
import '../core/flavor_config.dart';
import '../core/db/database_service.dart';
import 'history_detail_screen.dart';
import '../core/freemium/freemium_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../l10n/strings_fr.dart';
import '../widgets/premium_cta_widget.dart';
import '../main.dart' show isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart' show CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    analyticsService.logHistoryViewed();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DatabaseService.instance.getAll();
    if (mounted)
      setState(() {
        _entries = data;
        _loading = false;
      });
  }

  Future<void> _delete(int id) async {
    await DatabaseService.instance.delete(id);
    _load();
  }

  Future<void> _confirmClearAll(bool fr, bool es) async {
    final title = fr
        ? "Effacer l'historique"
        : (es ? 'Borrar historial' : 'Clear History');
    final body = fr
        ? 'Supprimer tous les calculs ?'
        : (es ? '¿Eliminar todos los cálculos?' : 'Delete all calculations?');
    final cancel = fr ? 'Annuler' : (es ? 'Cancelar' : 'Cancel');
    final ok = fr ? 'Supprimer' : (es ? 'Eliminar' : 'Delete');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ok,
                style: TextStyle(color: CalcwiseSemanticColors.errorDark)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseService.instance.clearAll();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final title = fr
            ? AppStringsFR.history
            : (es ? AppStringsES.history : AppStringsEN.history);
        final empty = fr
            ? AppStringsFR.historyEmpty
            : (es ? AppStringsES.historyEmpty : AppStringsEN.historyEmpty);
        final limitMsg = fr
            ? AppStringsFR.historyLimit
            : (es ? AppStringsES.historyLimit : AppStringsEN.historyLimit);

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (_entries.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.delete_sweep_rounded),
                  tooltip:
                      fr ? 'Tout effacer' : (es ? 'Borrar todo' : 'Clear All'),
                  onPressed: () => _confirmClearAll(fr, es),
                ),
              IconButton(
                icon: Icon(Icons.refresh_rounded),
                onPressed: _load,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(child: _buildBody(empty, limitMsg, fr, es)),
              const CalcwiseAdFooter(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(String empty, String limitMsg, bool fr, bool es) {
    if (_loading) {
      return const _HistorySkeleton();
    }

    if (_entries.isEmpty) {
      return CalcwiseEmptyState(
        icon: Icons.history_edu_rounded,
        title: fr
            ? 'Aucun calcul sauvegardé'
            : es
                ? 'Sin cálculos guardados'
                : 'No saved calculations',
        body: empty,
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (_, isPremium, __) {
        final showCta = !isPremium;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            if (!isPremium) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.mdPlus, vertical: AppSpacing.smPlus),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Icon(Icons.lock_outline, color: AppTheme.warning, size: 18),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(limitMsg,
                        style: TextStyle(
                            color: AppTheme.warning,
                            fontSize: AppTextSize.md,
                            fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
              SizedBox(height: AppSpacing.md),
            ],
            ..._entries.map(
              (e) => _HistoryCard(
                entry: e,
                fr: fr,
                es: es,
                onDelete: () => _delete(e.id!),
                onTap: () => Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) =>
                          HistoryDetailScreen(entry: e),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                      transitionDuration: AppDuration.base,
                    )),
              ),
            ),
            if (showCta) ...[
              SizedBox(height: AppSpacing.sm),
              PremiumCtaWidget(
                feature: fr
                    ? 'Historique illimité'
                    : (es ? 'Historial ilimitado' : 'Unlimited History'),
                compact: true,
              ),
            ],
          ],
        );
      },
    );
  }
}

// ─── History card ─────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  final bool fr, es;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.entry,
    required this.fr,
    required this.es,
    required this.onDelete,
    required this.onTap,
  });

  String _fmt(double v) {
    final symbol =
        entry.flavor == 'uk' ? '£' : (entry.flavor == 'ca' ? 'CA\$' : '\$');
    return NumberFormat.currency(symbol: symbol, decimalDigits: 0).format(v);
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy  HH:mm').format(entry.timestamp);
    final grossLabel = fr ? 'Brut' : (es ? 'Bruto' : 'Gross');
    final netLabel = fr ? 'Net' : (es ? 'Neto' : 'Net');
    final rateLabel = fr ? 'Taux' : (es ? 'Tasa' : 'Rate');

    final regionBadge = entry.region.isNotEmpty
        ? Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(entry.region,
                style: TextStyle(
                    fontSize: AppTextSize.xs,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600)),
          )
        : const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.smPlus),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.schedule, size: 14, color: AppTheme.labelGray),
              SizedBox(width: AppSpacing.xs),
              Text(dateStr,
                  style: TextStyle(
                      color: AppTheme.labelGray, fontSize: AppTextSize.sm)),
              const Spacer(),
              regionBadge,
              SizedBox(width: AppSpacing.sm),
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.xs),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: AppTheme.labelGray),
                ),
              ),
            ]),
            SizedBox(height: AppSpacing.smPlus),
            Row(children: [
              _StatCell(
                  label: grossLabel, value: _fmt(entry.result.grossAnnual)),
              SizedBox(width: AppSpacing.md),
              _StatCell(
                  label: netLabel,
                  value: _fmt(entry.result.netAnnual),
                  color: AppTheme.success),
              SizedBox(width: AppSpacing.md),
              _StatCell(
                  label: rateLabel,
                  value: '${entry.result.effectiveRate.toStringAsFixed(1)}%',
                  color: CalcwiseSemanticColors.errorDark),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _StatCell({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style:
              TextStyle(color: AppTheme.labelGray, fontSize: AppTextSize.xs)),
      SizedBox(height: AppSpacing.xxs),
      Text(value,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppTextSize.body,
              color: color ?? Theme.of(context).textTheme.bodyLarge?.color)),
    ]);
  }
}

// ─── History skeleton ─────────────────────────────────────────────────────────

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.smPlus),
        child: _SkeletonCard(),
      ),
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8E8E8);
    final shine = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: 88,
        decoration: BoxDecoration(
          color: Color.lerp(base, shine, _anim.value),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
    );
  }
}
