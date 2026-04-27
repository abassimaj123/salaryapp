import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/flavor_config.dart';
import '../core/db/database_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../l10n/strings_fr.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/premium_cta_widget.dart';
import '../main.dart' show altLanguageNotifier;

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
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DatabaseService.instance.getAll();
    if (mounted) setState(() { _entries = data; _loading = false; });
  }

  Future<void> _delete(int id) async {
    await DatabaseService.instance.delete(id);
    _load();
  }

  Future<void> _confirmClearAll(bool fr, bool es) async {
    final title  = fr ? "Effacer l'historique" : (es ? 'Borrar historial' : 'Clear History');
    final body   = fr ? 'Supprimer tous les calculs ?' : (es ? '¿Eliminar todos los cálculos?' : 'Delete all calculations?');
    final cancel = fr ? 'Annuler' : (es ? 'Cancelar' : 'Cancel');
    final ok     = fr ? 'Supprimer' : (es ? 'Eliminar' : 'Delete');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ok, style: const TextStyle(color: Colors.red)),
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
      valueListenable: altLanguageNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final title   = fr ? AppStringsFR.history : (es ? AppStringsES.history : AppStringsEN.history);
        final empty   = fr ? AppStringsFR.historyEmpty : (es ? AppStringsES.historyEmpty : AppStringsEN.historyEmpty);
        final limitMsg = fr ? AppStringsFR.historyLimit : (es ? AppStringsES.historyLimit : AppStringsEN.historyLimit);

        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              if (_entries.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: fr ? 'Tout effacer' : (es ? 'Borrar todo' : 'Clear All'),
                  onPressed: () => _confirmClearAll(fr, es),
                ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(child: _buildBody(empty, limitMsg, fr, es)),
              const BannerAdWidget(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(String empty, String limitMsg, bool fr, bool es) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.history_outlined, size: 72, color: AppTheme.labelGray.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(empty,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.labelGray, fontSize: 15)),
          ]),
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (_, isPremium, __) {
        final showCta = !isPremium;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!isPremium) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.lock_outline, color: AppTheme.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(limitMsg,
                        style: const TextStyle(
                            color: AppTheme.warning, fontSize: 13, fontWeight: FontWeight.w500)),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            ..._entries.map((e) => _HistoryCard(
                  entry: e,
                  fr: fr,
                  es: es,
                  onDelete: () => _delete(e.id!),
                )),
            if (showCta) ...[
              const SizedBox(height: 8),
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

  const _HistoryCard({
    required this.entry,
    required this.fr,
    required this.es,
    required this.onDelete,
  });

  String _fmt(double v) {
    final symbol = entry.flavor == 'uk'
        ? '£'
        : (entry.flavor == 'ca' ? 'CA\$' : '\$');
    return NumberFormat.currency(symbol: symbol, decimalDigits: 0).format(v);
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy  HH:mm').format(entry.timestamp);
    final grossLabel = fr ? 'Brut' : (es ? 'Bruto' : 'Gross');
    final netLabel   = fr ? 'Net'  : (es ? 'Neto'  : 'Net');
    final rateLabel  = fr ? 'Taux' : (es ? 'Tasa'  : 'Rate');

    final regionBadge = entry.region.isNotEmpty
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(entry.region,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w600)),
          )
        : const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.schedule, size: 14, color: AppTheme.labelGray),
            const SizedBox(width: 4),
            Text(dateStr,
                style: const TextStyle(color: AppTheme.labelGray, fontSize: 12)),
            const Spacer(),
            regionBadge,
            const SizedBox(width: 8),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 16, color: AppTheme.labelGray),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _StatCell(label: grossLabel, value: _fmt(entry.result.grossAnnual)),
            const SizedBox(width: 12),
            _StatCell(
                label: netLabel,
                value: _fmt(entry.result.netAnnual),
                color: AppTheme.success),
            const SizedBox(width: 12),
            _StatCell(
                label: rateLabel,
                value: '${entry.result.effectiveRate.toStringAsFixed(1)}%',
                color: Colors.redAccent),
          ]),
        ]),
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
          style: const TextStyle(color: AppTheme.labelGray, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: color ?? Theme.of(context).textTheme.bodyLarge?.color)),
    ]);
  }
}
