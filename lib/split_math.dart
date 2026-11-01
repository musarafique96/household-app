import 'dart:math' as math;

import 'data/models.dart';

/// One payment that clears part of a debt.
class Transfer {
  final int from;
  final int to;
  final double amount;

  const Transfer({required this.from, required this.to, required this.amount});
}

/// Positive means the person is owed money. Negative means they owe money.
Map<int, double> netBalances(List<SharedExpense> shared) {
  final net = <int, double>{};
  for (final s in shared) {
    net[s.paidBy] = (net[s.paidBy] ?? 0.0) + s.amount;
    s.owed.forEach((id, amount) {
      net[id] = (net[id] ?? 0.0) - amount;
    });
  }
  return net;
}

/// Smallest set of payments that clears all balances.
List<Transfer> computeTransfers(Map<int, double> net) {
  final debtors = <MapEntry<int, double>>[];
  final creditors = <MapEntry<int, double>>[];
  net.forEach((id, value) {
    if (value < -0.005) {
      debtors.add(MapEntry(id, -value));
    } else if (value > 0.005) {
      creditors.add(MapEntry(id, value));
    }
  });

  final transfers = <Transfer>[];
  var i = 0;
  var j = 0;
  while (i < debtors.length && j < creditors.length) {
    final amount = math.min(debtors[i].value, creditors[j].value);
    transfers.add(Transfer(from: debtors[i].key, to: creditors[j].key, amount: amount));

    debtors[i] = MapEntry(debtors[i].key, debtors[i].value - amount);
    creditors[j] = MapEntry(creditors[j].key, creditors[j].value - amount);

    if (debtors[i].value < 0.005) i++;
    if (creditors[j].value < 0.005) j++;
  }
  return transfers;
}
