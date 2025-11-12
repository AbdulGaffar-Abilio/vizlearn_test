import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wifi_iot/wifi_iot.dart' hide WifiNetwork;
import '../utils/wifi_scanner.dart';
import '../utils/hologram_client.dart';
import '../main.dart';

class DeviceConnectionPage extends StatefulWidget {
  const DeviceConnectionPage({super.key});

  @override
  State<DeviceConnectionPage> createState() => _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends State<DeviceConnectionPage> {
  final WifiScanner _wifiScanner = WifiScanner();
  Timer? _refreshTimer;
  bool _isConnectingToHotspot = false;
  String? _connectedHotspot;
  String? _deviceIp;
  bool _isConnectingToDevice = false;
  bool _isWifiEnabled = true;
  Timer? _wifiCheckTimer;

  @override
  void initState() {
    super.initState();
    // Check WiFi status periodically
    _checkWifiStatus();
    _wifiCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkWifiStatus();
    });
    // Refresh UI periodically to update scanner state
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _checkWifiStatus() async {
    try {
      final isEnabled = await WiFiForIoTPlugin.isEnabled();
      if (mounted && _isWifiEnabled != isEnabled) {
        setState(() {
          _isWifiEnabled = isEnabled;
        });
        if (isEnabled) {
          // WiFi just got enabled, start scanning
          _startScan();
        }
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _wifiCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    // Check if WiFi is enabled first
    final isEnabled = await WiFiForIoTPlugin.isEnabled();
    if (!isEnabled) {
      setState(() {
        _isWifiEnabled = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('WiFi is disabled. Please enable WiFi to scan for devices.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Enable',
              textColor: Colors.white,
              onPressed: () async {
                try {
                  await WiFiForIoTPlugin.setEnabled(true);
                  await Future.delayed(const Duration(seconds: 1));
                  _checkWifiStatus();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not enable WiFi: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ),
        );
      }
      return;
    }
    
    setState(() {
      _isWifiEnabled = true;
    });
    await _wifiScanner.startScan();
  }

  Future<void> _connectToHotspot(WifiNetwork network) async {
    if (_isConnectingToHotspot) return;

    // Check WiFi status first
    final isEnabled = await WiFiForIoTPlugin.isEnabled();
    if (!isEnabled) {
      setState(() {
        _isWifiEnabled = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('WiFi is disabled. Please enable WiFi to connect to the device.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Enable',
              textColor: Colors.white,
              onPressed: () async {
                try {
                  await WiFiForIoTPlugin.setEnabled(true);
                  await Future.delayed(const Duration(seconds: 1));
                  _checkWifiStatus();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Could not enable WiFi: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _isConnectingToHotspot = true;
      _connectedHotspot = null;
      _deviceIp = null;
      _isWifiEnabled = true;
    });

    try {

      // Remove existing network configuration if it exists
      try {
        await WiFiForIoTPlugin.removeWifiNetwork(network.ssid);
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        // Ignore if network doesn't exist
      }

      // Connect to the hologram hotspot programmatically
      const hologramPassword = '88888888';
      bool connected = false;
      
      try {
        if (!network.isSecure) {
          try {
            connected = await WiFiForIoTPlugin.connect(
              network.ssid,
              password: hologramPassword,
              security: NetworkSecurity.WPA,
              joinOnce: false,
            );
          } catch (e) {
            try {
              connected = await WiFiForIoTPlugin.connect(
                network.ssid,
                password: '',
                security: NetworkSecurity.NONE,
                joinOnce: false,
              );
            } catch (e2) {
              // Both failed
            }
          }
        } else {
          try {
            connected = await WiFiForIoTPlugin.connect(
              network.ssid,
              password: hologramPassword,
              security: NetworkSecurity.WPA,
              joinOnce: false,
            );
          } catch (e) {
            try {
              connected = await WiFiForIoTPlugin.connect(
                network.ssid,
                password: hologramPassword,
                security: NetworkSecurity.WEP,
                joinOnce: false,
              );
            } catch (e2) {
              try {
                connected = await WiFiForIoTPlugin.connect(
                  network.ssid,
                  password: hologramPassword,
                  security: NetworkSecurity.WPA,
                  joinOnce: false,
                );
              } catch (e3) {
                // All failed
              }
            }
          }
        }
      } catch (e) {
        try {
          connected = await WiFiForIoTPlugin.connect(
            network.ssid,
            password: hologramPassword,
            joinOnce: false,
          );
        } catch (e2) {
          debugPrint('WiFi connection error: $e2');
        }
      }

      if (connected) {
        // Wait for connection to establish and verify
        bool isConnected = false;
        String? actualIP;
        
        for (int i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          final currentSSID = await WiFiForIoTPlugin.getSSID();
          if (currentSSID != null && currentSSID.replaceAll('"', '') == network.ssid) {
            try {
              final ip = await WiFiForIoTPlugin.getIP();
              if (ip != null && ip.isNotEmpty) {
                actualIP = ip;
              }
            } catch (e) {
              // Ignore IP fetch errors
            }
            
            // Verify connectivity to gateway
            try {
              final client = HttpClient();
              client.connectionTimeout = const Duration(seconds: 2);
              final request = await client.getUrl(Uri.parse('http://192.168.43.1'))
                  .timeout(const Duration(seconds: 2));
              await request.close().timeout(const Duration(seconds: 2));
              client.close();
              isConnected = true;
              break;
            } catch (e) {
              if (i == 29) {
                isConnected = true;
              }
            }
          }
        }

        if (isConnected) {
          setState(() {
            _connectedHotspot = network.ssid;
            _deviceIp = '192.168.43.1';
            _isConnectingToHotspot = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Connected to ${network.ssid}${actualIP != null ? ' (IP: $actualIP)' : ''}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          
          // Automatically connect to device after hotspot connection
          await Future.delayed(const Duration(seconds: 2));
          _connectToDevice();
        } else {
          setState(() {
            _connectedHotspot = network.ssid;
            _deviceIp = '192.168.43.1';
            _isConnectingToHotspot = false;
          });
        }
      } else {
        setState(() {
          _isConnectingToHotspot = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect. Please check if the network is in range and try again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isConnectingToHotspot = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error connecting: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _connectToDevice() async {
    if (_deviceIp == null || _isConnectingToDevice) return;

    setState(() {
      _isConnectingToDevice = true;
    });

    try {
      // Wait for network to stabilize
      await Future.delayed(const Duration(seconds: 2));

      // Verify WiFi is connected
      final currentSSID = await WiFiForIoTPlugin.getSSID();
      if (currentSSID == null || currentSSID.isEmpty) {
        setState(() {
          _isConnectingToDevice = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WiFi not connected. Please connect to the hotspot first.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Show progress message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connecting to device via WebSocket (ws://$_deviceIp:7110)...'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 30),
          ),
        );
      }

      // Connect directly via WebSocket (port 7110) as per documentation
      final client = HologramClient(ip: _deviceIp!);
      await client.connect(timeout: const Duration(seconds: 30));

      // Wait for device to send initial status/info
      await Future.delayed(const Duration(seconds: 2));

      // Hide progress message
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (mounted) {
        // Navigate to main control screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => HomePage(initialClient: client, initialIp: _deviceIp!),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isConnectingToDevice = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect via WebSocket: $e\n\nPlease ensure:\n1. WiFi is connected to the hotspot\n2. Device is powered on\n3. Device IP is correct ($_deviceIp)\n4. WebSocket port 7110 is accessible\n5. Try again in a few seconds'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hologram Device Connection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _startScan,
            tooltip: 'Refresh Scan',
          ),
        ],
      ),
      body: Column(
        children: [
          // WiFi status warning
          if (!_isWifiEnabled)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'WiFi is disabled',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please enable WiFi in your device settings to scan and connect to hologram devices.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await WiFiForIoTPlugin.setEnabled(true);
                        await Future.delayed(const Duration(seconds: 1));
                        _checkWifiStatus();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not enable WiFi automatically. Please enable it manually in settings: $e'),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.wifi),
                    label: const Text('Enable WiFi'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

          // Brand logo input
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: _wifiScanner.brandLogo),
                    decoration: const InputDecoration(
                      labelText: 'Brand Logo',
                      hintText: 'XLZ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.branding_watermark),
                    ),
                    onChanged: (value) {
                      _wifiScanner.setBrandLogo(value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (!_isWifiEnabled || _wifiScanner.isScanning) ? null : _startScan,
                  icon: _wifiScanner.isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find),
                  label: Text(_wifiScanner.isScanning ? 'Scanning...' : 'Scan'),
                ),
              ],
            ),
          ),

          // Connection status
          if (_connectedHotspot != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.wifi, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Connected to Hotspot',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('SSID: $_connectedHotspot'),
                    Text('Device IP: $_deviceIp'),
                    if (_isConnectingToDevice) ...[
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text('Connecting to device via WebSocket...'),
                        ],
                      ),
                    ] else if (!_isConnectingToDevice && _connectedHotspot != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isConnectingToDevice ? null : _connectToDevice,
                          icon: _isConnectingToDevice
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.link),
                          label: Text(_isConnectingToDevice ? 'Connecting...' : 'Connect to Device'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Hologram devices section
          if (_wifiScanner.hologramDevices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Icon(Icons.devices, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Hologram Devices (${_wifiScanner.hologramDevices.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),

          // WiFi networks list
          Expanded(
            child: _wifiScanner.isScanning && _wifiScanner.networks.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Scanning for WiFi networks...'),
                      ],
                    ),
                  )
                : _wifiScanner.networks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.wifi_off,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No WiFi networks found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap "Scan" to search for nearby networks',
                              style: TextStyle(
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _wifiScanner.networks.length,
                        itemBuilder: (context, index) {
                          final network = _wifiScanner.networks[index];
                          final isHologramDevice = network.isHologramDevice(_wifiScanner.brandLogo);
                          final isConnected = _connectedHotspot == network.ssid;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: isHologramDevice
                                ? (isConnected ? Colors.green.shade50 : Colors.blue.shade50)
                                : null,
                            elevation: isHologramDevice ? 2 : 1,
                            child: ListTile(
                              leading: _buildSignalIcon(network),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      network.ssid,
                                      style: TextStyle(
                                        fontWeight: isHologramDevice
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isHologramDevice
                                            ? Colors.blue.shade700
                                            : null,
                                      ),
                                    ),
                                  ),
                                  if (isHologramDevice)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade700,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'DEVICE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  if (isConnected)
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green.shade700,
                                      size: 20,
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (network.bssid.isNotEmpty)
                                    Text(
                                      'BSSID: ${network.bssid}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (network.level != null)
                                    Text(
                                      'Signal: ${network.level} dBm (${network.signalStrengthPercent}%)',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (network.isSecure)
                                    const Row(
                                      children: [
                                        Icon(Icons.lock, size: 12),
                                        SizedBox(width: 4),
                                        Text('Secured', style: TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                ],
                              ),
                              trailing: isHologramDevice && !isConnected
                                  ? ElevatedButton(
                                      onPressed: _isConnectingToHotspot
                                          ? null
                                          : () => _connectToHotspot(network),
                                      child: _isConnectingToHotspot &&
                                              _connectedHotspot == null
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text('Connect'),
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
          ),

          // Error message
          if (_wifiScanner.error != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _wifiScanner.error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSignalIcon(WifiNetwork network) {
    final bars = network.signalBars;
    return SizedBox(
      width: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (index) {
          final isActive = index < bars;
          return Container(
            width: 4,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            height: 4 + (index * 4).toDouble(),
            decoration: BoxDecoration(
              color: isActive
                  ? (bars >= 3
                      ? Colors.green
                      : bars >= 2
                          ? Colors.orange
                          : Colors.red)
                  : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

