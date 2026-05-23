class FlavorConfig {
  FlavorConfig._();

  static String get flavor =>
      const String.fromEnvironment('FLAVOR', defaultValue: 'us');

  static bool get isUS => flavor == 'us';
  static bool get isUK => flavor == 'uk';
  static bool get isCA => flavor == 'ca';

  static String get currencySymbol => isUK ? '£' : (isCA ? 'CA\$' : '\$');
  static String get locale => isUK ? 'en_GB' : (isCA ? 'en_CA' : 'en_US');

  static String get privacyPolicyUrl => 'https://calqwise.com/privacy';

  static String get supportEmail {
    if (isUK) return 'support.uk@salaryapp.com';
    if (isCA) return 'support.ca@salaryapp.com';
    return 'support.us@salaryapp.com';
  }
}
