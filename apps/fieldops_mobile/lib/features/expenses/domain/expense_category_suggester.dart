const _fuelKeywords = [
  'shell',
  'chevron',
  'exxon',
  'mobil',
  'diesel',
  'gas',
  'fuel',
  'petrol',
];

const _toolsKeywords = [
  'harbor freight',
  'tool',
  'drill',
  'saw',
  'wrench',
  'blade',
  'equipment',
];

const _materialsKeywords = [
  'home depot',
  'lowes',
  'lumber',
  'supply',
  'concrete',
  'anchor',
  'fastener',
  'material',
  'wire',
  'pipe',
];

const _mealsKeywords = [
  'cafe',
  'restaurant',
  'lunch',
  'breakfast',
  'dinner',
  'meal',
  'coffee',
  'pizza',
  'taco',
  'burger',
];

String? suggestExpenseCategory({String? vendor, String? notes}) {
  final haystack = '${vendor ?? ''} ${notes ?? ''}'.trim().toLowerCase();
  if (haystack.isEmpty) {
    return null;
  }

  if (_containsAny(haystack, _fuelKeywords)) {
    return 'fuel';
  }
  if (_containsAny(haystack, _mealsKeywords)) {
    return 'meals';
  }
  if (_containsAny(haystack, _toolsKeywords)) {
    return 'tools';
  }
  if (_containsAny(haystack, _materialsKeywords)) {
    return 'materials';
  }

  return null;
}

bool _containsAny(String haystack, List<String> keywords) {
  for (final keyword in keywords) {
    if (haystack.contains(keyword)) {
      return true;
    }
  }
  return false;
}
