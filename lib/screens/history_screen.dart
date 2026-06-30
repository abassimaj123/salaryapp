import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/analytics/analytics_service.dart';
import '../core/flavor_config.dart';
import '../core/db/database_service.dart';
import '../core/salary_engine.dart' show SalaryResult;
import 'history_detail_screen.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../l10n/strings_fr.dart';
import '../main.dart' show isSpanishNotifier, historyService;
import 'package:calcwise_core/calcwise_core.dart' show CalcwiseAdFooter;
import 'package:calcwise_core/calcwise_core.dart' hide HistoryEntry;
import 'package:calcwise_core/calcwise_core.dart' as core show HistoryEntry;

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.showAppBar = false});
  final bool showAppBar;

  static final refreshNotifier = ValueNotifier<int>(0);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

/// Human-readable labels for the non-calculator save-capable tools, keyed by
/// screenId. Used to render a generic history card/detail for tools that
/// don't share the calculator's [SalaryResult] schema.
const Map<String, String> _kToolLabelsEn = {
  'benefits': 'Benefits Calculator',
  'bonus': 'Bonus Calculator',
  'raise': 'Raise Calculator',
  'retirement_optimizer': 'Retirement Optimizer',
  'rrsp_optimizer': 'RRSP Optimizer',
  'salary_comparison': 'Salary Comparison',
  'tax_breakdown': 'Tax Breakdown',
  'w4_wizard': 'W-4 Wizard',
};
const Map<String, String> _kToolLabelsFr = {
  'benefits': 'Avantages sociaux',
  'bonus': 'Calculateur de prime',
  'raise': 'Calculateur d’augmentation',
  'retirement_optimizer': 'Optimiseur de retraite',
  'rrsp_optimizer': 'Optimiseur REER',
  'salary_comparison': 'Comparaison de salaire',
  'tax_breakdown': 'Répartition fiscale',
  'w4_wizard': 'Assistant W-4',
};
const Map<String, String> _kToolLabelsEs = {
  'benefits': 'Calculadora de beneficios',
  'bonus': 'Calculadora de bono',
  'raise': 'Calculadora de aumento',
  'retirement_optimizer': 'Optimizador de jubilación',
  'rrsp_optimizer': 'Optimizador RRSP',
  'salary_comparison': 'Comparación de salario',
  'tax_breakdown': 'Desglose de impuestos',
  'w4_wizard': 'Asistente W-4',
};

String _toolLabel(String screenId, bool fr, bool es) {
  final map = fr ? _kToolLabelsFr : (es ? _kToolLabelsEs : _kToolLabelsEn);
  return map[screenId] ?? screenId;
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<HistoryEntry> _pinned = [];
  List<HistoryEntry> _recent = [];
  // Entries from the other 8 save-capable tools (benefits, bonus, raise,
  // retirement_optimizer, rrsp_optimizer, salary_comparison, tax_breakdown,
  // w4_wizard). They don't share the calculator's SalaryResult schema, so
  // they're displayed with a generic l1-based card/detail instead of being
  // forced through [_HistoryCard] / [HistoryDetailScreen].
  List<core.HistoryEntry> _otherPinned = [];
  List<core.HistoryEntry> _otherRecent = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    analyticsService.logScreenView('history');
    analyticsService.logHistoryViewed();
    _load();
    HistoryScreen.refreshNotifier.addListener(_load);
  }

  @override
  void dispose() {
    HistoryScreen.refreshNotifier.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // No screenId filter: History shows entries from every save-capable tool
    // (calculator, benefits, bonus, raise, retirement_optimizer,
    // rrsp_optimizer, salary_comparison, tax_breakdown, w4_wizard) since none
    // of them have a dedicated history view of their own.
    final data = await historyService.getHistory('salaryapp');
    if (!mounted) return;

    // Calculator entries share the SalaryResult schema → typed flow.
    final calcEntries = data.where((e) => e.screenId == 'calculator').toList();
    // Convert calcwise_core HistoryEntry → local HistoryEntry via l2 snapshot.
    // Filter out stale entries saved before the l2 schema was in place (grossAnnual=0).
    final local = calcEntries
        .map(_coreToLocal)
        .where((e) => e.result.grossAnnual > 0)
        .toList();

    // The other 8 save-capable tools (benefits, bonus, raise,
    // retirement_optimizer, rrsp_optimizer, salary_comparison, tax_breakdown,
    // w4_wizard) use their own l1/l2 schemas — shown via a generic card.
    final otherEntries =
        data.where((e) => e.screenId != 'calculator').toList();

    setState(() {
      _pinned = local.where((e) => e.isPinned).toList();
      _recent = local.where((e) => !e.isPinned).toList();
      _otherPinned = otherEntries.where((e) => e.isPinned).toList();
      _otherRecent = otherEntries.where((e) => !e.isPinned).toList();
      _loading = false;
    });
  }

  /// Converts a calcwise_core [HistoryEntry] (l1/l2 schema) back to the local
  /// [HistoryEntry] (SalaryResult schema) used by [_HistoryCard] and
  /// [HistoryDetailScreen].
  static HistoryEntry _coreToLocal(core.HistoryEntry e) {
    final results = (e.l2['results'] as Map?)?.cast<String, dynamic>() ?? {};
    final inputs  = (e.l2['inputs']  as Map?)?.cast<String, dynamic>() ?? {};
    return HistoryEntry(
      id:        e.id,
      flavor:    (inputs['flavor']  as String?)  ?? '',
      region:    (inputs['region']  as String?)  ?? '',
      timestamp: e.savedAt,
      result:    SalaryResult.fromMap({
        'grossAnnual':   (results['grossAnnual']   as num?)?.toDouble() ?? 0.0,
        'federalTax':    (results['federalTax']    as num?)?.toDouble() ?? 0.0,
        'ficaTax':       (results['ficaTax']       as num?)?.toDouble() ?? 0.0,
        'stateTax':      (results['stateTax']      as num?)?.toDouble() ?? 0.0,
        'totalTax':      (results['totalTax']      as num?)?.toDouble() ?? 0.0,
        'netAnnual':     (results['netAnnual']     as num?)?.toDouble() ?? 0.0,
        'netMonthly':    (results['netMonthly']    as num?)?.toDouble() ?? 0.0,
        'netBiWeekly':   (results['netBiWeekly']   as num?)?.toDouble() ?? 0.0,
        'netWeekly':     (results['netWeekly']     as num?)?.toDouble() ?? 0.0,
        'effectiveRate': (results['effectiveRate'] as num?)?.toDouble() ?? 0.0,
      }),
      isPinned:  e.isPinned,
      inputHash: e.resultHash,
      pinLabel:  e.pinLabel,
      pinOrder:  e.pinOrder,
    );
  }

  Future<void> _delete(int id) async {
    HapticFeedback.mediumImpact();
    await historyService.delete(id);
    if (!mounted) return;
    _load();
  }

  Future<void> _unpin(int id) async {
    HapticFeedback.mediumImpact();
    await historyService.unpin(id);
    if (!mounted) return;
    _load();
  }

  Future<void> _rename(HistoryEntry e, bool fr, bool es) async {
    final controller = TextEditingController(text: e.pinLabel ?? '');
    final title = fr
        ? 'Renommer le scénario'
        : (es ? 'Renombrar escenario' : 'Rename Scenario');
    final hint =
        fr ? 'Nom du scénario' : (es ? 'Nombre del escenario' : 'Scenario name');
    final cancel = fr ? 'Annuler' : (es ? 'Cancelar' : 'Cancel');
    final save = fr ? 'Enregistrer' : (es ? 'Guardar' : 'Save');
    final newLabel = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(cancel)),
          FilledButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(context, controller.text);
              },
              child: Text(save)),
        ],
      ),
    );
    controller.dispose();
    if (newLabel != null && newLabel.trim().isNotEmpty && e.id != null) {
      await historyService.rename(e.id!, newLabel.trim());
      if (!mounted) return;
      _load();
    }
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
                style: TextStyle(
                    color: CalcwiseSemanticColors.error(
                        Theme.of(context).brightness))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      HapticFeedback.mediumImpact();
      await DatabaseService.instance.clearAll();
      if (!mounted) return;
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

        final hasEntries = _pinned.isNotEmpty ||
            _recent.isNotEmpty ||
            _otherPinned.isNotEmpty ||
            _otherRecent.isNotEmpty;

        final bodyContent = Column(
          children: [
            Expanded(child: _buildBody(empty, limitMsg, fr, es)),
            const CalcwiseAdFooter(),
          ],
        );
        return widget.showAppBar
            ? Scaffold(
                appBar: AppBar(
                  title: Text(title),
                  actions: [
                    if (hasEntries)
                      IconButton(
                        icon: Icon(Icons.delete_sweep_rounded),
                        tooltip: fr
                            ? 'Tout effacer'
                            : (es ? 'Borrar todo' : 'Clear All'),
                        onPressed: () => _confirmClearAll(fr, es),
                      ),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded),
                      tooltip: fr
                          ? 'Actualiser'
                          : (es ? 'Actualizar' : 'Refresh'),
                      onPressed: _load,
                    ),
                  ],
                ),
                body: CalcwisePageEntrance(child: bodyContent),
              )
            : bodyContent;
      },
    );
  }

  Widget _buildBody(String empty, String limitMsg, bool fr, bool es) {
    if (_loading) {
      return const _HistorySkeleton();
    }

    if (_pinned.isEmpty &&
        _recent.isEmpty &&
        _otherPinned.isEmpty &&
        _otherRecent.isEmpty) {
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
      valueListenable: freemiumService.hasFullAccessNotifier,
      builder: (_, isPremium, __) {
        // Free users only ever see up to freeRingBufferSize recent calculations.
        final recentVisible = isPremium
            ? _recent
            : _recent.take(MonetizationConfig.freeRingBufferSize).toList();

        // Apply search filter.
        bool matchesQuery(HistoryEntry e) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          final label = (e.pinLabel ?? '').toLowerCase();
          final gross = e.result.grossAnnual.toStringAsFixed(0).toLowerCase();
          final region = e.region.toLowerCase();
          return label.contains(q) ||
              gross.contains(q) ||
              region.contains(q);
        }

        // Other-tool entries follow the same free-tier ring-buffer limit.
        final otherRecentVisible = isPremium
            ? _otherRecent
            : _otherRecent.take(MonetizationConfig.freeRingBufferSize).toList();

        bool matchesQueryOther(core.HistoryEntry e) {
          if (_searchQuery.isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          final label = (e.pinLabel ?? '').toLowerCase();
          final tool = _toolLabel(e.screenId, fr, es).toLowerCase();
          return label.contains(q) || tool.contains(q);
        }

        final filteredPinned = _pinned.where(matchesQuery).toList();
        final filteredRecent = recentVisible.where(matchesQuery).toList();
        final filteredOtherPinned = _otherPinned.where(matchesQueryOther).toList();
        final filteredOtherRecent =
            otherRecentVisible.where(matchesQueryOther).toList();
        final noResults = _searchQuery.isNotEmpty &&
            filteredPinned.isEmpty &&
            filteredRecent.isEmpty &&
            filteredOtherPinned.isEmpty &&
            filteredOtherRecent.isEmpty;

        final savedHeader = fr
            ? 'Scénarios enregistrés'
            : (es ? 'Escenarios guardados' : 'Saved Scenarios');
        final recentHeader = fr
            ? 'Calculs récents'
            : (es ? 'Cálculos recientes' : 'Recent Calculations');
        final otherToolsHeader = fr
            ? 'Autres outils'
            : (es ? 'Otras herramientas' : 'Other Tools');

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            CalcwiseSearchBar(
              onChanged: (q) => setState(() => _searchQuery = q),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (noResults)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxxl),
                child: CalcwiseEmptyState(
                  icon: Icons.search_off_rounded,
                  title: fr
                      ? 'Aucun résultat'
                      : (es ? 'Sin resultados' : 'No results found'),
                ),
              )
            else ...[
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

            // ── Saved Scenarios (pinned) ────────────────────────────────────
            if (filteredPinned.isNotEmpty) ...[
              _SectionHeader(label: savedHeader, icon: Icons.bookmark_rounded),
              SizedBox(height: AppSpacing.sm),
              ...filteredPinned.map((e) => _HistoryCard(
                    entry: e,
                    fr: fr,
                    es: es,
                    isPremium: isPremium,
                    onDelete: () => _delete(e.id!),
                    onUnpin: () => _unpin(e.id!),
                    onRename: () => _rename(e, fr, es),
                    onTap: () => _openDetail(e),
                  )),
              SizedBox(height: AppSpacing.md),
            ],

            // ── Recent Calculations (auto-saved) ────────────────────────────
            if (filteredRecent.isNotEmpty) ...[
              _SectionHeader(label: recentHeader, icon: Icons.schedule_rounded),
              SizedBox(height: AppSpacing.sm),
              ...filteredRecent.map((e) => _HistoryCard(
                    entry: e,
                    fr: fr,
                    es: es,
                    isPremium: isPremium,
                    onDelete: () => _delete(e.id!),
                    onUnpin: () => _unpin(e.id!),
                    onRename: () => _rename(e, fr, es),
                    onTap: () => _openDetail(e),
                  )),
            ],

            // ── Other Tools (benefits, bonus, raise, retirement/RRSP
            // optimizer, salary comparison, tax breakdown, W-4 wizard) ──────
            if (filteredOtherPinned.isNotEmpty ||
                filteredOtherRecent.isNotEmpty) ...[
              SizedBox(height: AppSpacing.md),
              _SectionHeader(
                  label: otherToolsHeader, icon: Icons.apps_rounded),
              SizedBox(height: AppSpacing.sm),
              ...filteredOtherPinned.map((e) => _GenericToolCard(
                    entry: e,
                    fr: fr,
                    es: es,
                    isPremium: isPremium,
                    onDelete: () => _delete(e.id!),
                    onUnpin: () => _unpin(e.id!),
                    onTap: () => _openGenericDetail(e, fr, es),
                  )),
              ...filteredOtherRecent.map((e) => _GenericToolCard(
                    entry: e,
                    fr: fr,
                    es: es,
                    isPremium: isPremium,
                    onDelete: () => _delete(e.id!),
                    onUnpin: () => _unpin(e.id!),
                    onTap: () => _openGenericDetail(e, fr, es),
                  )),
            ],

            if (!isPremium) ...[
              SizedBox(height: AppSpacing.sm),
              CalcwisePremiumGate(
                title: fr
                    ? 'Historique illimité'
                    : (es ? 'Historial ilimitado' : 'Unlimited History'),
                description: fr
                    ? 'Sauvegardez tous vos calculs sans limite'
                    : (es
                        ? 'Guarda todos tus cálculos sin límite'
                        : 'Save all your calculations with no limit'),
                onUnlock: () => PaywallHard.show(context),
                price: IAPService.instance.localizedPrice,
              ),
            ],
            ], // end else (noResults)
          ],
        );
      },
    );
  }

  void _openDetail(HistoryEntry e) => Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => HistoryDetailScreen(entry: e),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
          transitionDuration: AppDuration.base,
        ),
      );

  /// Generic detail view for the 8 non-calculator tools: shows the l2
  /// snapshot's inputs/results as plain label/value rows. These tools don't
  /// share the calculator's SalaryResult schema, so a typed detail screen
  /// (like [HistoryDetailScreen]) isn't viable without per-tool views.
  void _openGenericDetail(core.HistoryEntry e, bool fr, bool es) {
    final title = _toolLabel(e.screenId, fr, es);
    final dateStr = DateFormat('MMM d, yyyy  HH:mm', fr ? 'fr' : (es ? 'es' : 'en'))
        .format(e.savedAt);
    final inputs = (e.l2['inputs'] as Map?)?.cast<String, dynamic>() ??
        (e.l1).cast<String, dynamic>();
    final results = (e.l2['results'] as Map?)?.cast<String, dynamic>() ?? {};

    String fmtKey(String k) =>
        k.replaceAll('_', ' ').split(' ').map((w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    String fmtVal(dynamic v) {
      if (v is num) return v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
      return v.toString();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ListView(
            controller: scrollCtrl,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: AppTextSize.bodyXl,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
              SizedBox(height: AppSpacing.xs),
              Text(dateStr,
                  style: TextStyle(
                      color: AppTheme.labelGray, fontSize: AppTextSize.sm)),
              SizedBox(height: AppSpacing.lg),
              if (results.isNotEmpty) ...[
                Text(
                    fr ? 'Résultats' : (es ? 'Resultados' : 'Results'),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppTextSize.body)),
                SizedBox(height: AppSpacing.sm),
                ...results.entries.map((kv) => Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(fmtKey(kv.key)),
                          Text(fmtVal(kv.value),
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )),
                SizedBox(height: AppSpacing.lg),
              ],
              if (inputs.isNotEmpty) ...[
                Text(
                    fr ? 'Entrées' : (es ? 'Entradas' : 'Inputs'),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppTextSize.body)),
                SizedBox(height: AppSpacing.sm),
                ...inputs.entries.map((kv) => Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(fmtKey(kv.key)),
                          Text(fmtVal(kv.value)),
                        ],
                      ),
                    )),
              ],
              SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: AppTheme.primary),
      SizedBox(width: AppSpacing.sm),
      Text(label,
          style: TextStyle(
              fontSize: AppTextSize.bodyMd,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary)),
    ]);
  }
}

// ─── Generic tool card (non-calculator save-capable tools) ────────────────────

class _GenericToolCard extends StatelessWidget {
  final core.HistoryEntry entry;
  final bool fr, es, isPremium;
  final VoidCallback onDelete;
  final VoidCallback onUnpin;
  final VoidCallback onTap;

  const _GenericToolCard({
    required this.entry,
    required this.fr,
    required this.es,
    required this.isPremium,
    required this.onDelete,
    required this.onUnpin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy  HH:mm', fr ? 'fr' : (es ? 'es' : 'en'))
        .format(entry.savedAt);
    final toolLabel = _toolLabel(entry.screenId, fr, es);
    final unpinLabel = fr ? 'Désépingler' : (es ? 'Desfijar' : 'Unpin');
    final deleteLabel = fr ? 'Supprimer' : (es ? 'Eliminar' : 'Delete');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.smPlus),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.apps_rounded, size: 20, color: AppTheme.primary),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.pinLabel?.isNotEmpty == true
                          ? entry.pinLabel!
                          : toolLabel,
                      style: TextStyle(
                          fontSize: AppTextSize.body,
                          fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: AppSpacing.xxs),
                    Text(dateStr,
                        style: TextStyle(
                            color: AppTheme.labelGray,
                            fontSize: AppTextSize.sm)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    size: 20, color: AppTheme.labelGray),
                onSelected: (v) {
                  switch (v) {
                    case 'unpin':
                      onUnpin();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (entry.isPinned)
                    PopupMenuItem(
                      value: 'unpin',
                      child: Row(children: [
                        Icon(Icons.bookmark_remove_outlined, size: 18),
                        SizedBox(width: AppSpacing.sm),
                        Text(unpinLabel),
                      ]),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 18,
                          color: CalcwiseSemanticColors.error(
                              Theme.of(context).brightness)),
                      SizedBox(width: AppSpacing.sm),
                      Text(deleteLabel),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── History card ─────────────────────────────────────────────────────────────

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  final bool fr, es, isPremium;
  final VoidCallback onDelete;
  final VoidCallback onUnpin;
  final VoidCallback onRename;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.entry,
    required this.fr,
    required this.es,
    required this.isPremium,
    required this.onDelete,
    required this.onUnpin,
    required this.onRename,
    required this.onTap,
  });

  String _fmt(double v) {
    final symbol =
        entry.flavor == 'uk' ? '£' : (entry.flavor == 'ca' ? 'CA\$' : '\$');
    return NumberFormat.currency(symbol: symbol, decimalDigits: 0).format(v);
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy  HH:mm', fr ? 'fr' : (es ? 'es' : 'en'))
        .format(entry.timestamp);
    final grossLabel = fr ? 'Brut' : (es ? 'Bruto' : 'Gross');
    final netLabel = fr ? 'Net' : (es ? 'Neto' : 'Net');
    final rateLabel = fr ? 'Taux' : (es ? 'Tasa' : 'Rate');

    final unpinLabel =
        fr ? 'Désépingler' : (es ? 'Desfijar' : 'Unpin');
    final renameLabel = fr ? 'Renommer' : (es ? 'Renombrar' : 'Rename');
    final deleteLabel = fr ? 'Supprimer' : (es ? 'Eliminar' : 'Delete');

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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Card(
        margin: const EdgeInsets.only(bottom: AppSpacing.smPlus),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Pinned label / badge row
            if (entry.isPinned) ...[
              Row(children: [
                Icon(Icons.bookmark_rounded,
                    size: 15, color: AppTheme.primary),
                SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    entry.pinLabel?.isNotEmpty == true
                        ? entry.pinLabel!
                        : (fr
                            ? 'Scénario enregistré'
                            : (es ? 'Escenario guardado' : 'Saved Scenario')),
                    style: TextStyle(
                        fontSize: AppTextSize.sm,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              SizedBox(height: AppSpacing.xs),
            ],
            Row(children: [
              Icon(Icons.schedule, size: 14, color: AppTheme.labelGray),
              SizedBox(width: AppSpacing.xs),
              Text(dateStr,
                  style: TextStyle(
                      color: AppTheme.labelGray, fontSize: AppTextSize.sm)),
              const Spacer(),
              regionBadge,
              SizedBox(width: AppSpacing.xs),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded,
                    size: 20, color: AppTheme.labelGray),
                onSelected: (v) {
                  switch (v) {
                    case 'unpin':
                      onUnpin();
                      break;
                    case 'rename':
                      onRename();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  if (entry.isPinned)
                    PopupMenuItem(
                      value: 'unpin',
                      child: Row(children: [
                        Icon(Icons.bookmark_remove_outlined, size: 18),
                        SizedBox(width: AppSpacing.sm),
                        Text(unpinLabel),
                      ]),
                    ),
                  // Renaming a label is a premium feature.
                  if (entry.isPinned && isPremium)
                    PopupMenuItem(
                      value: 'rename',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: AppSpacing.sm),
                        Text(renameLabel),
                      ]),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 18,
                          color: CalcwiseSemanticColors.error(
                              Theme.of(context).brightness)),
                      SizedBox(width: AppSpacing.sm),
                      Text(deleteLabel),
                    ]),
                  ),
                ],
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
                  color: CalcwiseSemanticColors.error(
                      Theme.of(context).brightness)),
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
    final base = CalcwiseTheme.of(context).cardBorder;
    final shine = CalcwiseTheme.of(context).surfaceHigh;
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
