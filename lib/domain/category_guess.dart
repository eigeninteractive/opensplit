/// Guesses a category from what an expense was called.
library;

/// Words that give a category away, space-separated and keyed by the
/// category's icon name.
///
/// Keyed by icon rather than id or name because the icon is the one part of
/// the server's preset list that says what kind of thing a category is
/// without being a random id or a translatable label.
const Map<String, String> _keywords = {
  'restaurant':
      'dinner lunch breakfast brunch restaurant cafe coffee food meal pizza '
      'burger biryani dosa idli chai tea snack swiggy zomato takeaway takeout '
      'dessert sushi noodle thali starbucks mcdonalds kfc dominos',
  'local_grocery_store':
      'grocery groceries supermarket vegetable veggies fruit milk bread egg '
      'dmart bigbasket blinkit zepto instamart kirana provisions',
  'local_bar':
      'beer wine drink bar pub cocktail whisky whiskey vodka rum alcohol '
      'booze liquor nightclub club shot',
  'hotel': 'hotel hostel airbnb oyo stay resort homestay lodge accommodation',
  'flight': 'flight airline airfare plane indigo vistara',
  'local_taxi': 'uber ola rapido taxi cab auto rickshaw',
  'directions_transit': 'metro train bus irctc tram subway ferry railway',
  'local_gas_station': 'petrol diesel fuel parking toll fastag',
  'local_activity':
      'movie cinema concert museum trek hike bowling pvr inox zoo tour safari '
      'rafting',
  'shopping_bag':
      'shopping clothes shoe amazon flipkart myntra mall shirt dress jeans',
  'cottage': 'rent deposit landlord lease',
  'bolt': 'electricity electric power water cylinder lpg utilities',
  'wifi': 'wifi internet broadband phone mobile recharge jio airtel',
  'cleaning_services':
      'cleaning detergent soap toiletries tissue maid supplies broom mop '
      'garbage trash',
  'chair':
      'furniture sofa chair table mattress fridge refrigerator tv microwave '
      'appliance',
  'handyman': 'repair plumber electrician carpenter maintenance servicing',
  'medical_services':
      'doctor medicine pharmacy hospital clinic dentist medical chemist '
      'checkup',
  'celebration':
      'gift birthday party wedding anniversary cake celebration diwali '
      'christmas flower',
  'subscriptions':
      'netflix spotify prime hotstar youtube subscription disney membership '
      'gym',
};

final Map<String, String> _iconByKeyword = {
  for (final MapEntry(key: icon, value: words) in _keywords.entries)
    for (final word in words.split(' ')) word: icon,
};

final RegExp _separators = RegExp('[^a-z0-9]+');

/// The icon name of the category [description] most likely belongs to, or
/// null when nothing in it is recognised.
///
/// The earliest recognised word wins, so "Uber to dinner" is a taxi and
/// "Birthday cake" is a celebration. A trailing "s" is ignored, so plurals
/// match their singular.
String? guessCategoryIcon(String description) {
  for (final word in description.toLowerCase().split(_separators)) {
    if (word.isEmpty) continue;
    final icon = _iconByKeyword[word] ?? _iconByKeyword[_singular(word)];
    if (icon != null) return icon;
  }
  return null;
}

String _singular(String word) => word.length > 3 && word.endsWith('s')
    ? word.substring(0, word.length - 1)
    : word;
