import 'dart:typed_data';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hologram_test/theme/theme.dart';

import 'utils/hologram_client.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hologram Tester',
      theme: theme,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  final ipController = TextEditingController(text: '192.168.43.1');
  HologramClient? client;
  StreamSubscription<Map<String, dynamic>>? sub;
  String? selectedDeviceId;
  int brightness = 15;
  int volume = 10;
  int playMode = 1; // 1 seq, 2 single, 3 random
  int speed = 750; // 600-900
  int adjustmentValue = 1; // 0-decrease, 1-increase
  late TabController _tabController;
  final List<String> _logs = <String>[];
  StreamSubscription<String>? logsSub;
  bool _isConnecting = false;
  bool _isReady = false;
  Timer? _anglePressTimer;
  int? _currentAngleAdjustment; // 0 for decrease, 1 for increase, null if not pressing
  int? _lastPlayedFileId; // Track last played file to prevent duplicate plays
  DateTime? _lastPlayTime; // Track when last play command was sent

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    sub?.cancel();
    client?.disconnect();
    ipController.dispose();
    _anglePressTimer?.cancel();
    super.dispose();
  }

  Future<void> connect() async {
    final ip = ipController.text.trim();
    if (ip.isEmpty) return;
    setState(() {
      _isConnecting = true;
      _isReady = false;
    });
    try {
      final c = HologramClient(ip: ip);
      // Wait a bit for WiFi connection to stabilize, then connect with timeout
      await Future.delayed(const Duration(seconds: 3));
      await c.connect(timeout: const Duration(seconds: 20));
      sub?.cancel();
      sub = c.messages.listen((msg) {
        setState(() {
          selectedDeviceId ??= c.deviceInfo?.id ?? c.status?.ip ?? '';
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
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _isReady = false;
      });
      // Show error to user
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

  String? get deviceId => selectedDeviceId ?? client?.deviceInfo?.id;

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
      adjustmentValue: adjustmentVal ?? adjustmentValue,
    );
  }

  void _startAngleAdjustment(int adjustmentValue) {
    _stopAngleAdjustment(); // Stop any existing timer
    _currentAngleAdjustment = adjustmentValue;
    // Send initial command
    sendControl(0x10, adjustmentVal: adjustmentValue);
    // Start timer to send commands repeatedly
    _anglePressTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_currentAngleAdjustment != null) {
        sendControl(0x10, adjustmentVal: _currentAngleAdjustment!);
      } else {
        timer.cancel();
      }
    });
  }

  void _stopAngleAdjustment() {
    _anglePressTimer?.cancel();
    _anglePressTimer = null;
    _currentAngleAdjustment = null;
  }

  Future<void> pickAndUploadVideo() async {
    final id = deviceId;
    if (client == null || id == null || id.isEmpty) return;
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    
    // Declare progress tracking variables outside try block
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
      
      // Show upload progress with periodic updates
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
                          Text('Uploading: ${file.name}'),
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
            duration: const Duration(minutes: 5), // Long duration to show progress
            backgroundColor: Colors.blue,
          ),
        );
        
        // Update progress display periodically
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
      
      // Listen to progress updates and refresh UI
      final notifier = progressNotifier;
      progressSub = client!.logs.listen((_) {
        if (mounted) {
          setState(() {});
          final progress = client!.fileProgress[fileId] ?? 0;
          notifier.value = progress;
        }
      });
      
      await client!.uploadVideo(
        id: id,
        fileId: fileId,
        fileName: file.name,
        bytes: bytes,
      );
      
      progressSub.cancel();
      progressUpdateTimer?.cancel();
      progressNotifier.dispose();
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video uploaded successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      // Refresh UI
      if (mounted) setState(() {});
    } catch (e, stackTrace) {
      if (progressUpdateTimer != null) progressUpdateTimer.cancel();
      if (progressSub != null) progressSub.cancel();
      if (progressNotifier != null) progressNotifier.dispose();
      debugPrint('Video upload error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video upload failed: $e'),
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
        title: const Text('Hologram Tester'),
        bottom: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                tabs: const [
                  Tab(text: 'Basic Controls'),
                  Tab(text: 'Advanced Controls'),
                  Tab(text: 'Media'),
                  Tab(text: 'System Settings'),
                  Tab(text: 'Device Info'),
                  Tab(text: 'Logs'),
                ],
              ),
        actions: [
          IconButton(
            onPressed: _isConnecting ? null : (c == null ? connect : disconnect),
            icon: Icon(c == null ? Icons.link : Icons.link_off),
            tooltip: _isConnecting ? 'Connecting…' : (c == null ? 'Connect' : 'Disconnect'),
          )
        ],
      ),
      body: Column(
        children: [
          // Connection section
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ipController,
                    decoration: const InputDecoration(
                      labelText: 'Device IP (AP mode default: 192.168.43.1)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isConnecting ? null : (c == null ? connect : disconnect),
                  child: Text(_isConnecting ? 'Connecting…' : (c == null ? 'Connect' : 'Disconnect')),
                ),
              ],
            ),
          ),
          // Tab content
          Expanded(
            child: _isConnecting
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBasicControlsTab(c),
                      _buildAdvancedControlsTab(c),
                      _buildMediaTab(c),
                      _buildSystemSettingsTab(c),
                      _buildDeviceInfoTab(c),
                      _buildLogsTab(c),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicControlsTab(HologramClient? c) {
    final isConnected = c != null && _isReady;
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
                onPressed: isConnected ? () => sendControl(1) : null,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Power On'),
              ),
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(0) : null,
                icon: const Icon(Icons.power_off),
                label: const Text('Shutdown'),
              ),
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(2) : null,
                icon: const Icon(Icons.refresh),
                label: const Text('Restart'),
              ),
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(3) : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play'),
              ),
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(5) : null,
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
                          onChangeEnd: isConnected ? (_) => sendControl(7, brightnessVal: brightness) : null,
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
                          onChangeEnd: isConnected ? (_) => sendControl(0xB, volumeVal: volume) : null,
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
                    initialValue: playMode,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Sequential Loop')),
                      DropdownMenuItem(value: 2, child: Text('Single Loop')),
                      DropdownMenuItem(value: 3, child: Text('Random Play')),
                    ],
                    onChanged: isConnected ? (v) {
                      if (v == null) return;
                      setState(() => playMode = v);
                      sendControl(0x21, playModeVal: v);
                    } : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Factory Reset', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Reset all settings to factory defaults:\n'
                      '• Brightness: 15\n'
                      '• Volume: 15\n'
                      '• Play Mode: Sequential Loop\n'
                      '• Speed: 750\n'
                      '• Rotation: On\n'
                      '• Angle: Closed',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: isConnected ? () async {
                      final id = deviceId;
                      if (id != null) {
                        // Show confirmation dialog
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Factory Reset'),
                            content: const Text('This will reset all settings to factory defaults. Continue?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Reset', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirmed == true) {
                          await c.factoryReset(id: id);
                          // Update local state to match defaults
                          setState(() {
                            brightness = 15;
                            volume = 15;
                            playMode = 1;
                            speed = 750;
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Factory reset complete'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        }
                      }
                    } : null,
                    icon: const Icon(Icons.restore),
                    label: const Text('Factory Reset'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedControlsTab(HologramClient? c) {
    final isConnected = c != null && _isReady;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Angle Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              GestureDetector(
                onLongPressStart: isConnected ? (_) => _startAngleAdjustment(0) : null,
                onLongPressEnd: isConnected ? (_) => _stopAngleAdjustment() : null,
                child: ElevatedButton.icon(
                  onPressed: isConnected ? () => sendControl(0x10, adjustmentVal: 0) : null,
                  icon: const Icon(Icons.remove),
                  label: const Text('Angle - (Long press)'),
                ),
              ),
              GestureDetector(
                onLongPressStart: isConnected ? (_) => _startAngleAdjustment(1) : null,
                onLongPressEnd: isConnected ? (_) => _stopAngleAdjustment() : null,
                child: ElevatedButton.icon(
                  onPressed: isConnected ? () => sendControl(0x10, adjustmentVal: 1) : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Angle + (Long press)'),
                ),
              ),
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(0x11) : null,
                icon: const Icon(Icons.open_in_full),
                label: const Text('Open Angle'),
              ),
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(0x12) : null,
                icon: const Icon(Icons.close_fullscreen),
                label: const Text('Close Angle'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Rotation Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(0x23) : null,
                icon: const Icon(Icons.rotate_right),
                label: const Text('Forward Rotation'),
              ),
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(0x24) : null,
                icon: const Icon(Icons.rotate_left),
                label: const Text('Reverse Rotation'),
              ),
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(0x25) : null,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Power On Rotation'),
              ),
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(0x26) : null,
                icon: const Icon(Icons.power_off),
                label: const Text('Power On Non Rotation'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: isConnected ? () => sendControl(0x27) : null,
                icon: const Icon(Icons.memory),
                label: const Text('Start Stop Memory'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTab(HologramClient? c) {
    final isConnected = c != null && _isReady;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: isConnected ? pickAndUploadVideo : null,
                icon: const Icon(Icons.video_library),
                label: const Text('Upload Video'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              if (isConnected && c != null) {
                final id = deviceId;
                if (id != null) {
                  c.refreshFileList(id: id);
                  // Wait a bit for the device to respond with file list
                  await Future<void>.delayed(const Duration(milliseconds: 500));
                }
                setState(() {});
              }
            },
            child: c == null || c.files.isEmpty
                ? Center(child: Text(isConnected ? 'No files found' : 'Not connected - Connect to view files'))
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
                      final thumbUrl = (f.thumbPath != null && f.thumbPath!.isNotEmpty)
                          ? Uri.parse('http://${ipController.text.trim()}:8092${f.thumbPath!}').toString()
                          : null;
                      final progress = c.fileProgress[f.fileId] ?? f.percentage;
                      return Card(
                        child: InkWell(
                          onTap: isConnected ? () {
                            // Prevent playing the same file multiple times in quick succession
                            final now = DateTime.now();
                            if (_lastPlayedFileId == f.fileId && 
                                _lastPlayTime != null && 
                                now.difference(_lastPlayTime!) < const Duration(milliseconds: 500)) {
                              return; // Ignore duplicate play requests
                            }
                            
                            _lastPlayedFileId = f.fileId;
                            _lastPlayTime = now;
                            
                            // Pause any currently playing video first, then play the selected file
                            sendControl(5); // Pause
                            Future.delayed(const Duration(milliseconds: 100), () {
                              sendControl(6, fileId: f.fileId); // Play Specific File
                            });
                          } : null,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (thumbUrl != null)
                                  Expanded(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          thumbUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, st) => const Center(child: Icon(Icons.image_not_supported)),
                                        ),
                                        if (progress < 100)
                                          Positioned(
                                            bottom: 0,
                                            left: 0,
                                            right: 0,
                                            child: LinearProgressIndicator(value: progress / 100),
                                          ),
                                      ],
                                    ),
                                  )
                                else
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
                                      onPressed: isConnected ? () {
                                        final id = deviceId;
                                        if (id == null || c == null) return;
                                        c.deleteFiles(id: id, fileId: f.fileId, type: 0);
                                        // Refresh file list after deletion
                                        Future.delayed(const Duration(milliseconds: 500), () {
                                          c.refreshFileList(id: id);
                                          setState(() {});
                                        });
                                      } : null,
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

  Widget _buildSystemSettingsTab(HologramClient? c) {
    final isConnected = c != null && _isReady;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('System Control', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 1) : null,
                child: const Text('Update Immediately'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 5) : null,
                child: const Text('Display Device Info'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 8) : null,
                child: const Text('Open Status Form'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 9) : null,
                child: const Text('Close Status Form'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 17) : null,
                child: const Text('Set Status Report Interval'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 18) : null,
                child: const Text('Set File List Report Interval'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 19) : null,
                child: const Text('Display SN Code'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 20) : null,
                child: const Text('Hide SN Code'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 21) : null,
                child: const Text('Turn On Light Test'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 22) : null,
                child: const Text('Turn Off Light Test'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showSystemControlDialog(c!, 23) : null,
                child: const Text('Set Time'),
              ),
              ElevatedButton(
                onPressed: isConnected ? () => _showColorToneDialog(c!) : null,
                child: const Text('Set Color Tone'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('WiFi Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: isConnected ? () => _showWiFiConfigDialog(c!) : null,
            icon: const Icon(Icons.wifi),
            label: const Text('Configure WiFi'),
          ),
          const SizedBox(height: 24),
          const Text('Bluetooth Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: isConnected ? () => _showBluetoothConfigDialog(c!) : null,
            icon: const Icon(Icons.bluetooth),
            label: const Text('Configure Bluetooth'),
          ),
          const SizedBox(height: 24),
          const Text('Time Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: isConnected ? () => _showTimeConfigDialog(c!) : null,
            icon: const Icon(Icons.schedule),
            label: const Text('Configure Time Schedule'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceInfoTab(HologramClient? c) {
    final info = c?.deviceInfo;
    final status = c?.status;
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
                  _buildInfoRow('Password', info?.password ?? '-'),
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

  void _showSystemControlDialog(HologramClient c, int controlType) {
    final id = deviceId;
    if (id == null) return;

    final secondsController = TextEditingController();
    final dateTimeController = TextEditingController(text: DateTime.now().toString().substring(0, 19));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_getSystemControlTitle(controlType)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controlType == 17 || controlType == 18)
              TextField(
                controller: secondsController,
                decoration: const InputDecoration(
                  labelText: 'Interval (seconds, multiple of 20)',
                  hintText: '20',
                ),
                keyboardType: TextInputType.number,
              ),
            if (controlType == 23)
              TextField(
                controller: dateTimeController,
                decoration: const InputDecoration(
                  labelText: 'Date Time (YYYY-MM-DD HH:MM:SS)',
                ),
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
              final seconds = secondsController.text.isNotEmpty ? int.tryParse(secondsController.text) : null;
              final dateTime = dateTimeController.text.isNotEmpty ? dateTimeController.text : null;
              c.sendSystemControl(
                id: id,
                controlType: controlType,
                seconds: seconds,
                dateTime: dateTime,
              );
              Navigator.pop(context);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  String _getSystemControlTitle(int controlType) {
    switch (controlType) {
      case 1:
        return 'Update Immediately';
      case 5:
        return 'Display Device Information';
      case 8:
        return 'Open Status Form';
      case 9:
        return 'Close Status Form';
      case 17:
        return 'Set Status Report Interval';
      case 18:
        return 'Set File List Report Interval';
      case 19:
        return 'Display SN Code';
      case 20:
        return 'Hide SN Code';
      case 21:
        return 'Turn On Light Test';
      case 22:
        return 'Turn Off Light Test';
      case 23:
        return 'Set Time';
      default:
        return 'System Control';
    }
  }

  void _showColorToneDialog(HologramClient c) {
    final id = deviceId;
    if (id == null) return;

    final rController = TextEditingController(text: '32768');
    final gController = TextEditingController(text: '32768');
    final bController = TextEditingController(text: '32768');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Color Tone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: rController,
              decoration: const InputDecoration(labelText: 'R Tone (0-65536, default: 32768)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: gController,
              decoration: const InputDecoration(labelText: 'G Tone (0-65536, default: 32768)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: bController,
              decoration: const InputDecoration(labelText: 'B Tone (0-65536, default: 32768)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () {
                    rController.text = '32768';
                    gController.text = '50000';
                    bController.text = '50000';
                  },
                  child: const Text('Cool'),
                ),
                ElevatedButton(
                  onPressed: () {
                    rController.text = '52768';
                    gController.text = '32768';
                    bController.text = '32768';
                  },
                  child: const Text('Warm'),
                ),
                ElevatedButton(
                  onPressed: () {
                    rController.text = '65536';
                    gController.text = '65536';
                    bController.text = '65536';
                  },
                  child: const Text('Highlight'),
                ),
                ElevatedButton(
                  onPressed: () {
                    rController.text = '32768';
                    gController.text = '32768';
                    bController.text = '32768';
                  },
                  child: const Text('True Color'),
                ),
              ],
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
              final r = int.tryParse(rController.text) ?? 32768;
              final g = int.tryParse(gController.text) ?? 32768;
              final b = int.tryParse(bController.text) ?? 32768;
              c.sendSystemControl(
                id: id,
                controlType: 24,
                rTone: r,
                gTone: g,
                bTone: b,
              );
              Navigator.pop(context);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
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
          title: const Text('WiFi Configuration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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

  void _showBluetoothConfigDialog(HologramClient c) {
    final id = deviceId;
    if (id == null) return;

    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    int value = 1; // 0-Disconnect, 1-Connect

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bluetooth Configuration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: value,
                decoration: const InputDecoration(labelText: 'Action'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Disconnect')),
                  DropdownMenuItem(value: 1, child: Text('Connect')),
                ],
                onChanged: (v) => setDialogState(() => value = v ?? 1),
              ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Bluetooth Name'),
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password (optional)'),
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
                c.configureBluetooth(
                  id: id,
                  value: value,
                  bluetoothName: nameController.text.isNotEmpty ? nameController.text : null,
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

  void _showTimeConfigDialog(HologramClient c) {
    final id = deviceId;
    if (id == null) return;

    final schedules = <Map<String, dynamic>>[];
    final startTimeController = TextEditingController();
    final endTimeController = TextEditingController();
    final weekDaysController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Time Configuration'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: startTimeController,
                  decoration: const InputDecoration(
                    labelText: 'Start Time (YYYY-MM-DD HH:MM:SS)',
                    hintText: '2020-12-19 17:35:10',
                  ),
                ),
                TextField(
                  controller: endTimeController,
                  decoration: const InputDecoration(
                    labelText: 'End Time (YYYY-MM-DD HH:MM:SS)',
                    hintText: '2020-12-19 17:35:10',
                  ),
                ),
                TextField(
                  controller: weekDaysController,
                  decoration: const InputDecoration(
                    labelText: 'Week Days (binary, e.g., 65 = Mon+Sun)',
                    hintText: '65',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    if (startTimeController.text.isNotEmpty && endTimeController.text.isNotEmpty) {
                      schedules.add({
                        'id': schedules.length,
                        'starttime': startTimeController.text,
                        'endtime': endTimeController.text,
                        'devid': 0,
                        'mergeid': 0,
                        'houseid': 0,
                        'devsandweek': int.tryParse(weekDaysController.text) ?? 0,
                      });
                      setDialogState(() {});
                    }
                  },
                  child: const Text('Add Schedule'),
                ),
                if (schedules.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Schedules:', style: TextStyle(fontWeight: FontWeight.bold)),
                  ...schedules.map((s) => ListTile(
                        title: Text('${s['starttime']} - ${s['endtime']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () {
                            schedules.remove(s);
                            setDialogState(() {});
                          },
                        ),
                      )),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (schedules.isNotEmpty) {
                  c.configureTime(id: id, timeSchedules: schedules);
                  Navigator.pop(context);
                }
              },
              child: const Text('Configure'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsTab(HologramClient? c) {
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
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              thickness: 1,
            ),
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
}
