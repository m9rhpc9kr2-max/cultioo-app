import '../services/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/trade_republic_widgets.dart';
import '../services/cultioo_spinner.dart';

class LiveLocationMap extends StatefulWidget {
  final int orderId;
  final Map<String, dynamic>? deliveryAddress;

  const LiveLocationMap({
    super.key,
    required this.orderId,
    this.deliveryAddress,
  });

  @override
  State<LiveLocationMap> createState() => _LiveLocationMapState();
}

class _LiveLocationMapState extends State<LiveLocationMap> {
  Timer? _locationUpdateTimer;
  double? _driverLat;
  double? _driverLng;
  DateTime? _lastUpdate;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchDriverLocation();
    // Update location every 10 seconds
    _locationUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchDriverLocation(),
    );
  }

  @override
  void dispose() {
    _locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDriverLocation() async {
    try {
      final response = await ApiService.getDriverLocation(widget.orderId);

      if (!mounted) return; // Check if widget is still mounted

      if (response['success'] == true) {
        final location = response['location'];
        setState(() {
          _driverLat = location['latitude'];
          _driverLng = location['longitude'];
          _lastUpdate = location['updatedAt'] != null
              ? DateTime.parse(location['updatedAt'])
              : null;
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = AppLocalizations.of(context)!.locationNotAvailable;
        });
      }
    } catch (e) {
      print('❌ Error fetching driver location: $e');
      if (!mounted) return; // Check if widget is still mounted
      setState(() {
        _isLoading = false;
        _errorMessage = AppLocalizations.of(context)!.failedToFetchLocation(e.toString());
      });
    }
  }

  Future<void> _openInGoogleMaps() async {
    if (_driverLat == null || _driverLng == null) return;

    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$_driverLat,$_driverLng',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openInAppleMaps() async {
    if (_driverLat == null || _driverLng == null) return;

    final url = Uri.parse('https://maps.apple.com/?q=$_driverLat,$_driverLng');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String _formatLastUpdate() {
    if (_lastUpdate == null) return 'Unknown';

    final now = DateTime.now();
    final difference = now.difference(_lastUpdate!);

    if (difference.inSeconds < 60) {
      return AppLocalizations.of(context)!.justNow;
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min ago';
    } else {
      return '${difference.inHours}h ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show loading only initially
    if (_isLoading && _driverLat == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CultiooLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.loadingDriverLocation,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
      );
    }

    // Show error if location not available
    if (_errorMessage != null && _driverLat == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.location,
              size: 64,
              color: Colors.grey.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? AppLocalizations.of(context)!.driverLocationNotAvailable,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.theDriverHasntSharedLocation,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TradeRepublicButton(
              label: AppLocalizations.of(context)!.retry,
              onPressed: _fetchDriverLocation,
              icon: const Icon(CupertinoIcons.refresh),
            ),
          ],
        ),
      );
    }

    // Show map if we have coordinates
    if (_driverLat == null || _driverLng == null) {
      return Center(
        child: CultiooLoadingIndicator(),
      );
    }

    // Get delivery address coordinates
    final deliveryLat = widget.deliveryAddress?['lat'];
    final deliveryLng = widget.deliveryAddress?['lng'];

    // Build Mapbox Static API URL - always centered on driver
    // Using simple, reliable pin markers that definitely work
    String mapUrl;

    if (deliveryLat != null && deliveryLng != null) {
      // Show both markers: large black pin for driver, small red pin for destination
      // Format: pin-{size}+{color}(lng,lat)
      // NOTE: Mapbox access token should be set via environment variable
      mapUrl =
          'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-l+000000($_driverLng,$_driverLat),pin-s+ff0000($deliveryLng,$deliveryLat)/$_driverLng,$_driverLat,13,0/600x800@2x?access_token=MAPBOX_ACCESS_TOKEN_PLACEHOLDER';
    } else {
      // Show only driver location with large black pin
      // NOTE: Mapbox access token should be set via environment variable
      mapUrl =
          'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/pin-l+000000($_driverLng,$_driverLat)/$_driverLng,$_driverLat,13,0/600x800@2x?access_token=MAPBOX_ACCESS_TOKEN_PLACEHOLDER';
    }

    return Stack(
      children: [
        // Map Preview Image from Mapbox Static API
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(25),
       
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            mapUrl,
            key: ValueKey(
              'map-$_driverLat-$_driverLng-${_lastUpdate?.millisecondsSinceEpoch}',
            ),
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CultiooLoadingIndicator(),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.map_fill, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.mapLoadingFailed,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Info card showing last update
        Positioned(
          top: 20,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(25),
            
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(25),
                  
                  ),
                  child: Icon(
                    CupertinoIcons.cube_box_fill,
                    color: isDark ? Colors.black : Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.driverLocation,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context)!.updatedTime(_formatLastUpdate()),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                TradeRepublicButton(
                  icon: Icon(
                    CupertinoIcons.refresh,
                    size: 20,
                  ),
                  isSecondary: true,
                  width: 48,
                  height: 48,
                  padding: EdgeInsets.zero,
                  borderRadius: BorderRadius.circular(25),
                  onPressed: _fetchDriverLocation,
                ),
              ],
            ),
          ),
        ),

        // Open in Maps buttons
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                  ),
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.googleMaps,
                    onPressed: _openInGoogleMaps,
                    icon: const Icon(CupertinoIcons.map_fill),
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                  ),
                  child: TradeRepublicButton(
                    label: AppLocalizations.of(context)!.appleMaps,
                    onPressed: _openInAppleMaps,
                    icon: const Icon(CupertinoIcons.location_north_fill),
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
