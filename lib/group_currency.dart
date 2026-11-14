/// An amount shown to one member. [needsRate] is true when the member has no rate for the group currency,
/// so the amount is still in the group currency and must not be added to amounts in another currency.
class ShownAmount {
  final double amount;
  final String currency;
  final bool needsRate;
  const ShownAmount(this.amount, this.currency, {this.needsRate = false});
}

/// Shows a group amount in the member's chosen currency.
///
/// [rates] are the member's own rates: account-currency units per one unit of each currency.
/// Group amount to own currency: amount × rate(group currency). The member's own currency is 1.
ShownAmount showInView({
  required double groupAmount,
  required String groupCurrency,
  required String ownCurrency,
  required Map<String, double> rates,
  required bool showOwn,
}) {
  if (!showOwn || ownCurrency == groupCurrency || ownCurrency.isEmpty) {
    return ShownAmount(groupAmount, groupCurrency);
  }
  final rate = rates[groupCurrency];
  if (rate == null || rate <= 0) {
    return ShownAmount(groupAmount, groupCurrency, needsRate: true);
  }
  return ShownAmount(groupAmount * rate, ownCurrency);
}
