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
import '../widgets/app_bar_actions.dart';
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
            child: Text(ok, style: TextStyle(color: Colors.red)),
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
              const AppBarActions(),
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
      return Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history_rounded,
                size: 44, color: AppTheme.labelGray.withValues(alpha: 0.4)),
            SizedBox(height: 16),
            Text(empty,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.labelGray, fontSize: AppTextSize.bodyMd)),
          ]),
        ),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Icon(Icons.lock_outline, color: AppTheme.warning, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(limitMsg,
                        style: TextStyle(
                            color: AppTheme.warning,
                            fontSize: AppTextSize.md,
                            fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
              SizedBox(height: 12),
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
              SizedBox(height: 8),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.schedule, size: 14, color: AppTheme.labelGray),
              SizedBox(width: 4),
              Text(dateStr,
                  style: TextStyle(
                      color: AppTheme.labelGray, fontSize: AppTextSize.sm)),
              const Spacer(),
              regionBadge,
              SizedBox(width: 8),
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
            SizedBox(height: 10),
            Row(children: [
              _StatCell(
                  label: grossLabel, value: _fmt(entry.result.grossAnnual)),
              SizedBox(width: 12),
              _StatCell(
                  label: netLabel,
                  value: _fmt(entry.result.netAnnual),
                  color: AppTheme.success),
              SizedBox(width: 12),
              _StatCell(
                  label: rateLabel,
                  value: '${entry.result.effectiveRate.toStringAsFixed(1)}%',
                  color: Colors.redAccent),
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
      SizedBox(height: 2),
      Text(value,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: AppTextSize.body,
              color: color ?? Theme.of(context).textTheme.bodyLarge?.color)),
    ]);
  }
}
