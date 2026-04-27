import 'package:shared_preferences/shared_preferences.dart';
import 'freemium_service.dart';

final paywallService = PaywallService._();

class PaywallService {
  PaywallService._();
  static const _keySessionCount = 'paywall_session_count';
  static const _keyCalcCount    = 'paywall_calc_count';
  int _sessionCount = 0;
  int _calcCount    = 0;
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCount = prefs.getInt(_keySessionCount) ?? 0;
    _calcCount    = prefs.getInt(_keyCalcCount)    ?? 0;
  }
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySessionCount, _sessionCount);
    await prefs.setInt(_keyCalcCount,    _calcCount);
  }
  Future<bool> recordSession() async {
    if (freemiumService.isPremium) return false;
    _sessionCount++;
    await _save();
    return _sessionCount == 2 || _sessionCount == 3;
  }
  Future<bool> recordCalculation() async {
    if (freemiumService.isPremium) return false;
    _calcCount++;
    await _save();
    return _calcCount % 5 == 0;
  }
  void resetCalcCount() => _calcCount = 0;
  int get sessionCount => _sessionCount;
  int get calcCount    => _calcCount;
}
