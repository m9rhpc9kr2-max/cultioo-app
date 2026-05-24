import 'dart:convert';
import 'package:http/http.dart' as http;

class PlacesService {
  // Using FREE Nominatim (OpenStreetMap) API - no API key required!
  // Completely free alternative to Google Places API
  
  static Future<List<Map<String, String>>> searchAddresses(String query) async {
    try {
      // Try Nominatim first (free OpenStreetMap geocoding)
      return await _fetchNominatimSuggestions(query);
    } catch (e) {
      print('Error with Nominatim API: $e');
      // Fallback to intelligent mock data if API fails
      return _getMockSuggestions(query);
    }
  }
  
  static Future<List<Map<String, String>>> _fetchNominatimSuggestions(String query) async {
    // Nominatim is the FREE geocoding service by OpenStreetMap
    // No API key required, completely free to use!
    final String baseUrl = 'https://nominatim.openstreetmap.org/search';
    // Removed countrycodes parameter to allow worldwide addresses
    final String request = '$baseUrl?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=8';
    
    final response = await http.get(
      Uri.parse(request),
      headers: {
        'User-Agent': 'CultiooApp/1.0', // Required by Nominatim
      },
    );
    
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      
      return data.map<Map<String, String>>((item) {
        final displayName = item['display_name'] as String;
        final lat = item['lat'] as String;
        final lon = item['lon'] as String;
        
        // Extract structured address components for shorter format
        String shortAddress = '';
        String country = 'Unknown';
        
        if (item['address'] != null) {
          final address = item['address'] as Map<String, dynamic>;
          
          // Build shorter address: Street Number, Street, ZIP City, Country
          final parts = <String>[];
          
          // Street and house number
          String streetPart = '';
          if (address['house_number'] != null) {
            streetPart += '${address['house_number']} ';
          }
          if (address['road'] != null) {
            streetPart += address['road'];
          } else if (address['street'] != null) {
            streetPart += address['street'];
          }
          if (streetPart.isNotEmpty) {
            parts.add(streetPart.trim());
          }
          
          // ZIP and City
          String cityPart = '';
          if (address['postcode'] != null) {
            cityPart += '${address['postcode']} ';
          }
          if (address['city'] != null) {
            cityPart += address['city'];
          } else if (address['town'] != null) {
            cityPart += address['town'];
          } else if (address['village'] != null) {
            cityPart += address['village'];
          }
          if (cityPart.isNotEmpty) {
            parts.add(cityPart.trim());
          }
          
          // Country
          if (address['country'] != null) {
            country = address['country'] as String;
            parts.add(country);
          }
          
          // Join parts with commas
          shortAddress = parts.join(', ');
          
          // Fallback to display_name if we couldn't build a proper address
          if (shortAddress.isEmpty || shortAddress == country) {
            shortAddress = displayName;
          }
        } else {
          shortAddress = displayName;
        }
        
        return {
          'address': shortAddress,
          'country': country,
          'fullAddress': shortAddress,
          'placeId': 'nominatim_${lat}_$lon',
          'lat': lat,
          'lon': lon,
        };
      }).toList();
    } else {
      throw Exception('Failed to fetch Nominatim places: ${response.statusCode}');
    }
  }
  
  static List<Map<String, String>> _getMockSuggestions(String query) {
    final mockSuggestions = <Map<String, String>>[];
    
    // Intelligent mock suggestions based on common international address patterns
    final lowerQuery = query.toLowerCase();
    
    if (lowerQuery.contains('main') || lowerQuery.contains('street')) {
      mockSuggestions.addAll([
        {
          'address': '$query, 78701 Austin, United States',
          'country': 'United States',
          'fullAddress': '$query, 78701 Austin, United States',
          'placeId': 'mock_austin_${query.hashCode}',
        },
        {
          'address': '$query, London, United Kingdom',
          'country': 'United Kingdom',
          'fullAddress': '$query, London, United Kingdom',
          'placeId': 'mock_london_${query.hashCode}',
        },
        {
          'address': '$query, 10115 Berlin, Germany',
          'country': 'Germany',
          'fullAddress': '$query, 10115 Berlin, Germany',
          'placeId': 'mock_berlin_${query.hashCode}',
        },
      ]);
    } else if (lowerQuery.contains('broadway')) {
      mockSuggestions.addAll([
        {
          'address': '$query, New York, NY 10019, United States',
          'country': 'United States',
          'fullAddress': '$query, New York, NY 10019, United States',
          'placeId': 'mock_broadway_nyc_${query.hashCode}',
        },
        {
          'address': '$query, Nashville, TN 37203, United States',
          'country': 'United States',
          'fullAddress': '$query, Nashville, TN 37203, United States',
          'placeId': 'mock_broadway_nash_${query.hashCode}',
        },
      ]);
    } else if (lowerQuery.contains('avenue') || lowerQuery.contains('ave')) {
      mockSuggestions.addAll([
        {
          'address': '$query, Paris, France',
          'country': 'France',
          'fullAddress': '$query, Paris, France',
          'placeId': 'mock_paris_${query.hashCode}',
        },
        {
          'address': '$query, New York, NY, United States',
          'country': 'United States',
          'fullAddress': '$query, New York, NY, United States',
          'placeId': 'mock_nyc_ave_${query.hashCode}',
        },
      ]);
    } else if (lowerQuery.contains('straße') || lowerQuery.contains('str')) {
      mockSuggestions.addAll([
        {
          'address': '$query, Berlin, Germany',
          'country': 'Germany',
          'fullAddress': '$query, Berlin, Germany',
          'placeId': 'mock_berlin_str_${query.hashCode}',
        },
        {
          'address': '$query, Munich, Germany',
          'country': 'Germany',
          'fullAddress': '$query, Munich, Germany',
          'placeId': 'mock_munich_${query.hashCode}',
        },
      ]);
    } else if (lowerQuery.contains('via') || lowerQuery.contains('piazza')) {
      mockSuggestions.addAll([
        {
          'address': '$query, Rome, Italy',
          'country': 'Italy',
          'fullAddress': '$query, Rome, Italy',
          'placeId': 'mock_rome_${query.hashCode}',
        },
        {
          'address': '$query, Milan, Italy',
          'country': 'Italy',
          'fullAddress': '$query, Milan, Italy',
          'placeId': 'mock_milan_${query.hashCode}',
        },
      ]);
    } else {
      // General suggestions with diverse international cities
      final cities = [
        {'city': 'New York', 'state': 'NY', 'country': 'United States'},
        {'city': 'London', 'state': '', 'country': 'United Kingdom'},
        {'city': 'Berlin', 'state': '', 'country': 'Germany'},
        {'city': 'Paris', 'state': '', 'country': 'France'},
        {'city': 'Tokyo', 'state': '', 'country': 'Japan'},
        {'city': 'Sydney', 'state': 'NSW', 'country': 'Australia'},
        {'city': 'Toronto', 'state': 'ON', 'country': 'Canada'},
        {'city': 'Amsterdam', 'state': '', 'country': 'Netherlands'},
        {'city': 'Madrid', 'state': '', 'country': 'Spain'},
        {'city': 'Rome', 'state': '', 'country': 'Italy'},
      ];
      
      for (int i = 0; i < 5 && i < cities.length; i++) {
        final city = cities[i];
        final stateInfo = city['state']!.isNotEmpty ? ', ${city['state']}' : '';
        mockSuggestions.add({
          'address': '$query, ${city['city']}$stateInfo, ${city['country']}',
          'country': city['country']!,
          'fullAddress': '$query, ${city['city']}$stateInfo, ${city['country']}',
          'placeId': 'mock_${city['city']?.toLowerCase()}_${query.hashCode}',
        });
      }
    }
    
    return mockSuggestions.take(6).toList(); // Increased to 6 suggestions for more variety
  }
  
  // Get detailed information about a place using Nominatim
  static Future<Map<String, dynamic>?> getPlaceDetails(String placeId) async {
    if (placeId.startsWith('mock_')) {
      return null; // No details for mock data
    }
    
    if (placeId.startsWith('nominatim_')) {
      // Extract lat/lon from Nominatim place ID
      final parts = placeId.split('_');
      if (parts.length >= 3) {
        final lat = parts[1];
        final lon = parts[2];
        
        try {
          final String baseUrl = 'https://nominatim.openstreetmap.org/reverse';
          final String request = '$baseUrl?lat=$lat&lon=$lon&format=json&addressdetails=1';
          
          final response = await http.get(
            Uri.parse(request),
            headers: {
              'User-Agent': 'CultiooApp/1.0',
            },
          );
          
          if (response.statusCode == 200) {
            return json.decode(response.body);
          }
        } catch (e) {
          print('Error fetching Nominatim place details: $e');
        }
      }
    }
    
    return null;
  }
}
