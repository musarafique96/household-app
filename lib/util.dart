const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Date as yyyy-MM-dd, used for storing and comparing dates in the database.
String ymd(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Amount with the user's currency, e.g. "120.00 SAR".
String money(double value, String currency) => '${value.toStringAsFixed(2)} $currency';

String monthLabel(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String monthShort(DateTime d) => '${_months[d.month - 1]} ${d.year % 100}';
