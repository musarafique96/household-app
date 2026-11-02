/// Currency codes offered in dropdowns across the app.
const List<String> kCurrencyCodes = [
  'SAR', 'PKR', 'AED', 'USD', 'EUR', 'GBP', 'INR', 'BDT', 'EGP', 'JOD',
  'KWD', 'QAR', 'OMR', 'BHD', 'CAD', 'AUD', 'CHF', 'CNY', 'JPY', 'TRY',
  'MYR', 'SGD', 'IDR', 'PHP', 'LKR', 'NPR', 'ZAR', 'KES', 'NGN', 'SEK',
];

/// Dropdown items for [codes], adding [extra] first if it is not already listed.
List<String> currencyChoices({String? extra, Iterable<String> exclude = const []}) {
  final list = [
    if (extra != null && extra.isNotEmpty) extra,
    ...kCurrencyCodes,
  ];
  final seen = <String>{};
  return [
    for (final c in list)
      if (!exclude.contains(c) && seen.add(c)) c,
  ];
}
