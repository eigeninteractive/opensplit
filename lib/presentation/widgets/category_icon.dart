import 'package:flutter/material.dart';

/// Resolves a category's stored icon name to a Material icon.
const Map<String, IconData> _icons = {
  'restaurant': Icons.restaurant_rounded,
  'local_grocery_store': Icons.local_grocery_store_rounded,
  'local_bar': Icons.local_bar_rounded,
  'hotel': Icons.hotel_rounded,
  'flight': Icons.flight_rounded,
  'local_taxi': Icons.local_taxi_rounded,
  'directions_transit': Icons.directions_transit_rounded,
  'local_gas_station': Icons.local_gas_station_rounded,
  'local_activity': Icons.local_activity_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'cottage': Icons.cottage_rounded,
  'bolt': Icons.bolt_rounded,
  'wifi': Icons.wifi_rounded,
  'cleaning_services': Icons.cleaning_services_rounded,
  'chair': Icons.chair_rounded,
  'handyman': Icons.handyman_rounded,
  'medical_services': Icons.medical_services_rounded,
  'celebration': Icons.celebration_rounded,
  'subscriptions': Icons.subscriptions_rounded,
  'category': Icons.category_rounded,
};

/// The icon for [name], falling back to the one "Other" uses.
IconData categoryIcon(String name) => _icons[name] ?? Icons.category_rounded;
