/// Reference data that ships with the app.
///
/// Currencies and preset categories exist on the server too, and the ids here
/// must match it exactly. A category id is written onto entries, so if a device
/// invented its own id for "Groceries" while offline, that entry would point at
/// a category the server has never heard of. Deterministic ids make the presets
/// safe to use before the first sync ever completes.
library;

/// ISO 4217 subset, with the exponent that governs minor units.
const List<({String code, int exponent, String? symbol, String name})>
presetCurrencies = [
  (code: 'INR', exponent: 2, symbol: '₹', name: 'Indian Rupee'),
  (code: 'USD', exponent: 2, symbol: r'$', name: 'US Dollar'),
  (code: 'EUR', exponent: 2, symbol: '€', name: 'Euro'),
  (code: 'GBP', exponent: 2, symbol: '£', name: 'Pound Sterling'),
  (code: 'SGD', exponent: 2, symbol: r'S$', name: 'Singapore Dollar'),
  (code: 'AED', exponent: 2, symbol: 'د.إ', name: 'UAE Dirham'),
  (code: 'AUD', exponent: 2, symbol: r'A$', name: 'Australian Dollar'),
  (code: 'JPY', exponent: 0, symbol: '¥', name: 'Japanese Yen'),
  (code: 'KRW', exponent: 0, symbol: '₩', name: 'South Korean Won'),
  (code: 'VND', exponent: 0, symbol: '₫', name: 'Vietnamese Dong'),
  (code: 'IDR', exponent: 2, symbol: 'Rp', name: 'Indonesian Rupiah'),
  (code: 'THB', exponent: 2, symbol: '฿', name: 'Thai Baht'),
  (code: 'LKR', exponent: 2, symbol: 'Rs', name: 'Sri Lankan Rupee'),
  (code: 'NPR', exponent: 2, symbol: 'Rs', name: 'Nepalese Rupee'),
  (code: 'KWD', exponent: 3, symbol: 'د.ك', name: 'Kuwaiti Dinar'),
  (code: 'BHD', exponent: 3, symbol: '.د.ب', name: 'Bahraini Dinar'),
];

/// The categories every group gets, in the order they are offered.
///
/// Ordered by how often a thing is actually *shared*, not alphabetically: a
/// restaurant bill and a taxi are split constantly, a sofa once. The picker is
/// a list someone scrolls while a waiter waits, so the first six entries carry
/// most of the traffic.
///
/// Ids are fixed here and in the server migration, and are written onto
/// entries. If a device invented its own id for "Groceries" while offline, that
/// entry would point at a category the server has never heard of and would show
/// as uncategorised everywhere else.
const List<({String id, String name, String icon})> presetCategories = [
  (
    id: 'e7b1844c-76a3-4d2b-bd81-56a74e11f943',
    name: 'Restaurants',
    icon: 'restaurant',
  ),
  (
    id: 'afe84b91-6ac5-4ec2-9290-bd18cb8a7605',
    name: 'Groceries',
    icon: 'local_grocery_store',
  ),
  (
    id: 'ea5dacd7-da9f-49e3-9e99-90a0343be536',
    name: 'Drinks & nightlife',
    icon: 'local_bar',
  ),
  (
    id: '1f289d21-ff2f-4382-a4f8-31d6366583fa',
    name: 'Accommodation',
    icon: 'hotel',
  ),
  (id: '8a682d2e-53f2-4d7f-9217-16e360c3eaa5', name: 'Flights', icon: 'flight'),
  (
    id: '36df7514-5f84-433f-bcce-67a891f61a93',
    name: 'Taxi & rideshare',
    icon: 'local_taxi',
  ),
  (
    id: 'dff02d03-31fa-476d-b6d4-67c9322c3b50',
    name: 'Public transport',
    icon: 'directions_transit',
  ),
  (
    id: '02fa4141-452c-4142-b51b-9374b8a78186',
    name: 'Fuel & parking',
    icon: 'local_gas_station',
  ),
  (
    id: 'f5676a7a-6c8b-4ac9-bf09-ccc982885153',
    name: 'Activities & outings',
    icon: 'local_activity',
  ),
  (
    id: '421962f1-795c-414a-816b-215cb8a942c2',
    name: 'Shopping',
    icon: 'shopping_bag',
  ),
  (id: '8c66bd37-e243-480d-8277-135105642331', name: 'Rent', icon: 'cottage'),
  (id: 'cfb5c503-c424-41d4-a285-a51ab44f0a28', name: 'Utilities', icon: 'bolt'),
  (
    id: '669596e4-88f5-4a66-97d0-a6f5857cc6b0',
    name: 'Internet & phone',
    icon: 'wifi',
  ),
  (
    id: '4ea8849c-d298-4a23-91ec-84332bac0a81',
    name: 'Household supplies',
    icon: 'cleaning_services',
  ),
  (
    id: 'bca2463d-8dc4-45b5-8b86-ef59559e7820',
    name: 'Furniture & appliances',
    icon: 'chair',
  ),
  (
    id: '54dd3641-140a-4931-8235-0600d6f34f34',
    name: 'Repairs & maintenance',
    icon: 'handyman',
  ),
  (
    id: '1e7958bd-100e-4bc4-8e16-23a5a12f01cd',
    name: 'Health & medical',
    icon: 'medical_services',
  ),
  (
    id: 'fca7633f-06b4-4492-bbdc-2ef1e850dc1b',
    name: 'Gifts & celebrations',
    icon: 'celebration',
  ),
  (
    id: '580f8062-6c94-4997-b9e4-b13d3140a738',
    name: 'Subscriptions',
    icon: 'subscriptions',
  ),
  (id: '4d6e0094-04e8-4aae-9d93-9aeb7c3fff4e', name: 'Other', icon: 'category'),
];
