import 'package:fieldops_mobile/features/expenses/domain/expense_category_suggester.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('suggests fuel for gas station vendors', () {
    expect(
      suggestExpenseCategory(vendor: 'Shell', notes: 'Diesel fill-up for crew truck'),
      'fuel',
    );
  });

  test('suggests meals for restaurant-like notes', () {
    expect(
      suggestExpenseCategory(vendor: 'Downtown Cafe', notes: 'Crew lunch while on outage repair'),
      'meals',
    );
  });
}
