import '../core/ads/ad_footer.dart';
import 'package:calcwise_core/calcwise_core.dart' show themeModeService;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/flavor_config.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/ads/ad_service.dart';
import '../core/services/review_service.dart';
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

        final title   = fr ? AppStringsFR.settings : (es ? AppStringsES.settings : AppStringsEN.settings);

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Premium section ────────────────────────────────
                    _PremiumSection(fr: fr, es: es),
                    SizedBox(height: 16),

                    // ── Language toggle (CA: FR/EN | US: EN/ES | UK: none) ──
                    if (!FlavorConfig.isUK) ...[
                      _LanguageSection(fr: fr, es: es),
                      SizedBox(height: 16),
                    ],

                    // ── Appearance (theme toggle) ─────────────────────
                    _AppearanceSection(fr: fr, es: es),
                    SizedBox(height: 16),

                    // ── Rewarded ad ───────────────────────────────────
                    _RewardedSection(fr: fr, es: es),
                    SizedBox(height: 16),

                    // ── Links ─────────────────────────────────────────
                    _LinksSection(fr: fr, es: es),
                    SizedBox(height: 16),

                    // ── Disclaimer ────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                      child: Text(
                        fr
                            ? 'À titre informatif seulement. Pas de conseil financier. Consultez un conseiller avant de prendre des décisions.'
                            : es
                                ? 'Solo con fines informativos. No es asesoramiento financiero. Consulte a un profesional.'
                                : 'For informational purposes only. Not financial advice. Consult a qualified advisor before making financial decisions.',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.labelGray,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: 8),

                    // ── App info ──────────────────────────────────────
                    _AppInfoTile(fr: fr, es: es),
                  ],
                ),
              ),
              const AdFooter(),
            ],
          ),
        );
      },
    );
  }
}

// ─── Premium section ──────────────────────────────────────────────────────────

class _PremiumSection extends StatelessWidget {
  final bool fr, es;
  const _PremiumSection({required this.fr, required this.es});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (_, isPremium, __) {
        final premiumTitle = fr
            ? AppStringsFR.premium
            : (es ? AppStringsES.premium : AppStringsEN.premium);
        final premiumDesc = fr
            ? AppStringsFR.premiumDesc
            : (es ? AppStringsES.premiumDesc : AppStringsEN.premiumDesc);
        final getPremium = fr
            ? AppStringsFR.getPremium
            : (es ? AppStringsES.getPremium : AppStringsEN.getPremium);
        final restore = fr
            ? AppStringsFR.restorePurchase
            : (es ? AppStringsES.restorePurchase : AppStringsEN.restorePurchase);
        final activeLabel = fr
            ? AppStringsFR.premiumActive
            : (es ? AppStringsES.premiumActive : AppStringsEN.premiumActive);

        if (isPremium) {
          return _SectionCard(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.verified, color: AppTheme.success),
              ),
              title: Text(activeLabel,
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(premiumDesc,
                  style: TextStyle(color: AppTheme.labelGray, fontSize: 12)),
              trailing: Icon(Icons.check_circle, color: AppTheme.success),
            ),
          );
        }

        return _SectionCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.star_rounded,
                      color: Colors.white, size: 20),
                ),
                SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(premiumTitle,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(premiumDesc,
                      style: TextStyle(
                          color: AppTheme.labelGray, fontSize: 12)),
                ]),
              ]),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => IAPService.instance.buy(),
                child: Text(getPremium),
              ),
              SizedBox(height: 8),
              TextButton(
                onPressed: () => IAPService.instance.restore(),
                child: Text(restore,
                    style: TextStyle(color: AppTheme.labelGray)),
              ),
            ]),
          ),
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
    final title = fr
        ? 'Langue'
        : (es ? 'Idioma' : 'Language');

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

        if (FlavorConfig.isCA) {
          // FR / EN toggle
          return _SectionCard(
            title: title,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(
                  child: _LangChip(
                    label: 'Français',
                    selected: useAlt,
                    onTap: () => setAlt(true),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _LangChip(
                    label: 'English',
                    selected: !useAlt,
                    onTap: () => setAlt(false),
                  ),
                ),
              ]),
            ),
          );
        }

        // US: EN / ES toggle
        return _SectionCard(
          title: title,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              Expanded(
                child: _LangChip(
                  label: 'English',
                  selected: !useAlt,
                  onTap: () => setAlt(false),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _LangChip(
                  label: 'Español',
                  selected: useAlt,
                  onTap: () => setAlt(true),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
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
            fontSize: 14,
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

            return _SectionCard(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.ondemand_video, color: Colors.purple),
                ),
                title: Text(adFreeLabel,
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  isRewarded
                      ? '${freemiumService.rewardedRemaining?.inMinutes ?? 0} min left'
                      : (fr
                          ? 'Regardez une pub pour 60 min sans pub'
                          : (es
                              ? 'Vea un anuncio para 60 min sin anuncios'
                              : 'Watch an ad for 60 ad-free minutes')),
                  style: TextStyle(
                      color: AppTheme.labelGray, fontSize: 12),
                ),
                trailing: isRewarded
                    ? Icon(Icons.check_circle, color: AppTheme.success)
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(90, 36),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: AdService.instance.isRewardedReady
                            ? () => AdService.instance.showRewarded(
                                  onRewarded:
                                      freemiumService.activateRewarded,
                                )
                            : null,
                        child: Text(watchLabel,
                            style: TextStyle(fontSize: 12)),
                      ),
              ),
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
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
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

    return _SectionCard(
      title: fr ? 'Liens' : (es ? 'Enlaces' : 'Links'),
      child: Column(children: [
        _LinkTile(
          icon: Icons.star_outline,
          label: fr ? 'Noter l\'app' : (es ? 'Calificar la app' : 'Rate App'),
          onTap: () => ReviewService.instance.requestReview(),
        ),
        Divider(height: 1, indent: 56, color: AppTheme.divider),
        _LinkTile(
          icon: Icons.privacy_tip_outlined,
          label: privacyLabel,
          onTap: () => _launch(FlavorConfig.privacyPolicyUrl),
        ),
        Divider(height: 1, indent: 56, color: AppTheme.divider),
        _LinkTile(
          icon: Icons.mail_outline,
          label: supportLabel,
          onTap: () => _launch('mailto:${FlavorConfig.supportEmail}'),
        ),
        Divider(height: 1, indent: 56, color: AppTheme.divider),
        _LinkTile(
          icon: Icons.apps_outlined,
          label: '$discoverLabel — $calqwiseLabel',
          onTap: () =>
              _launch('https://play.google.com/store/apps/developer?id=CalqWise'),
        ),
      ]),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LinkTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primary, size: 22),
      title: Text(label, style: TextStyle(fontSize: 14)),
      trailing: Icon(Icons.chevron_right, color: AppTheme.labelGray),
      onTap: onTap,
    );
  }
}

// ─── App info tile ────────────────────────────────────────────────────────────

class _AppInfoTile extends StatelessWidget {
  final bool fr, es;
  const _AppInfoTile({required this.fr, required this.es});

  @override
  Widget build(BuildContext context) {
    final flavorBadge = FlavorConfig.isUK
        ? 'UK'
        : (FlavorConfig.isCA ? 'CA' : 'US');
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Salary Calculator $flavorBadge · v1.0.0',
          style: TextStyle(color: AppTheme.labelGray, fontSize: 12),
        ),
      ),
    );
  }
}

// ─── Appearance section ───────────────────────────────────────────────────────

class _AppearanceSection extends StatelessWidget {
  final bool fr, es;
  const _AppearanceSection({required this.fr, required this.es});

  @override
  Widget build(BuildContext context) {
    final title = fr ? 'Apparence' : (es ? 'Apariencia' : 'Appearance');
    return _SectionCard(
      title: title,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeService.notifier,
        builder: (_, __, ___) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(themeModeService.icon, color: AppTheme.primary),
          title: Text(themeModeService.label(isFrench: fr, isSpanish: es)),
          trailing: Icon(Icons.chevron_right, color: AppTheme.labelGray),
          onTap: () => themeModeService.toggle(),
        ),
      ),
    );
  }
}

// ─── Reusable card wrapper ────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  final String? title;
  const _SectionCard({required this.child, this.title});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text(title!,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppTheme.labelGray,
                      letterSpacing: 0.8)),
            ),
          child,
        ],
      ),
    );
  }
}
