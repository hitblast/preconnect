const String defaultWebPageTitle =
    'PreConnect Web | Fast, Calm Academic Companion App for BRAC University';

String normalizeWebPageTitle(String title) {
  final value = title.trim();
  if (value.isEmpty) return defaultWebPageTitle;
  if (value.startsWith('PreConnect Web |')) return value;
  return 'PreConnect Web | $value';
}

void setWebPageTitle(String title) {}
