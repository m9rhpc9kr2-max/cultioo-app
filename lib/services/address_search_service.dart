import 'dart:convert';
import 'package:http/http.dart' as http;

class AddressSearchService {
  // Use OpenStreetMap Nominatim API (free)
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  
  static Future<List<AddressSuggestion>> searchAddresses(String query) async {
    if (query.trim().isEmpty || query.length < 3) {
      return [];
    }
    
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&addressdetails=1&extratags=1&accept-language=en',
        ),
        headers: {
          'User-Agent': 'CultiooApp/1.0.0',
          'Accept-Language': 'en',
        },
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        
        return data.map((item) {
          return AddressSuggestion.fromJson(item);
        }).toList();
      } else {
//print('Address search error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
//print('Error during address search: $e');
      return [];
    }
  }
  
  static Future<AddressSuggestion?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/reverse?lat=$lat&lon=$lng&format=json&addressdetails=1&accept-language=en',
        ),
        headers: {
          'User-Agent': 'CultiooApp/1.0.0',
          'Accept-Language': 'en',
        },
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return AddressSuggestion.fromJson(data);
      }
    } catch (e) {
//print('Error during reverse geocoding: $e');
    }
    return null;
  }
}

class AddressSuggestion {
  final String displayName;
  final String formattedAddress;
  final double lat;
  final double lng;
  final String? country;
  final String? city;
  final String? postcode;
  final String? street;
  final String? houseNumber;
  
  AddressSuggestion({
    required this.displayName,
    required this.formattedAddress,
    required this.lat,
    required this.lng,
    this.country,
    this.city,
    this.postcode,
    this.street,
    this.houseNumber,
  });
  
  factory AddressSuggestion.fromJson(Map<String, dynamic> json) {
    final address = json['address'] ?? {};
    
    // Format the address as in the database
    String formattedAddress = '';
    
    // Street and house number
    final street = address['road'] ?? address['street'] ?? '';
    final houseNumber = address['house_number'] ?? '';
    if (street.isNotEmpty) {
      formattedAddress += street;
      if (houseNumber.isNotEmpty) {
        formattedAddress += ' $houseNumber';
      }
    }
    
    // Postal code
    final postcode = address['postcode'] ?? '';
    if (postcode.isNotEmpty) {
      if (formattedAddress.isNotEmpty) formattedAddress += ', ';
      formattedAddress += postcode;
    }
    
    // City
    final city = address['city'] ?? 
                 address['town'] ?? 
                 address['village'] ?? 
                 address['municipality'] ?? '';
    if (city.isNotEmpty) {
      if (formattedAddress.isNotEmpty) formattedAddress += ', ';
      formattedAddress += city;
    }
    
    // Country
    final country = address['country'] ?? '';
    if (country.isNotEmpty) {
      if (formattedAddress.isNotEmpty) formattedAddress += ', ';
      formattedAddress += country;
    }
    
    // Fallback to display_name if formatted address is empty
    if (formattedAddress.isEmpty) {
      formattedAddress = json['display_name'] ?? '';
    }
    
    return AddressSuggestion(
      displayName: json['display_name'] ?? '',
      formattedAddress: formattedAddress,
      lat: double.tryParse(json['lat']?.toString() ?? '0') ?? 0.0,
      lng: double.tryParse(json['lon']?.toString() ?? '0') ?? 0.0,
      country: country.isNotEmpty ? country : null,
      city: city.isNotEmpty ? city : null,
      postcode: postcode.isNotEmpty ? postcode : null,
      street: street.isNotEmpty ? street : null,
      houseNumber: houseNumber.isNotEmpty ? houseNumber : null,
    );
  }
  
  @override
  String toString() {
    return formattedAddress;
  }
}
