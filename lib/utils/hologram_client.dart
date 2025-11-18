import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'hologram_protocol.dart';

class HologramFileItem {
  HologramFileItem({
    required this.fileId,
    required this.fileType,
    required this.fileName,
    required this.percentage,
    this.playCount,
    this.playOrder,
    this.packNumber,
    this.thumbPath,
  });

  final int fileId;
  final int fileType; // 1 image, 2 video
  final String fileName;
  final int percentage;
  final int? playCount;
  final int? playOrder;
  final int? packNumber;
  final String? thumbPath;
}

class HologramDeviceInfo {
  HologramDeviceInfo({
    this.id,
    this.name,
    this.password,
    this.deviceType,
    this.brandName,
    this.appName,
    this.versionNumber,
  });

  final String? id;
  final String? name;
  final String? password;
  final int? deviceType;
  final String? brandName;
  final String? appName;
  final String? versionNumber;
}

class HologramStatus {
  HologramStatus({
    this.open,
    this.brightness,
    this.volume,
    this.fileId,
    this.wifiSignal,
    this.memory,
    this.playMode,
    this.ip,
  });

  final bool? open;
  final int? brightness; // 0-15
  final int? volume; // 0-15
  final int? fileId;
  final int? wifiSignal; // 0-100
  final int? memory; // MB
  final int? playMode; // 1,2,3
  final String? ip;
}

typedef MessageListener = void Function(Map<String, dynamic> message);

class HologramClient {
  HologramClient({required this.ip})
      : httpBase = Uri.parse('http://$ip:8092'),
        wsUri = Uri.parse('ws://$ip:7110');

  String ip;
  final Uri httpBase;
  final Uri wsUri;
  bool isNetworkMode = false; // Network mode flag (type=2 for cluster/network mode)

  final _protocol = HologramProtocol();
  WebSocketChannel? _channel;
  WebSocket? _ws; // Store WebSocket directly for binary data
  StreamSubscription? _subscription;

  // State
  HologramStatus? status;
  HologramDeviceInfo? deviceInfo;
  List<HologramFileItem> files = [];
  
  // Progress tracking
  final Map<int, int> fileProgress = {}; // fileId -> percentage
  final Map<int, bool> fileFeedback = {}; // feedback_index -> success
  final Map<int, int> _uploadProgress = {}; // fileId -> bytes uploaded

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  // Logs
  final _logController = StreamController<String>.broadcast();
  final List<String> _logBuffer = <String>[];
  Stream<String> get logs => _logController.stream;
  List<String> get logBuffer => List.unmodifiable(_logBuffer);

  void _log(String message) {
    log("--------------------------------------");
    log(message);
    log("--------------------------------------");
    final ts = DateTime.now().toIso8601String();
    final line = '[$ts] $message';
    _logBuffer.add(line);
    if (_logBuffer.length > 500) {
      _logBuffer.removeAt(0);
    }
    _logController.add(line);
  }

  bool get isConnected => _channel != null;

  Future<void> connect({Duration? timeout}) async {
    await disconnect();
    _log('Connecting to WS: $wsUri');
    
    try {
      // Use timeout or default to 20 seconds
      final connectTimeout = timeout ?? const Duration(seconds: 20);
      
      // First, try to check if device is reachable via HTTP
      _log('Checking device connectivity...');
      try {
        final httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 5);
        final request = await httpClient.getUrl(Uri.parse('http://$ip:8092'))
            .timeout(const Duration(seconds: 5));
        await request.close().timeout(const Duration(seconds: 5));
        httpClient.close();
        _log('Device is reachable');
      } catch (e) {
        _log('Device connectivity check failed: $e (continuing anyway)');
      }
      
      // Use WebSocket.connect directly for better timeout handling
      final httpClient = HttpClient();
      httpClient.connectionTimeout = connectTimeout;
      httpClient.idleTimeout = connectTimeout;
      
      _log('Attempting WebSocket connection...');
      final ws = await WebSocket.connect(
        wsUri.toString(),
        customClient: httpClient,
      ).timeout(connectTimeout, onTimeout: () {
        httpClient.close(force: true);
        throw TimeoutException('Connection timeout after ${connectTimeout.inSeconds} seconds. Make sure you are connected to the device WiFi and the device is powered on.', connectTimeout);
      });
      
      // Store WebSocket directly for binary data transmission
      _ws = ws;
      // Create WebSocketChannel from the WebSocket for JSON messages
      final ch = IOWebSocketChannel(ws);
      _channel = ch;
      _subscription = ch.stream.listen(_onData, onError: (e, st) {
        _messageController.add({'error': e.toString()});
        _log('WebSocket error: $e');
      }, onDone: () {
        _messageController.add({'done': true});
        _log('WebSocket closed');
        disconnect();
      });
      _log('Connected to websocket');
    } catch (e) {
      _log('Connection failed: $e');
      await disconnect();
      _messageController.add({'error': e.toString()});
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    await _ws?.close();
    _ws = null;
    _log('Disconnected');
  }

  void _onData(dynamic data) {
    try {
      if (data is String) {
        final msg = jsonDecode(data) as Map<String, dynamic>;
        _handleJson(msg);
        _messageController.add(msg);
        final preview =  data;
        _log('RX JSON cmd=${msg['cmd']}: $preview');
      } else if (data is List<int>) {
        // Device might send binary feedback (0x1B progress or 0x1C feedback)
        // Check if it's a feedback packet: 0xFA 0xF0 ... 0xFE
        if (data.length >= 3 && data[0] == 0xFA && data[1] == 0xF0) {
          _log('RX Binary feedback packet (${data.length} bytes): cmd=0x${data[2].toRadixString(16)}');
          // Try to parse as feedback if possible
        } else {
          _log('RX Binary (${data.length} bytes) - first bytes: ${data.length > 10 ? data.sublist(0, 10).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ') : 'N/A'}');
        }
      } else if (data is Uint8List) {
        // Handle Uint8List directly
        final list = data.toList();
        if (list.length >= 3 && list[0] == 0xFA && list[1] == 0xF0) {
          _log('RX Binary feedback packet (${list.length} bytes): cmd=0x${list[2].toRadixString(16)}');
        } else {
          _log('RX Binary Uint8List (${list.length} bytes)');
        }
      }
    } catch (e) {
      _log('RX parse error: $e');
    }
  }

  // Helper function to safely parse numeric values that might be strings or numbers
  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
      // Try parsing as double first, then convert to int
      final doubleParsed = double.tryParse(value);
      if (doubleParsed != null) return doubleParsed.toInt();
    }
    return null;
  }

  void _handleJson(Map<String, dynamic> msg) {
    final cmd = msg['cmd'];
    final props = (msg['properties'] ?? {}) as Map<String, dynamic>;
    if (cmd == 0x1A || cmd == 26) {
      status = HologramStatus(
        open: props['open'] as bool?,
        brightness: _parseInt(props['brightness']),
        volume: _parseInt(props['volume']),
        fileId: _parseInt(props['file_id']),
        wifiSignal: _parseInt(props['wifi_signal']),
        memory: _parseInt(props['memory']),
        playMode: _parseInt(props['play_mode']),
        ip: props['ip'] as String?,
      );
    } else if (cmd == 0x40 || cmd == 64) {
      deviceInfo = HologramDeviceInfo(
        id: props['id'] as String?,
        name: props['name'] as String?,
        password: props['password'] as String?,
        deviceType: _parseInt(props['device_type']),
        appName: props['appName'] as String?,
        brandName: props['brandName'] as String?,
        versionNumber: props['versionNumber']?.toString(),
      );
    } else if (cmd == 0x1E || cmd == 30) {
      final list = (props['file'] ?? props['File'] ?? []) as List<dynamic>;
      final mappedFiles = list.map((e) {
        final m = e as Map<String, dynamic>;
        return HologramFileItem(
          fileId: _parseInt(m['file_id']) ?? 0,
          fileType: _parseInt(m['file_type']) ?? 0,
          fileName: (m['file_name'] ?? '').toString(),
          percentage: _parseInt(m['percentage']) ?? 0,
          playCount: _parseInt(m['play_count']),
          playOrder: _parseInt(m['play_order']),
          packNumber: _parseInt(m['pack_number']),
          thumbPath: m['thum_path'] as String?,
        );
      }).toList();
      
      // Deduplicate files by file_id and file_name to prevent duplicate videos/images
      // Use a combination of file_id and file_name as unique key
      final seenFiles = <String>{};
      files = mappedFiles.where((file) {
        // Create unique key from file_id and file_name
        final key = '${file.fileId}_${file.fileName}';
        if (seenFiles.contains(key)) {
          _log('Skipping duplicate file: file_id=${file.fileId}, name=${file.fileName}');
          return false; // Skip duplicate
        }
        seenFiles.add(key);
        return true;
      }).toList();
      
      // Also sort by file_id to ensure consistent ordering
      files.sort((a, b) => a.fileId.compareTo(b.fileId));
      
      _log('File list updated: ${files.length} unique files (deduplicated from ${mappedFiles.length})');
    } else if (cmd == 0x1B || cmd == 27) {
      // File processing progress
      final fileId = _parseInt(props['file_id']);
      final percentage = _parseInt(props['percentage']);
      if (fileId != null && percentage != null) {
        fileProgress[fileId] = percentage;
      }
    } else if (cmd == 0x1C || cmd == 28) {
      // Feedback packet
      final feedbackIndex = _parseInt(props['feedback_index']);
      final state = _parseInt(props['state']);
      if (feedbackIndex != null && state != null) {
        fileFeedback[feedbackIndex] = state == 1; // 1-Success, 0-Failure
      }
    }
  }

  // COMMANDS
  void sendDeviceControl({
    required String id,
    required int value,
    int? fileId,
    int? brightness,
    int? volume,
    int? adjustmentValue,
    int? playMode,
    int? speedValue,
    bool? isNetworkMode,
  }) {
    final order = _protocol.nextOrder();
    // Use current status values if not provided
    final currentBrightness = brightness ?? status?.brightness ?? 1;
    final currentVolume = volume ?? status?.volume ?? 15;
    final currentPlayMode = playMode ?? status?.playMode ?? 1;
    // Speed should be in range 600-900, default to 750
    final currentSpeed = speedValue ?? 750;
    // Use network mode if specified, otherwise use instance flag
    final useNetworkMode = isNetworkMode ?? this.isNetworkMode;
    
    final props = <String, dynamic>{
      'type': useNetworkMode ? 2 : 1, // 1 for standalone, 2 for network mode
      'id': id,
      'value': value,
      'file_id': fileId ?? 0,
      'brightness_value': currentBrightness,
      'adjustment_value': adjustmentValue ?? 1,
      'volume_value': currentVolume,
      'play_mode': currentPlayMode,
      'speed_value': currentSpeed,
    };
    final json = HologramProtocol.envelopeWithProperties(
      cmd: 0x2E,
      order: order,
      properties: props,
      source: useNetworkMode ? id : 0, // Use device ID as source in network mode
      destination: useNetworkMode ? id : 0, // Use device ID as destination in network mode
    );
    _channel?.sink.add(json);
    _log('TX 0x2E DeviceControl value=$value id=$id type=${useNetworkMode ? 2 : 1} file_id=${props['file_id']} brightness=${props['brightness_value']} volume=${props['volume_value']} play_mode=${props['play_mode']} speed=${props['speed_value']}');
    _log('TX JSON: $json');
  }

  void sendSystemControl({
    required String id,
    required int controlType,
    int? seconds,
    String? dateTime,
    int? rTone,
    int? gTone,
    int? bTone,
  }) {
    final order = _protocol.nextOrder();
    final props = <String, dynamic>{
      'type': 1,
      'id': id,
      'control_type': controlType,
      if (seconds != null) 'second': seconds,
      if (dateTime != null) 'date_time': dateTime,
      if (rTone != null) 'r_tone': rTone,
      if (gTone != null) 'g_tone': gTone,
      if (bTone != null) 'b_tone': bTone,
    };
    final json = HologramProtocol.envelopeWithProperties(
      cmd: 0x34,
      order: order,
      properties: props,
      source: 0,
      destination: 0,
    );
    _channel?.sink.add(json);
    _log('TX 0x34 SystemControl type=$controlType second=${props['second']} date_time=${props['date_time']} r=${props['r_tone']} g=${props['g_tone']} b=${props['b_tone']}');
  }

  void prepareToTransmit({
    required String id,
    required int fileId,
    required int fileType, // 1 image, 2 video
    required String fileName,
    int playCount = 1,
    int residenceTime = 0,
    int displayMode = 0,
    int level = 0,
    int position = 0,
    int packNumber = 0,
    int? type, // 0-Device (single device P mode), 1-Splicing (S mode), 2-Cluster (N mode)
    bool? isNetworkMode,
  }) {
    final order = _protocol.nextOrder();
    // Use network mode if specified, otherwise use instance flag
    final useNetworkMode = isNetworkMode ?? this.isNetworkMode;
    final modeType = type ?? (useNetworkMode ? 2 : 0); // 0 for standalone, 2 for network mode
    
    final props = <String, dynamic>{
      'type': modeType,
      'id': id,
      'file_id': fileId,
      'file_type': fileType,
      'play_count': playCount,
      'residence_time': residenceTime,
      'display_mode': displayMode,
      'level': level,
      'position': position,
      'file_name': fileName,
      'pack_number': packNumber,
    };
    final json = HologramProtocol.envelopeWithProperties(
      cmd: 0x41,
      order: order,
      properties: props,
      source: useNetworkMode ? id : 0, // Use device ID as source in network mode
      destination: useNetworkMode ? id : 0, // Use device ID as destination in network mode
    );
    _channel?.sink.add(json);
    _log('TX 0x41 PrepareTransmit type=$fileType mode=$modeType file_id=$fileId name=$fileName');
  }

  Future<void> uploadImageBytes({
    required String id,
    required int fileId,
    required String fileName,
    required Uint8List bytes,
    int chunkSize = 32768, // Protocol says max 32768 bytes per packet (data portion)
    bool? isNetworkMode,
  }) async {
    if (_channel == null) {
      _log('Error: WebSocket not connected');
      throw StateError('WebSocket not connected');
    }

    // Calculate total packet count
    final total = bytes.length;
    final packCount = (total / chunkSize).ceil();
    _log('Image upload preparation: file_id=$fileId name=$fileName size=$total bytes, will send $packCount packets');

    // CRITICAL: Send 0x41 "prepare to transmit" command FIRST
    // Use network mode if specified, otherwise use instance flag
    final useNetworkMode = isNetworkMode ?? this.isNetworkMode;
    prepareToTransmit(
      id: id,
      fileId: fileId,
      fileType: 1, // 1 = Image
      fileName: fileName,
      type: useNetworkMode ? 2 : 0, // 0 for standalone, 2 for network mode
      playCount: 1,
      residenceTime: 0,
      displayMode: 0,
      level: 0,
      position: 0,
      packNumber: 0,
      isNetworkMode: useNetworkMode,
    );
    
    _log('TX 0x41 PrepareToTransmit: file_id=$fileId, file_type=1 (Image), type=${useNetworkMode ? 2 : 0} (${useNetworkMode ? "Network" : "Device"}), pack_number=0, name=$fileName');

    // Wait 300ms for device to be ready after prepare command
    // Device firmware expects ~200-500ms gap between 0x41 and first data packet
    await Future<void>.delayed(const Duration(milliseconds: 300));
    
    // Send all packets sequentially
    for (var i = 0; i < packCount; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize > total) ? total : start + chunkSize;
      final slice = bytes.sublist(start, end);
      
      // Build packet according to protocol: 0XFA 0XF0 66 packNumber packCount packIndex length Data 0XFE
      // Structure: [0xFA, 0xF0, cmd(66), packNumber(0), packCount, packIndex, length(2 bytes BE), data, 0xFE]
      // Note: packNumber in data packet header is 0 (different from pack_number in prepareToTransmit)
      final pkt = HologramProtocol.buildImageDataPacket(
        packCount: packCount,
        packIndex: i + 1, // packIndex starts from 1 (not 0) - CRITICAL
        data: slice,
        cmd: 66, // Fixed command for image data
        packNumber: 0, // packNumber in data packet header is always 0
      );
      
      // Verify packet structure before sending
      if (pkt.length < 9) {
        _log('ERROR: Packet ${i + 1} too short! Expected at least 9 bytes, got ${pkt.length}');
        continue;
      }
      if (pkt[0] != 0xFA || pkt[1] != 0xF0 || pkt[2] != 66 || pkt[pkt.length - 1] != 0xFE) {
        _log('ERROR: Packet ${i + 1} has invalid structure!');
        _log('  Expected: [0xFA, 0xF0, 0x42, ...], got: [0x${pkt[0].toRadixString(16)}, 0x${pkt[1].toRadixString(16)}, 0x${pkt[2].toRadixString(16)}, ...]');
        continue;
      }
      
      // Verify packCount and packIndex values
      if (pkt[4] != (packCount & 0xFF) || pkt[5] != ((i + 1) & 0xFF)) {
        _log('ERROR: Packet ${i + 1} has incorrect packCount or packIndex!');
        _log('  Expected packCount=${packCount & 0xFF}, packIndex=${(i + 1) & 0xFF}');
        _log('  Got packCount=${pkt[4]}, packIndex=${pkt[5]}');
        continue;
      }
      
      // Send binary data through WebSocket
      // CRITICAL: Use WebSocket directly for binary frames to ensure correct transmission
      // Convert Uint8List to List<int> for WebSocket.add()
      final binaryData = pkt.toList();
      if (_ws != null) {
        // WebSocket.add() accepts List<int> for binary frames
        _ws!.add(binaryData);
      } else {
        // Fallback to WebSocketChannel if WebSocket is not available
        _channel?.sink.add(binaryData);
        _log('WARNING: Using WebSocketChannel fallback for binary data');
      }
      
      // Log first few bytes of packet for debugging
      final preview = binaryData.length > 20 
          ? binaryData.sublist(0, 20).map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ')
          : binaryData.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(' ');
      _log('Sent packet ${i + 1}/$packCount: dataLen=${slice.length}, total=${pkt.length} bytes, packCount=${pkt[4]}, packIndex=${pkt[5]}, preview=[$preview...]');
      
      // Small delay between packets to avoid overwhelming the device
      // But not too long - device expects continuous stream
      if (i < packCount - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    
    // Give the device time to process and store the complete image
    // Device needs time to write the file to storage after the last data packet
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    
    // Refresh file list to see the newly uploaded image
    refreshFileList(id: id);
    
    // Wait for file list to be updated from device
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    
    _log('Image upload complete: file_id=$fileId name=$fileName size=$total bytes ($packCount packets) - waiting for device confirmation');
  }

  Future<http.StreamedResponse> uploadVideo({
    required String id,
    required int fileId,
    required String fileName,
    required Uint8List bytes,
    Uri? overrideUploadUrl,
    bool? isNetworkMode,
  }) async {
    // Initialize upload progress
    final totalBytes = bytes.length;
    fileProgress[fileId] = 0;
    _log('Video upload starting: file_id=$fileId name=$fileName size=$totalBytes bytes');
    
    // Per spec, send prepare first, then HTTP upload to http://ip:8092
    // Use network mode if specified, otherwise use instance flag
    final useNetworkMode = isNetworkMode ?? this.isNetworkMode;
    prepareToTransmit(
      id: id,
      fileId: fileId,
      fileType: 2, // 2 = Video
      fileName: fileName,
      type: useNetworkMode ? 2 : 0, // 0 = Device (standalone), 2 = Cluster (network mode)
      isNetworkMode: useNetworkMode,
    );

    // Wait for device to be ready after prepare command
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Try multiple possible endpoints - some devices use /upload or /uploadVideo
    final baseUrl = overrideUploadUrl ?? httpBase;
    final possibleUrls = [
      baseUrl, // Root: http://ip:8092
      baseUrl.resolve('/upload'), // http://ip:8092/upload
      baseUrl.resolve('/uploadVideo'), // http://ip:8092/uploadVideo
    ];

    http.StreamedResponse? resp;
    String? usedUrl;
    Exception? lastError;

    // Optional: quick connectivity check to HTTP port (non-fatal)
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(baseUrl).timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(const Duration(seconds: 5));
      _log('HTTP check ${baseUrl} responded with status ${response.statusCode}');
      client.close();
    } catch (e) {
      _log('WARNING: HTTP ${baseUrl} connectivity check failed: $e (continuing)');
    }

    for (final url in possibleUrls) {
      try {
        // Strategy A: Multipart POST with 'file'
        {
          final req = http.MultipartRequest('POST', url);
          req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
          req.fields['file_id'] = fileId.toString();
          req.fields['file_name'] = fileName;
          _log('Video upload attempt A (multipart:file) POST $url fields=${req.fields}');
          _log('Sending HTTP request...');
          final startTime = DateTime.now();
          
          // Track upload progress - update periodically during upload
          _uploadProgress[fileId] = 0;
          fileProgress[fileId] = 5; // Start at 5% (preparation done)
          Timer? progressTimer;
          progressTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
            // Estimate progress based on elapsed time and file size
            // Assume average upload speed of ~1MB/s for estimation
            final elapsed = DateTime.now().difference(startTime);
            final estimatedSpeed = 1024 * 1024; // 1 MB/s
            final estimatedBytes = (elapsed.inMilliseconds / 1000.0 * estimatedSpeed).toInt();
            final estimatedProgress = ((estimatedBytes / totalBytes) * 100).clamp(5, 95).toInt();
            if (estimatedProgress > (fileProgress[fileId] ?? 0)) {
              fileProgress[fileId] = estimatedProgress;
            }
          });
          
          final streamedResp = await req.send().timeout(
            const Duration(seconds: 60),
            onTimeout: () {
              progressTimer?.cancel();
              final elapsed = DateTime.now().difference(startTime);
              _log('Video upload TIMEOUT (A) after ${elapsed.inSeconds}s');
              throw TimeoutException('Video upload timeout after 60 seconds');
            },
          );
          progressTimer.cancel();
          fileProgress[fileId] = 100; // Mark as complete
          final elapsed = DateTime.now().difference(startTime);
          _log('HTTP completed (A) in ${elapsed.inMilliseconds}ms');
          usedUrl = url.toString();
          _log('Response (A): status=${streamedResp.statusCode} headers=${streamedResp.headers}');
          final responseBody = await streamedResp.stream.bytesToString().timeout(
            const Duration(seconds: 10),
            onTimeout: () => 'Response body read timeout',
          );
          _log('Body (A): ${responseBody.length > 200 ? responseBody.substring(0, 200) + "..." : responseBody}');
          resp = http.StreamedResponse(
            Stream.value(responseBody.codeUnits),
            streamedResp.statusCode,
            headers: streamedResp.headers,
            reasonPhrase: streamedResp.reasonPhrase,
            contentLength: responseBody.length,
            isRedirect: streamedResp.isRedirect,
            persistentConnection: streamedResp.persistentConnection,
            request: streamedResp.request,
          );
          if (resp.statusCode >= 200 && resp.statusCode < 300) break;
        }
        // Strategy B: Multipart POST with 'video'
        {
          final req = http.MultipartRequest('POST', url);
          req.files.add(http.MultipartFile.fromBytes('video', bytes, filename: fileName));
          req.fields['file_id'] = fileId.toString();
          req.fields['file_name'] = fileName;
          _log('Video upload attempt B (multipart:video) POST $url fields=${req.fields}');
          final streamedResp = await req.send().timeout(
            const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException('Video upload timeout (B) after 60 seconds'),
          );
          _log('Response (B): status=${streamedResp.statusCode}');
          final responseBody = await streamedResp.stream.bytesToString().timeout(
            const Duration(seconds: 10),
            onTimeout: () => 'Response body read timeout',
          );
          _log('Body (B): ${responseBody.length > 200 ? responseBody.substring(0, 200) + "..." : responseBody}');
          resp = http.StreamedResponse(
            Stream.value(responseBody.codeUnits),
            streamedResp.statusCode,
            headers: streamedResp.headers,
          );
          if (resp.statusCode >= 200 && resp.statusCode < 300) break;
        }
        // Strategy C: Raw POST octet-stream with query params
        {
          final rawUrl = Uri.parse(url.toString()).replace(queryParameters: {
            'file_id': fileId.toString(),
            'file_name': fileName,
          });
          _log('Video upload attempt C (raw POST octet-stream): $rawUrl');
          final r = await http
              .post(rawUrl, headers: {'Content-Type': 'application/octet-stream'}, body: bytes)
              .timeout(const Duration(seconds: 60));
          _log('Raw POST (C) status=${r.statusCode} len=${r.body.length}');
          if (r.statusCode >= 200 && r.statusCode < 300) {
            resp = http.StreamedResponse(Stream.value(r.body.codeUnits), r.statusCode, headers: r.headers);
            usedUrl = rawUrl.toString();
            break;
          }
        }
        // Strategy D: Raw POST video/mp4
        {
          final rawUrl = Uri.parse(url.toString()).replace(queryParameters: {
            'file_id': fileId.toString(),
            'file_name': fileName,
          });
          _log('Video upload attempt D (raw POST video/mp4): $rawUrl');
          final r = await http
              .post(rawUrl, headers: {'Content-Type': 'video/mp4'}, body: bytes)
              .timeout(const Duration(seconds: 60));
          _log('Raw POST (D) status=${r.statusCode} len=${r.body.length}');
          if (r.statusCode >= 200 && r.statusCode < 300) {
            resp = http.StreamedResponse(Stream.value(r.body.codeUnits), r.statusCode, headers: r.headers);
            usedUrl = rawUrl.toString();
            break;
          }
        }
        // Strategy E: Raw PUT octet-stream
        {
          final rawUrl = Uri.parse(url.toString()).replace(queryParameters: {
            'file_id': fileId.toString(),
            'file_name': fileName,
          });
          _log('Video upload attempt E (raw PUT octet-stream): $rawUrl');
          final r = await http
              .put(rawUrl, headers: {'Content-Type': 'application/octet-stream'}, body: bytes)
              .timeout(const Duration(seconds: 60));
          _log('Raw PUT (E) status=${r.statusCode} len=${r.body.length}');
          if (r.statusCode >= 200 && r.statusCode < 300) {
            resp = http.StreamedResponse(Stream.value(r.body.codeUnits), r.statusCode, headers: r.headers);
            usedUrl = rawUrl.toString();
            break;
          }
        }
        // Strategy F: Raw PUT video/mp4
        {
          final rawUrl = Uri.parse(url.toString()).replace(queryParameters: {
            'file_id': fileId.toString(),
            'file_name': fileName,
          });
          _log('Video upload attempt F (raw PUT video/mp4): $rawUrl');
          final r = await http
              .put(rawUrl, headers: {'Content-Type': 'video/mp4'}, body: bytes)
              .timeout(const Duration(seconds: 60));
          _log('Raw PUT (F) status=${r.statusCode} len=${r.body.length}');
          if (r.statusCode >= 200 && r.statusCode < 300) {
            resp = http.StreamedResponse(Stream.value(r.body.codeUnits), r.statusCode, headers: r.headers);
            usedUrl = rawUrl.toString();
            break;
          }
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        _log('Video upload failed for $url: $e');
        // Reset progress on error
        fileProgress[fileId] = 0;
        // Continue to next URL
      }
    }

    if (resp == null) {
      _log('ERROR: Video HTTP upload failed for all endpoints. Trying WS fallback...');
      fileProgress[fileId] = 50; // Show 50% during fallback
      try {
        await _uploadVideoBytesFallback(
          id: id,
          fileId: fileId,
          fileName: fileName,
          bytes: bytes,
        );
        fileProgress[fileId] = 100; // Mark complete after fallback
        // After fallback, return a synthetic response to indicate success
        return http.StreamedResponse(Stream.value('OK'.codeUnits), 200);
      } catch (e) {
        fileProgress[fileId] = 0; // Reset on fallback failure
        rethrow;
      }
    }
    
    // Wait a bit for device to process and save the file
    fileProgress[fileId] = 98; // Almost done, processing on device
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    
    // Refresh file list to see the newly uploaded video
    refreshFileList(id: id);
    
    // Wait for file list response
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    
    fileProgress[fileId] = 100; // Complete
    _log('Video upload complete: file_id=$fileId name=$fileName');
    
    return resp;
  }

  void deleteFiles({required String id, int fileId = 0, int? type, bool? isNetworkMode}) {
    // type: 0 = single device (P), 1 = splicing (S), 2 = network (N)
    // fileId: 0 = delete all files, >0 = delete specific file
    final order = _protocol.nextOrder();
    // Use network mode if specified, otherwise use instance flag
    final useNetworkMode = isNetworkMode ?? this.isNetworkMode;
    final modeType = type ?? (useNetworkMode ? 2 : 0); // 0 for standalone, 2 for network mode
    
    final props = <String, dynamic>{
      'type': modeType,
      'id': id,
      'file_id': fileId,
    };
    
    // Use device ID as source/destination in network mode
    final json = HologramProtocol.envelopeWithProperties(
      cmd: 0x43,
      order: order,
      properties: props,
      source: useNetworkMode ? id : 0, // Use device ID in network mode
      destination: useNetworkMode ? id : 0, // Use device ID in network mode
    );
    _channel?.sink.add(json);
    if (fileId == 0) {
      _log('TX 0x43 DeleteFiles: ALL files (type=$modeType, id=$id)');
    } else {
      _log('TX 0x43 DeleteFiles: file_id=$fileId (type=$modeType, id=$id)');
    }
    _log('TX JSON: $json');
    
    // Automatically refresh file list after deletion
    // Wait a bit for device to process the delete command
    Future.delayed(const Duration(milliseconds: 800), () {
      refreshFileList(id: id, isNetworkMode: useNetworkMode);
      _log('Auto-refreshing file list after delete command');
    });
  }

  void refreshFileList({required String id, bool? isNetworkMode}) {
    // 1) Ask device to update immediately (commonly triggers state push)
    sendSystemControl(id: id, controlType: 1);
    // 2) Also explicitly request file list if supported (cmd 0x1D)
    requestFileList(id: id, isNetworkMode: isNetworkMode);
    _log('Requesting file list refresh (system update + explicit request)');
  }

  // Explicitly request file list (0x1D) - many firmwares require this to respond with 0x1E list
  void requestFileList({required String id, int? type, bool? isNetworkMode}) {
    final order = _protocol.nextOrder();
    // Use network mode if specified, otherwise use instance flag
    final useNetworkMode = isNetworkMode ?? this.isNetworkMode;
    final modeType = type ?? (useNetworkMode ? 2 : 0); // 0 for standalone, 2 for network mode
    
    final props = <String, dynamic>{
      'type': modeType,
      'id': id,
    };
    final json = HologramProtocol.envelopeWithProperties(
      cmd: 0x1D,
      order: order,
      properties: props,
      source: useNetworkMode ? id : 0, // Use device ID in network mode
      destination: useNetworkMode ? id : 0, // Use device ID in network mode
    );
    _channel?.sink.add(json);
    _log('TX 0x1D RequestFileList type=$modeType id=$id');
  }

  // Fallback: Upload video bytes via WebSocket binary packets if HTTP upload fails
  Future<void> _uploadVideoBytesFallback({
    required String id,
    required int fileId,
    required String fileName,
    required Uint8List bytes,
    int chunkSize = 32768,
  }) async {
    if (_channel == null) {
      _log('Error: WebSocket not connected');
      throw StateError('WebSocket not connected');
    }

    final total = bytes.length;
    final packCount = (total / chunkSize).ceil();
    _log('Video WS fallback: file_id=$fileId name=$fileName size=$total bytes, $packCount packets');

    // Ensure device prepared for video
    prepareToTransmit(
      id: id,
      fileId: fileId,
      fileType: 2,
      fileName: fileName,
      type: 0,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));

    for (var i = 0; i < packCount; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize > total) ? total : start + chunkSize;
      final slice = bytes.sublist(start, end);
      // Use cmd 67 (0x43) or 66? Image uses 66; try 67 for video data
      final pkt = HologramProtocol.buildImageDataPacket(
        packCount: packCount,
        packIndex: i + 1,
        data: slice,
        cmd: 67,
        packNumber: 0,
      );
      final binaryData = pkt.toList();
      if (_ws != null) {
        _ws!.add(binaryData);
      } else {
        _channel?.sink.add(binaryData);
      }
      _log('WS sent video packet ${i + 1}/$packCount len=${pkt.length}');
      if (i < packCount - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    refreshFileList(id: id);
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    _log('Video WS fallback complete: file_id=$fileId name=$fileName size=$total bytes ($packCount packets)');
  }

  void resetRotationSettings({required String id}) {
    // Reset all rotation settings to defaults
    // 1. Set speed to default (750)
    sendDeviceControl(
      id: id,
      value: 0x22, // Set Speed
      speedValue: 750,
    );
    
    // 2. Power On Non Rotation (0x26) - default state
    sendDeviceControl(
      id: id,
      value: 0x26, // Power On Non Rotation
    );
    
    _log('Reset rotation settings: speed=750, power on non rotation');
  }

  Future<void> resetSplicingSettings({required String id}) async {
    // Reset splicing settings to defaults for single device mode
    // This fixes issues with dual-display, reflection, or splicing mode
    _log('Resetting splicing settings to defaults...');
    
    // 1. Pause current playback
    sendDeviceControl(
      id: id,
      value: 5, // Pause
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    
    // 2. Get current file to restart with default splicing settings
    final currentFileId = status?.fileId;
    
    if (currentFileId != null && currentFileId > 0) {
      // 3. Find the file in the files list to get its details
      final currentFile = files.firstWhere(
        (f) => f.fileId == currentFileId,
        orElse: () => files.isNotEmpty ? files.first : HologramFileItem(
          fileId: currentFileId,
          fileType: 2, // Assume video
          fileName: '',
          percentage: 100,
        ),
      );
      
      // 4. Prepare to transmit with default splicing settings (all 0s for single device mode)
      // display_mode=0, level=0, position=0 means single device mode, no splicing
      prepareToTransmit(
        id: id,
        fileId: currentFileId,
        fileType: currentFile.fileType,
        fileName: currentFile.fileName,
        type: 0, // 0 = Device (single device P mode)
        displayMode: 0, // Default - single device mode
        level: 0, // Default - display on all sides
        position: 0, // Default - display on all sides
      );
      
      await Future<void>.delayed(const Duration(milliseconds: 200));
      
      // 5. Restart playback with default splicing settings
      sendDeviceControl(
        id: id,
        value: 6, // Play Specific File
        fileId: currentFileId,
      );
      
      _log('Splicing settings reset: display_mode=0, level=0, position=0 (single device mode)');
    } else {
      // No file playing, just log that splicing is reset
      _log('Splicing settings reset: No file currently playing');
    }
  }

  Future<void> factoryReset({required String id}) async {
    // Factory reset all settings to default values
    // This resets everything to factory defaults to fix issues from testing
    _log('Starting factory reset...');
    
    // 1. Pause current playback
    sendDeviceControl(
      id: id,
      value: 5, // Pause
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    
    // 2. Reset brightness to default (15 - maximum)
    sendDeviceControl(
      id: id,
      value: 7, // Brightness Adjustment
      brightness: 15,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    
    // 3. Reset volume to default (15 - maximum)
    sendDeviceControl(
      id: id,
      value: 0xB, // Volume Adjustment
      volume: 15,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    
    // 4. Reset play mode to default (1 - Sequential Loop)
    sendDeviceControl(
      id: id,
      value: 0x21, // Play Mode
      playMode: 1,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    
    // 5. Reset speed to default (750)
    sendDeviceControl(
      id: id,
      value: 0x22, // Set Speed
      speedValue: 750,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    
    // 6. Stop rotation completely (Power On Non Rotation)
    sendDeviceControl(
      id: id,
      value: 0x26, // Power On Non Rotation
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    
    // 7. Reset angle to default (Close Angle)
    sendDeviceControl(
      id: id,
      value: 0x12, // Close Angle
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    
    // 8. Restart rotation (Power On Rotation) to sync with defaults
    sendDeviceControl(
      id: id,
      value: 0x25, // Power On Rotation
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    
    // 9. Stop playback completely to reset display mode
    // This ensures video is not in dual-display or reflection mode
    // First pause, then wait longer to ensure complete stop
    sendDeviceControl(
      id: id,
      value: 5, // Pause
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    
    // 10. Stop rotation again briefly to reset any display mode issues
    sendDeviceControl(
      id: id,
      value: 0x26, // Power On Non Rotation
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    
    // 11. Restart rotation
    sendDeviceControl(
      id: id,
      value: 0x25, // Power On Rotation
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    
    // 12. If there was a current file playing, restart it to ensure proper single-display mode
    // This should fix the double video (top/bottom reflection) issue
    final currentFileId = status?.fileId;
    if (currentFileId != null && currentFileId > 0) {
      // Restart the file to ensure it's in single-display mode (not dual/reflection)
      sendDeviceControl(
        id: id,
        value: 6, // Play Specific File
        fileId: currentFileId,
      );
      _log('Factory reset complete: Restarted video playback to ensure single-display mode (no reflection)');
    } else {
      // Just resume playback
      sendDeviceControl(
        id: id,
        value: 3, // Play
      );
      _log('Factory reset complete: Resumed playback');
    }
    
    _log('Factory reset complete: brightness=15, volume=15, playMode=1, speed=750, rotation=on, angle=closed');
  }

  Future<void> resyncVideoAndRotation({required String id, int? currentFileId, int? currentSpeed}) async {
    // Resync video render rate with rotation rate
    // This fixes the issue where video and rotation get out of sync after speed changes
    // The 180-degree offset happens when frames are not aligned with rotation position
    // Solution: Stop rotation completely, set speed, then restart rotation and video together
    _log('Resyncing video and rotation...');
    
    // 1. Pause current playback completely
    sendDeviceControl(
      id: id,
      value: 5, // Pause
    );
    
    // Wait for pause to fully take effect
    await Future<void>.delayed(const Duration(milliseconds: 300));
    
    // 2. Stop rotation completely (Power On Non Rotation)
    sendDeviceControl(
      id: id,
      value: 0x26, // Power On Non Rotation
    );
    
    // Wait for rotation to stop completely
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    
    // 3. Set speed (use current speed or default 750)
    final speedToSet = currentSpeed ?? 750;
    sendDeviceControl(
      id: id,
      value: 0x22, // Set Speed
      speedValue: speedToSet,
    );
    
    // Wait for speed to be set
    await Future<void>.delayed(const Duration(milliseconds: 500));
    
    // 4. Restart rotation (Power On Rotation)
    sendDeviceControl(
      id: id,
      value: 0x25, // Power On Rotation
    );
    
    // Wait for rotation to start and stabilize
    await Future<void>.delayed(const Duration(milliseconds: 800));
    
    // 5. Restart video playback to sync with rotation
    if (currentFileId != null && currentFileId > 0) {
      // Restart the specific file - this should resync frames with rotation position
      sendDeviceControl(
        id: id,
        value: 6, // Play Specific File
        fileId: currentFileId,
      );
      _log('Resync complete: Restarted rotation and file_id=$currentFileId with speed=$speedToSet');
    } else {
      // Just resume playback
      sendDeviceControl(
        id: id,
        value: 3, // Play
      );
      _log('Resync complete: Restarted rotation and resumed playback with speed=$speedToSet');
    }
  }

  // Peripheral Configuration (0x30)
  void configureBluetooth({
    required String id,
    required int value, // 0-Disconnect, 1-Connect
    String? bluetoothName,
    String? password,
  }) {
    final order = _protocol.nextOrder();
    final props = <String, dynamic>{
      'type': 0,
      'id': id,
      'value': value,
      if (bluetoothName != null) 'bluetooth': bluetoothName,
      if (password != null) 'password': password,
    };
    final json = HologramProtocol.envelopeWithProperties(
      cmd: 0x30,
      order: order,
      properties: props,
      source: '0', // Use string "0" per protocol
      destination: id, // Use device ID as destination per protocol
    );
    _channel?.sink.add(json);
    _log('TX 0x30 Bluetooth value=$value name=$bluetoothName');
  }

  // WiFi Configuration (0x2F)
  void configureWiFi({
    required String id,
    required int mode, // 0-Change, 1-Add, 2-Delete
    required bool isHotspot,
    String? ssid,
    String? password,
  }) {
    final order = _protocol.nextOrder();
    final props = <String, dynamic>{
      'type': 1,
      'id': id,
      'mode': mode,
      'ishot': isHotspot,
      if (ssid != null) 'ssid': ssid,
      if (password != null) 'password': password,
    };
    final json = HologramProtocol.envelopeWithProperties(
      cmd: 0x2F,
      order: order,
      properties: props,
      source: '0', // Use string "0" per protocol
      destination: id, // Use device ID as destination per protocol
    );
    _channel?.sink.add(json);
    _log('TX 0x2F WiFi mode=$mode hotspot=$isHotspot ssid=$ssid');
  }

  // Time Configuration (0x35)
  void configureTime({
    required String id,
    required List<Map<String, dynamic>> timeSchedules,
  }) {
    final order = _protocol.nextOrder();
    final props = <String, dynamic>{
      'type': 0,
      'id': id,
      'time': timeSchedules,
    };
    final json = HologramProtocol.envelopeWithProperties(
      cmd: 0x35,
      order: order,
      properties: props,
      source: '0', // Use string "0" per protocol
      destination: id, // Use device ID as destination per protocol
    );
    _channel?.sink.add(json);
    _log('TX 0x35 Time schedules=${timeSchedules.length}');
  }
}


