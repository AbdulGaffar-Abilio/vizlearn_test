import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../utils/hologram_client.dart';

class NetworkModePage extends StatefulWidget {
  const NetworkModePage({super.key});

  @override
  State<NetworkModePage> createState() => _NetworkModePageState();
}

class _NetworkModePageState extends State<NetworkModePage> with SingleTickerProviderStateMixin {
  late final TextEditingController serverUrlController;
  late final TextEditingController deviceIdController;
  late final TextEditingController devicePasswordController;
  HologramClient? client;
  StreamSubscription<Map<String, dynamic>>? sub;
  String? selectedDeviceId;
  int brightness = 15;
  int volume = 10;
  int playMode = 1;
  int speed = 750;
  late TabController _tabController;
  final List<String> _logs = <String>[];
  StreamSubscription<String>? logsSub;
  bool _isConnecting = false;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    serverUrlController = TextEditingController(text: 'ws://your-server.com:7110');
    deviceIdController = TextEditingController();
    devicePasswordController = TextEditingController();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    sub?.cancel();
    client?.disconnect();
    serverUrlController.dispose();
    deviceIdController.dispose();
    devicePasswordController.dispose();
    logsSub?.cancel();
    super.dispose();
  }


  Future<void> connect() async {
    final serverUrl = serverUrlController.text.trim();
    final deviceId = deviceIdController.text.trim();
    
    if (serverUrl.isEmpty || deviceId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter server URL and device ID'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isConnecting = true;
      _isReady = false;
    });

    try {
      // Parse server URL to extract IP/host
      Uri uri;
      try {
        uri = Uri.parse(serverUrl);
      } catch (e) {
        // If not a full URL, treat as IP address
        uri = Uri.parse('ws://$serverUrl:7110');
      }

      final ip = uri.host;
      final c = HologramClient(ip: ip);
      c.isNetworkMode = true; // Set network mode flag
      
      await Future.delayed(const Duration(seconds: 2));
      await c.connect(timeout: const Duration(seconds: 30));
      
      sub?.cancel();
      sub = c.messages.listen((msg) {
        setState(() {
          selectedDeviceId ??= c.deviceInfo?.id ?? deviceId;
          if (c.status?.brightness != null) brightness = c.status!.brightness!;
          if (c.status?.volume != null) volume = c.status!.volume!;
          if (c.status?.playMode != null) playMode = c.status!.playMode!;
          if (!_isReady && (msg['cmd'] != null || msg['properties'] != null)) {
            _isReady = true;
            _isConnecting = false;
          }
          if (msg['error'] != null || msg['done'] != null) {
            _isConnecting = false;
          }
        });
      });
      
      logsSub?.cancel();
      logsSub = c.logs.listen((line) {
        setState(() {
          _logs.add(line);
          if (_logs.length > 2000) {
            _logs.removeRange(0, _logs.length - 2000);
          }
        });
      });
      
      setState(() {
        client = c;
        selectedDeviceId = deviceId;
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isReady = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> disconnect() async {
    await client?.disconnect();
    await sub?.cancel();
    await logsSub?.cancel();
    setState(() {
      client = null;
      selectedDeviceId = null;
      _logs.clear();
      _isConnecting = false;
      _isReady = false;
    });
  }

  String? get deviceId => selectedDeviceId ?? deviceIdController.text.trim();

  void sendControl(int value, {int? fileId, int? brightnessVal, int? volumeVal, int? playModeVal, int? speedVal, int? adjustmentVal}) {
    final id = deviceId;
    if (client == null || id == null || id.isEmpty) return;
    client!.sendDeviceControl(
      id: id,
      value: value,
      fileId: fileId,
      brightness: brightnessVal ?? brightness,
      volume: volumeVal ?? volume,
      playMode: playModeVal ?? playMode,
      speedValue: speedVal ?? speed,
      adjustmentValue: adjustmentVal ?? 1,
      isNetworkMode: true, // Use network mode
    );
  }

  Future<void> pickAndUploadVideo() async {
    final id = deviceId;
    if (client == null || id == null || id.isEmpty) return;
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    
    Timer? progressUpdateTimer;
    StreamSubscription<String>? progressSub;
    ValueNotifier<int>? progressNotifier;
    
    try {
      Uint8List bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else {
        final xf = file.xFile;
        bytes = await xf.readAsBytes();
      }
      final fileId = DateTime.now().millisecondsSinceEpoch % 1000000;
      
      progressNotifier = ValueNotifier<int>(0);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: ValueListenableBuilder<int>(
              valueListenable: progressNotifier,
              builder: (context, progress, _) {
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Uploading to cloud: ${file.name}'),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(value: progress / 100),
                          const SizedBox(height: 4),
                          Text('$progress%', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            duration: const Duration(minutes: 5),
            backgroundColor: Colors.blue,
          ),
        );
        
        final notifier = progressNotifier;
        progressUpdateTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
          if (mounted) {
            final progress = client!.fileProgress[fileId] ?? 0;
            notifier.value = progress;
            if (progress >= 100) {
              timer.cancel();
            }
          } else {
            timer.cancel();
          }
        });
      }
      
      final notifier = progressNotifier;
      progressSub = client!.logs.listen((_) {
        if (mounted) {
          setState(() {});
          final progress = client!.fileProgress[fileId] ?? 0;
          notifier.value = progress;
        }
      });
      
      // Upload via network mode (type=2 for cluster/network mode)
      await client!.uploadVideo(
        id: id,
        fileId: fileId,
        fileName: file.name,
        bytes: bytes,
        isNetworkMode: true, // Use network mode
      );
      
      progressSub.cancel();
      progressUpdateTimer?.cancel();
      progressNotifier.dispose();
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video uploaded to cloud successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      if (mounted) setState(() {});
    } catch (e, stackTrace) {
      if (progressUpdateTimer != null) progressUpdateTimer.cancel();
      if (progressSub != null) progressSub.cancel();
      if (progressNotifier != null) progressNotifier.dispose();
      debugPrint('Cloud video upload error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cloud upload failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = client;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Mode'),
        bottom: c != null && _isReady
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                tabs: const [
                  Tab(text: 'Connection'),
                  Tab(text: 'Basic Controls'),
                  Tab(text: 'Advanced Controls'),
                  Tab(text: 'Cloud Media'),
                  Tab(text: 'Device Info'),
                  Tab(text: 'Logs'),
                ],
              )
            : null,
        actions: [
          IconButton(
            onPressed: _isConnecting ? null : (c == null ? connect : disconnect),
            icon: Icon(c == null ? Icons.cloud_upload : Icons.cloud_off),
            tooltip: _isConnecting ? 'Connecting…' : (c == null ? 'Connect' : 'Disconnect'),
          )
        ],
      ),
      body: Column(
        children: [
          // Connection section
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: serverUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL (ws://server.com:7110)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.cloud),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: deviceIdController,
                        decoration: const InputDecoration(
                          labelText: 'Device ID',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.devices),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: devicePasswordController,
                        decoration: const InputDecoration(
                          labelText: 'Password (optional)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock),
                        ),
                        obscureText: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isConnecting ? null : (c == null ? connect : disconnect),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: Text(_isConnecting ? 'Connecting…' : (c == null ? 'Connect to Cloud' : 'Disconnect')),
                ),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: c == null
                ? const Center(child: Text('Not connected. Please connect to cloud server first.'))
                : !_isReady
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildConnectionTab(c),
                          _buildBasicControlsTab(c),
                          _buildAdvancedControlsTab(c),
                          _buildCloudMediaTab(c),
                          _buildDeviceInfoTab(c),
                          _buildLogsTab(c),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionTab(HologramClient c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Network Mode Connection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('Connect to hologram devices over the cloud/network.'),
                  const SizedBox(height: 16),
                  _buildInfoRow('Server URL', serverUrlController.text),
                  _buildInfoRow('Device ID', deviceIdController.text),
                  _buildInfoRow('Connection Status', c.isConnected ? 'Connected' : 'Disconnected'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('WiFi Configuration for Network Mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Configure device WiFi to connect to your network for cloud access.'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _showWiFiConfigDialog(c),
                    icon: const Icon(Icons.wifi),
                    label: const Text('Configure WiFi'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicControlsTab(HologramClient c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => sendControl(1),
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Power On'),
              ),
              ElevatedButton.icon(
                onPressed: () => sendControl(0),
                icon: const Icon(Icons.power_off),
                label: const Text('Shutdown'),
              ),
              ElevatedButton.icon(
                onPressed: () => sendControl(2),
                icon: const Icon(Icons.refresh),
                label: const Text('Restart'),
              ),
              ElevatedButton.icon(
                onPressed: () => sendControl(3),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              ElevatedButton.icon(
                onPressed: () => sendControl(5),
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Brightness (0-15)', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: 15,
                          divisions: 15,
                          value: brightness.toDouble(),
                          label: '$brightness',
                          onChanged: (v) => setState(() => brightness = v.toInt()),
                          onChangeEnd: (_) => sendControl(7, brightnessVal: brightness),
                        ),
                      ),
                      SizedBox(width: 60, child: Text('$brightness', textAlign: TextAlign.center)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Volume (0-15)', style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: 15,
                          divisions: 15,
                          value: volume.toDouble(),
                          label: '$volume',
                          onChanged: (v) => setState(() => volume = v.toInt()),
                          onChangeEnd: (_) => sendControl(0xB, volumeVal: volume),
                        ),
                      ),
                      SizedBox(width: 60, child: Text('$volume', textAlign: TextAlign.center)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Play Mode', style: TextStyle(fontWeight: FontWeight.bold)),
                  DropdownButtonFormField<int>(
                    value: playMode,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Sequential Loop')),
                      DropdownMenuItem(value: 2, child: Text('Single Loop')),
                      DropdownMenuItem(value: 3, child: Text('Random Play')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => playMode = v);
                      sendControl(0x21, playModeVal: v);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedControlsTab(HologramClient c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rotation Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: () => sendControl(0x23),
                icon: const Icon(Icons.rotate_right),
                label: const Text('Forward Rotation'),
              ),
              ElevatedButton.icon(
                onPressed: () => sendControl(0x24),
                icon: const Icon(Icons.rotate_left),
                label: const Text('Reverse Rotation'),
              ),
              ElevatedButton.icon(
                onPressed: () => sendControl(0x25),
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Power On Rotation'),
              ),
              ElevatedButton.icon(
                onPressed: () => sendControl(0x26),
                icon: const Icon(Icons.power_off),
                label: const Text('Power On Non Rotation'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCloudMediaTab(HologramClient c) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: pickAndUploadVideo,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Upload Video to Cloud'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final id = deviceId;
                  if (id != null) {
                    c.refreshFileList(id: id, isNetworkMode: true);
                    Future.delayed(const Duration(milliseconds: 500), () {
                      setState(() {});
                    });
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Media List'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              final id = deviceId;
              if (id != null) {
                c.refreshFileList(id: id, isNetworkMode: true);
                await Future<void>.delayed(const Duration(milliseconds: 500));
              }
              setState(() {});
            },
            child: c.files.isEmpty
                ? const Center(child: Text('No media files found'))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.6,
                    ),
                    itemCount: c.files.length,
                    itemBuilder: (context, index) {
                      final f = c.files[index];
                      final progress = c.fileProgress[f.fileId] ?? f.percentage;
                      return Card(
                        child: InkWell(
                          onTap: () {
                            sendControl(5); // Pause
                            Future.delayed(const Duration(milliseconds: 100), () {
                              sendControl(6, fileId: f.fileId); // Play Specific File
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Center(
                                    child: Icon(f.fileType == 1 ? Icons.image : Icons.video_library, size: 48),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(f.fileName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Text('ID: ${f.fileId}  ${(f.fileType == 1) ? 'IMG' : 'VID'}  $progress%', style: const TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        final id = deviceId;
                                        if (id == null) return;
                                        c.deleteFiles(id: id, fileId: f.fileId, type: 2); // type=2 for network mode
                                        Future.delayed(const Duration(milliseconds: 500), () {
                                          c.refreshFileList(id: id, isNetworkMode: true);
                                          setState(() {});
                                        });
                                      },
                                      tooltip: 'Delete ${f.fileName}',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceInfoTab(HologramClient c) {
    final info = c.deviceInfo;
    final status = c.status;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Device Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  _buildInfoRow('Device ID', info?.id ?? '-'),
                  _buildInfoRow('SN/Name', info?.name ?? '-'),
                  _buildInfoRow('Version', info?.versionNumber ?? '-'),
                  _buildInfoRow('Device Type', info?.deviceType?.toString() ?? '-'),
                  _buildInfoRow('Brand Name', info?.brandName ?? '-'),
                  _buildInfoRow('App Name', info?.appName ?? '-'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Device Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Divider(),
                  _buildInfoRow('Power State', status?.open == true ? 'ON' : status?.open == false ? 'OFF' : '-'),
                  _buildInfoRow('Brightness', '${status?.brightness ?? '-'} / 15'),
                  _buildInfoRow('Volume', '${status?.volume ?? '-'} / 15'),
                  _buildInfoRow('Play Mode', _getPlayModeName(status?.playMode)),
                  _buildInfoRow('Current File ID', status?.fileId?.toString() ?? '-'),
                  _buildInfoRow('WiFi Signal', '${status?.wifiSignal ?? '-'}%'),
                  _buildInfoRow('Free Space', '${status?.memory ?? '-'} MB'),
                  _buildInfoRow('IP Address', status?.ip ?? '-'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsTab(HologramClient c) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => setState(() => _logs.clear()),
                icon: const Icon(Icons.clear),
                label: const Text('Clear Logs'),
              ),
              const SizedBox(width: 8),
              Text('Lines: ${_logs.length}')
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: _logs.length,
            separatorBuilder: (context, index) => const Divider(height: 1, thickness: 1),
            itemBuilder: (context, index) {
              final line = _logs[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  line,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _getPlayModeName(int? mode) {
    switch (mode) {
      case 1:
        return 'Sequential Loop';
      case 2:
        return 'Single Loop';
      case 3:
        return 'Random Play';
      default:
        return '-';
    }
  }

  void _showWiFiConfigDialog(HologramClient c) {
    final id = deviceId;
    if (id == null) return;

    final modeController = TextEditingController(text: '0');
    final ssidController = TextEditingController();
    final passwordController = TextEditingController();
    bool isHotspot = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('WiFi Configuration (Network Mode)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Configure device WiFi to connect to your network for cloud access.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: 0,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Change')),
                  DropdownMenuItem(value: 1, child: Text('Add')),
                  DropdownMenuItem(value: 2, child: Text('Delete')),
                ],
                onChanged: (v) => modeController.text = v.toString(),
              ),
              CheckboxListTile(
                title: const Text('Is Hotspot'),
                value: isHotspot,
                onChanged: (v) => setDialogState(() => isHotspot = v ?? false),
              ),
              TextField(
                controller: ssidController,
                decoration: const InputDecoration(labelText: 'SSID'),
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final mode = int.tryParse(modeController.text) ?? 0;
                c.configureWiFi(
                  id: id,
                  mode: mode,
                  isHotspot: isHotspot,
                  ssid: ssidController.text.isNotEmpty ? ssidController.text : null,
                  password: passwordController.text.isNotEmpty ? passwordController.text : null,
                );
                Navigator.pop(context);
              },
              child: const Text('Configure'),
            ),
          ],
        ),
      ),
    );
  }
}

