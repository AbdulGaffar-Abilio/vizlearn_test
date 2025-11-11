import 'dart:convert';
import 'dart:typed_data';

class HologramProtocol {
  HologramProtocol({int initialOrder = 1}) : _order = initialOrder;

  int _order;

  int nextOrder() {
    _order++;
    if (_order > 255) _order = 1;
    return _order;
  }

  static Map<String, dynamic> baseEnvelope({
    required int cmd,
    required int order,
    int source = 0,
    int destination = 0,
    int versionCode = 1,
    int packOrder = 1,
    int packCount = 1,
  }) {
    return {
      'cmd': cmd,
      'source': source,
      'destination': destination,
      'order': order,
      'version_code': versionCode,
      'pack_order': packOrder,
      'pack_count': packCount,
    };
  }

  static String envelopeWithProperties({
    required int cmd,
    required int order,
    required Map<String, dynamic> properties,
    Object source = 0,
    Object destination = 0,
    int versionCode = 1,
  }) {
    // Support both int and string for source/destination
    // Convert to int for baseEnvelope (use 0 as default if string)
    final sourceInt = source is int ? source : (source is String ? 0 : 0);
    final destInt = destination is int ? destination : (destination is String ? 0 : 0);
    
    final env = baseEnvelope(
      cmd: cmd,
      order: order,
      source: sourceInt,
      destination: destInt,
      versionCode: versionCode,
    );
    
    // Override with actual values (strings if provided)
    final result = <String, dynamic>{
      ...env,
      'properties': properties,
    };
    
    // Use string values if provided, otherwise keep the int values
    if (source is String) {
      result['source'] = source;
    }
    if (destination is String) {
      result['destination'] = destination;
    }
    
    return jsonEncode(result);
  }

  static Uint8List buildImageDataPacket({
    required int packCount,
    required int packIndex,
    required Uint8List data,
    int cmd = 66,
    int packNumber = 0,
  }) {
    // Packet format:
    // 0xFA 0xF0 cmd packNumber packCount packIndex length Data 0xFE
    final length = data.length;
    final header = Uint8List(6);
    header[0] = 0xFA;
    header[1] = 0xF0;
    header[2] = cmd;
    header[3] = packNumber;
    header[4] = packCount & 0xFF;
    header[5] = packIndex & 0xFF;

    final lengthBytes = Uint8List(2);
    final lbd = lengthBytes.buffer.asByteData();
    lbd.setUint16(0, length, Endian.big);

    final trailer = Uint8List.fromList([0xFE]);

    return Uint8List.fromList([
      ...header,
      ...lengthBytes,
      ...data,
      ...trailer,
    ]);
  }
}


