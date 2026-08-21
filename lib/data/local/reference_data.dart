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

/// Global category presets, with ids fixed to match the server migration.
const List<({String id, String name, String icon})> presetCategories = [
  (
    id: '00000000-0000-4000-8000-000000000001',
    name: 'Food & Drink',
    icon: 'utensils',
  ),
  (
    id: '00000000-0000-4000-8000-000000000002',
    name: 'Groceries',
    icon: 'shopping-cart',
  ),
  (id: '00000000-0000-4000-8000-000000000003', name: 'Transport', icon: 'car'),
  (
    id: '00000000-0000-4000-8000-000000000004',
    name: 'Accommodation',
    icon: 'bed',
  ),
  (id: '00000000-0000-4000-8000-000000000005', name: 'Rent', icon: 'home'),
  (id: '00000000-0000-4000-8000-000000000006', name: 'Utilities', icon: 'zap'),
  (
    id: '00000000-0000-4000-8000-000000000007',
    name: 'Entertainment',
    icon: 'film',
  ),
  (
    id: '00000000-0000-4000-8000-000000000008',
    name: 'Shopping',
    icon: 'shopping-bag',
  ),
  (
    id: '00000000-0000-4000-8000-000000000009',
    name: 'Health',
    icon: 'heart-pulse',
  ),
  (
    id: '00000000-0000-4000-8000-00000000000a',
    name: 'Other',
    icon: 'circle-dot',
  ),
];
