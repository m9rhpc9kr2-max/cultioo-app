String normalizeWagonTypeId(String? value) {
  final raw = (value ?? '').trim().toLowerCase();
  if (raw.isEmpty) return '';

  // Families mapped to canonical buckets
  if (raw == 'grain_tipper' || raw == 'grain_tanker') return 'grain';
  if (raw == 'vegetable_oil') return 'oil';
  if (raw == 'milk_tanker' || raw == 'dairy_transport') return 'liquid_food';
  if (raw == 'charcuterie_delicatessen' || raw == 'poultry_transport') return 'meat';
  if (raw == 'fish_seafood' || raw == 'cheese_transport' || raw == 'eggs_transport') {
    return 'temperature_controlled';
  }
  if (raw == 'coffee_tea' || raw == 'wine_alcohol' || raw == 'honey_jam' || raw == 'nuts_seeds') {
    return 'dry_bulk';
  }
  if (raw == 'chocolate_confectionery' || raw == 'spices_herbs') return 'specialty';
  if (raw == 'meal_prep_catering' || raw == 'organic_bio' || raw == 'kosher_halal') {
    return 'specialty';
  }
  if (raw == 'pet_food') return 'dry_goods';

  if (raw == 'pharma_healthcare') return 'temperature_controlled';

  if (raw == 'food_tanker') return 'liquid_food';
  if (raw == 'silo_trailer' || raw == 'cement_silo' || raw == 'powder_tanker') return 'dry_bulk';
  if (raw == 'bitumen_tanker') return 'oil';

  if (raw == 'adr_general' || raw == 'adr_tanker' || raw == 'fuel_tanker' || raw == 'chemical_tanker' || raw == 'gas_tanker' || raw == 'explosives_transport' || raw == 'flammable_liquids' || raw == 'corrosive_materials' || raw == 'hazardous_waste') {
    return 'specialty';
  }

  if (raw == 'box_truck' || raw == 'curtain_sider' || raw == 'flatbed' || raw == 'drop_deck' || raw == 'low_loader' || raw == 'container_chassis' || raw == 'swap_body' || raw == 'mega_trailer' || raw == 'car_carrier' || raw == 'livestock' || raw == 'moving_floor' || raw == 'side_loader' || raw == 'crane_truck') {
    return 'dry_goods';
  }
  if (raw == 'panel_van') return 'dry_goods';

  return raw;
}

/// Returns a human-readable label for a wagon type.
/// No AppLocalizations dependency – uses a built-in English label map.
String wagonLabelFromType(String? type, [dynamic _]) {
  const labels = {
    'grain': 'Grain',
    'dry_bulk': 'Dry Bulk',
    'oil': 'Oil / Bitumen',
    'liquid_food': 'Liquid Food',
    'refrigerated': 'Refrigerated',
    'fresh_produce': 'Fresh Produce',
    'frozen': 'Frozen',
    'temperature_controlled': 'Temperature Controlled',
    'meat': 'Meat / Poultry',
    'bakery': 'Bakery',
    'beverage': 'Beverage',
    'specialty': 'Specialty',
    'dry_goods': 'Dry Goods',
  };

  final normalized = normalizeWagonTypeId(type);
  if (normalized.isEmpty) return '';
  return labels[normalized] ??
      normalized
          .replaceAll('_', ' ')
          .split(' ')
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
}
