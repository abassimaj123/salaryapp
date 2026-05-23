import 'package:calcwise_core/calcwise_core.dart'
    show
        themeModeService,
        CalcwiseAdFooter,
        CalcwiseRateAppTile,
        CalcwiseSettingsScaffold,
        CalcwiseSettingsSection,
        CalcwiseSettingsTile;
import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/flavor_config.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../main.dart' show adService;
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../l10n/strings_fr.dart';
import '../main.dart' show isSpanishNotifier;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, useAlt, _) {
        final es = FlavorConfig.isUS && useAlt;
        final fr = FlavorConfig.isCA && useAlt;

        final title = fr
            ? AppStringsFR.settings
            : (es ? AppStringsES.settings : AppStringsEN.settings);

        return CalcwiseSettingsScaffold(
          title: title,
          bottomNavigationBar: const CalcwiseAdFooter(),
          children: [
            // ── Premium section ────────────────────────────────
            _PremiumSection(fr: fr, es: es),

            // ── Language toggle (CA: FR/EN | US: EN/ES | UK: none) ──
            if (!FlavorConfig.isUK) _LanguageSection(fr: fr, es: es),

            // ── Appearance (theme toggle) ─────────────────────
            CalcwiseSettingsSection(
              title: fr ? 'Apparence' : (es ? 'Apariencia' : 'Appearance'),
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeService.notifier,
                  builder: (_, __, ___) => CalcwiseSettingsTile(
                    icon: themeModeService.icon,
                    label: themeModeService.label(isFrench: fr, isSpanish: es),
                    onTap: () => themeModeService.toggle(),
                  ),
                ),
              ],
            ),

            // ── Rewarded ad ───────────────────────────────────
            _RewardedSection(fr: fr, es: es),

            // ── Links ─────────────────────────────────────────
            _LinksSection(fr: fr, es: es),

            // ── Disclaimer ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.sm),
              child: Text(
                fr
                    ? 'À titre informatif seulement. Pas de conseil financier. Consultez un conseiller avant de prendre des décisions.'
                    : es
                        ? 'Solo con fines informativos. No es asesoramiento financiero. Consulte a un profesional.'
                        : 'For informational purposes only. Not financial advice. Consult a qualified advisor before making financial decisions.',
                style: TextStyle(
                  fontSize: AppTextSize.xs,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.labelGray,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // ── App info ──────────────────────────────────────
            _AppInfoTile(fr: fr, es: es),
          ],
        );
      },
    );
  }
}

// ─── Premium section ──────────────────────────────────────────────────────────

class _PremiumSection extends StatelessWidget {
  final bool fr, es;
  const _PremiumSection({required this.fr, required this.es});

  String _price() {
    if (FlavorConfig.isUK) return '£2.49';
    if (FlavorConfig.isCA) return 'CA\$3.99';
    return '\$2.99';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (_, isPremium, __) {
        final premiumDesc = fr
            ? AppStringsFR.premiumDesc
            : (es ? AppStringsES.premiumDesc : AppStringsEN.premiumDesc);
        final getPremium = fr
            ? AppStringsFR.getPremium
            : (es ? AppStringsES.getPremium : AppStringsEN.getPremium);
        final restore = fr
            ? AppStringsFR.restorePurchase
            : (es
                ? AppStringsES.restorePurchase
                : AppStringsEN.restorePurchase);
        final activeLabel = fr
            ? AppStringsFR.premiumActive
            : (es ? AppStringsES.premiumActive : AppStringsEN.premiumActive);

        return CalcwiseSettingsSection(
          title: 'Premium',
          children: isPremium
              ? [
                  ListTile(
                    leading: Icon(Icons.verified, color: AppTheme.success),
                    title: Text(activeLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(premiumDesc,
                        style: TextStyle(
                            color: AppTheme.labelGray,
                            fontSize: AppTextSize.sm)),
                    trailing: Icon(Icons.check_circle, color: AppTheme.success),
                  ),
                ]
              : [
                  // ── UK: Lifetime "Best Value" card (shown above standard) ──
                  if (FlavorConfig.isUK) _LifetimeCard(premiumDesc: premiumDesc),

                  CalcwiseSettingsTile(
                    icon: Icons.star_rounded,
                    label: getPremium,
                    subtitle: premiumDesc,
                    trailing: _price(),
                    onTap: () => IAPService.instance.buy(),
                  ),
                  CalcwiseSettingsTile(
                    icon: Icons.restore,
                    label: restore,
                    onTap: () => IAPService.instance.restore(),
                  ),
                ],
        );
      },
    );
  }
}

// ─── Language toggle ──────────────────────────────────────────────────────────

class _LanguageSection extends StatelessWidget {
  final bool fr, es;
  const _LanguageSection({required this.fr, required this.es});

  @override
  Widget build(BuildContext context) {
    final title = fr ? 'Langue' : (es ? 'Idioma' : 'Language');

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, useAlt, __) {
        Future<void> setAlt(bool value) async {
          isSpanishNotifier.value = value;
          final prefs = await SharedPreferences.getInstance();
          if (FlavorConfig.isCA) {
            await prefs.setString('language', value ? 'fr' : 'en');
          } else {
            await prefs.setString('language', value ? 'es' : 'en');
          }
        }

        final children = FlavorConfig.isCA
            ? [
                Expanded(
                  child: _LangChip(
                    label: 'Français',
                    selected: useAlt,
                    onTap: () => setAlt(true),
                  ),
                ),
                const SizedBox(width: AppSpacing.smPlus),
                Expanded(
                  child: _LangChip(
                    label: 'English',
                    selected: !useAlt,
                    onTap: () => setAlt(false),
                  ),
                ),
              ]
            : [
                Expanded(
                  child: _LangChip(
                    label: 'English',
                    selected: !useAlt,
                    onTap: () => setAlt(false),
                  ),
                ),
                const SizedBox(width: AppSpacing.smPlus),
                Expanded(
                  child: _LangChip(
                    label: 'Español',
                    selected: useAlt,
                    onTap: () => setAlt(true),
                  ),
                ),
              ];

        return CalcwiseSettingsSection(
          title: title,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
              child: Row(children: children),
            ),
          ],
        );
      },
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.mdPlus),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.labelGray,
            fontWeight: FontWeight.w600,
            fontSize: AppTextSize.body,
          ),
        ),
      ),
    );
  }
}

// ─── Rewarded ad section ──────────────────────────────────────────────────────

class _RewardedSection extends StatelessWidget {
  final bool fr, es;
  const _RewardedSection({required this.fr, required this.es});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (_, isPremium, __) {
        if (isPremium) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: freemiumService.isRewardedNotifier,
          builder: (_, isRewarded, __) {
            final watchLabel = fr
                ? AppStringsFR.watchAd
                : (es ? AppStringsES.watchAd : AppStringsEN.watchAd);
            final adFreeLabel = fr
                ? AppStringsFR.adFree60
                : (es ? AppStringsES.adFree60 : AppStringsEN.adFree60);

            return CalcwiseSettingsSection(
              title: fr
                  ? 'Pub récompensée'
                  : (es ? 'Anuncio recompensado' : 'Rewarded ad'),
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: CalcwiseSemanticColors.successDeep
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                    ),
                    child: const Icon(Icons.ondemand_video,
                        color: CalcwiseSemanticColors.successDeep),
                  ),
                  title: Text(adFreeLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    isRewarded
                        ? '${freemiumService.rewardedRemaining?.inMinutes ?? 0} min left'
                        : (fr
                            ? 'Regardez une pub pour 60 min sans pub'
                            : (es
                                ? 'Vea un anuncio para 60 min sin anuncios'
                                : 'Watch an ad for 60 ad-free minutes')),
                    style: TextStyle(
                        color: AppTheme.labelGray, fontSize: AppTextSize.sm),
                  ),
                  trailing: isRewarded
                      ? Icon(Icons.check_circle, color: AppTheme.success)
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(90, 48),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: adService.isRewardedReady
                              ? () => adService.showRewarded()
                              : null,
                          child: Text(watchLabel,
                              style: const TextStyle(fontSize: AppTextSize.sm)),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ─── Links section ────────────────────────────────────────────────────────────

class _LinksSection extends StatelessWidget {
  final bool fr, es;
  const _LinksSection({required this.fr, required this.es});

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri))
      launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final privacyLabel = fr
        ? AppStringsFR.privacyPolicy
        : (es ? AppStringsES.privacyPolicy : AppStringsEN.privacyPolicy);
    final supportLabel = fr
        ? AppStringsFR.contactSupport
        : (es ? AppStringsES.contactSupport : AppStringsEN.contactSupport);
    final discoverLabel = fr
        ? AppStringsFR.discover
        : (es ? AppStringsES.discover : AppStringsEN.discover);
    final calqwiseLabel = fr
        ? AppStringsFR.calqwise
        : (es ? AppStringsES.calqwise : AppStringsEN.calqwise);

    return CalcwiseSettingsSection(
      title: fr ? 'Liens' : (es ? 'Enlaces' : 'Links'),
      children: [
        CalcwiseRateAppTile(
            label: fr
                ? 'Noter l\'app'
                : (es ? 'Calificar la app' : 'Rate the App')),
        CalcwiseSettingsTile(
          icon: Icons.privacy_tip_rounded,
          label: privacyLabel,
          onTap: () => _launch(FlavorConfig.privacyPolicyUrl),
        ),
        CalcwiseSettingsTile(
          icon: Icons.mail_outline,
          label: supportLabel,
          onTap: () => _launch('mailto:${FlavorConfig.supportEmail}'),
        ),
        CalcwiseSettingsTile(
          icon: Icons.apps_rounded,
          label: '$discoverLabel — $calqwiseLabel',
          onTap: () => _launch(
              'https://play.google.com/store/apps/developer?id=CalqWise'),
        ),
      ],
    );
  }
}

// ─── UK Lifetime IAP card ─────────────────────────────────────────────────────

/// "Best Value — Lifetime" purchase card shown only in the UK flavor.
///
/// TODO(play-console): The product 'premium_lifetime_uk' must be created as a
/// non-consumable one-time product in Play Console before publishing the UK AAB.
class _LifetimeCard extends StatelessWidget {
  final String premiumDesc;
  const _LifetimeCard({required this.premiumDesc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: () => IAPService.instance.buyLifetime(),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.mdPlus),
            child: Row(
              children: [
                // Crown icon
                Container(
                  padding: const EdgeInsets.all(AppSpacing.smPlus),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                  ),
                  child: const Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: AppSpacing.mdPlus),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Lifetime Access',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: AppTextSize.bodyMd,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.smPlus, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFBBF24),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Text(
                              'BEST VALUE',
                              style: TextStyle(
                                color: Color(0xFF1C1917),
                                fontWeight: FontWeight.w800,
                                fontSize: 9,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        premiumDesc,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: AppTextSize.sm,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Price — live from Play Store, fallback to placeholder
                ValueListenableBuilder<String?>(
                  valueListenable: IAPService.instance.localizedLifetimePrice,
                  builder: (_, price, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        // TODO: replace placeholder once product is in Play Console
                        price ?? '£X.XX',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: AppTextSize.title,
                        ),
                      ),
                      const Text(
                        'one time',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: AppTextSize.xs,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── App info tile ────────────────────────────────────────────────────────────

class _AppInfoTile extends StatelessWidget {
  final bool fr, es;
  const _AppInfoTile({required this.fr, required this.es});

  @override
  Widget build(BuildContext context) {
    final flavorBadge =
        FlavorConfig.isUK ? 'UK' : (FlavorConfig.isCA ? 'CA' : 'US');
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          'Salary Calculator $flavorBadge · v1.0.0',
          style: TextStyle(color: AppTheme.labelGray, fontSize: AppTextSize.sm),
        ),
      ),
    );
  }
}
