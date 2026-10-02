import 'package:opensplit/domain/category_guess.dart';
import 'package:test/test.dart';

void main() {
  group('guessCategoryIcon', () {
    test('recognises a word anywhere, whatever its case', () {
      expect(guessCategoryIcon('Dinner at Toit'), 'restaurant');
      expect(guessCategoryIcon('Airport UBER'), 'local_taxi');
      expect(guessCategoryIcon('Netflix'), 'subscriptions');
    });

    test('the earliest recognised word wins', () {
      expect(guessCategoryIcon('Birthday cake'), 'celebration');
      expect(guessCategoryIcon('Uber to dinner'), 'local_taxi');
      expect(guessCategoryIcon('Dinner, then an Uber'), 'restaurant');
    });

    test('plurals match their singular', () {
      expect(guessCategoryIcon('Beers'), 'local_bar');
      expect(guessCategoryIcon('Movies'), 'local_activity');
      expect(guessCategoryIcon('Groceries'), 'local_grocery_store');
    });

    test('matches whole words only', () {
      expect(guessCategoryIcon('Barbecue'), isNull);
      expect(guessCategoryIcon('Autograph'), isNull);
    });

    test('is null when nothing is recognised', () {
      expect(guessCategoryIcon(''), isNull);
      expect(guessCategoryIcon('   '), isNull);
      expect(guessCategoryIcon('Misc'), isNull);
    });
  });
}
