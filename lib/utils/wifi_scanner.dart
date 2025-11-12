import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:permission_handler/permission_handler.dart';

class WifiNetwork {
  final String ssid;
  final String bssid;
  final int? level; // Signal strength in dBm
  final bool isSecure;
  final int? frequency;

  WifiNetwork({
    required this.ssid,
    required this.bssid,
    this.level,
    this.isSecure = false,
    this.frequency,
  });

  int get signalBars {
    if (level == null) return 0;
    if (level! >= -50) return 4;
    if (level! >= -60) return 3;
    if (level! >= -70) return 2;
    if (level! >= -80) return 1;
    return 0;
  }

  int get signalStrengthPercent {
    if (level == null) return 0;
    // Convert dBm to percentage (rough estimate: -100 to -30 dBm)
    final percent = ((level! + 100) / 70 * 100).clamp(0, 100).toInt();
    return percent;
  }

  bool isHologramDevice(String brandLogo) {
    // Check if SSID starts with brand logo (e.g., "XLZ")
    return ssid.toUpperCase().startsWith(brandLogo.toUpperCase());
  }
}

class WifiScanner extends ChangeNotifier {
  List<WifiNetwork> _networks = [];
  List<WifiNetwork> _hologramDevices = [];
  bool _isScanning = false;
  String _brandLogo = 'XLZ';
  String? _error;

  List<WifiNetwork> get networks => _networks;
  List<WifiNetwork> get hologramDevices => _hologramDevices;
  bool get isScanning => _isScanning;
  String get brandLogo => _brandLogo;
  String? get error => _error;

  void setBrandLogo(String logo) {
    _brandLogo = logo.isEmpty ? 'XLZ' : logo;
    _updateHologramDevices();
    notifyListeners();
  }

  void _updateHologramDevices() {
    _hologramDevices = _networks
        .where((network) => network.isHologramDevice(_brandLogo))
        .toList();
  }

  Future<bool> requestPermissions() async {
    // Request location permission (required for WiFi scanning on Android)
    final locationStatus = await Permission.location.status;
    
    if (!locationStatus.isGranted) {
      final requestResult = await Permission.location.request();
      if (!requestResult.isGranted) {
        _error = 'Location permission is required for WiFi scanning. Please enable it in app settings.';
        notifyListeners();
        return false;
      }
    }

    // Note: nearbyWifiDevices permission (Android 12+) is optional and handled automatically
    // by the system. We don't need to explicitly request it as location permission is sufficient.

    // Check if WiFi scanning is available
    final canGetScannedResults = await WiFiScan.instance.canGetScannedResults();
    if (canGetScannedResults == CanGetScannedResults.notSupported) {
      _error = 'WiFi scanning is not supported on this device';
      notifyListeners();
      return false;
    }

    return true;
  }

  Future<void> startScan() async {
    if (_isScanning) return;

    _error = null;
    _isScanning = true;
    notifyListeners();

    try {
      // Request permissions first
      final hasPermission = await requestPermissions();
      if (!hasPermission) {
        _isScanning = false;
        notifyListeners();
        return;
      }

      // Check if we can get scanned results
      final canGetScannedResults = await WiFiScan.instance.canGetScannedResults();
      
      if (canGetScannedResults == CanGetScannedResults.notSupported) {
        _error = 'WiFi scanning is not supported on this device';
        _isScanning = false;
        notifyListeners();
        return;
      }

      // Start scanning
      final result = await WiFiScan.instance.startScan();
      if (result != true) {
        _error = 'Failed to start WiFi scan. Error: $result';
        _isScanning = false;
        notifyListeners();
        return;
      }

      // Wait a bit for scan to complete (longer wait for better results)
      await Future.delayed(const Duration(seconds: 3));

      // Get scanned results
      List<WiFiAccessPoint> accessPoints = [];
      
      if (canGetScannedResults == CanGetScannedResults.yes) {
        try {
          accessPoints = await WiFiScan.instance.getScannedResults();
        } catch (e) {
          _error = 'Failed to get scan results: $e';
          _isScanning = false;
          notifyListeners();
          return;
        }
      } else if (canGetScannedResults == CanGetScannedResults.notSupported) {
        _error = 'WiFi scanning is not supported on this device';
        _isScanning = false;
        notifyListeners();
        return;
      } else {
        // CanGetScannedResults.requiresLocationPermission
        // Try to get results anyway
        try {
          accessPoints = await WiFiScan.instance.getScannedResults();
        } catch (e) {
          _error = 'Cannot get scanned results. Please ensure location permission is granted: $e';
          _isScanning = false;
          notifyListeners();
          return;
        }
      }

      // Convert to our model
      _networks = accessPoints.map((ap) {
        return WifiNetwork(
          ssid: ap.ssid,
          bssid: ap.bssid,
          level: ap.level,
          isSecure: ap.capabilities.contains('WPA') || 
                    ap.capabilities.contains('WEP') ||
                    ap.capabilities.contains('WPS'),
          frequency: ap.frequency,
        );
      }).toList();

      // Sort by signal strength (strongest first)
      _networks.sort((a, b) {
        final aLevel = a.level ?? -100;
        final bLevel = b.level ?? -100;
        return bLevel.compareTo(aLevel);
      });

      _updateHologramDevices();
      _isScanning = false;
      notifyListeners();
    } catch (e) {
      _error = 'Error scanning WiFi: $e';
      _isScanning = false;
      notifyListeners();
    }
  }

  void clearResults() {
    _networks.clear();
    _hologramDevices.clear();
    _error = null;
    notifyListeners();
  }
}

