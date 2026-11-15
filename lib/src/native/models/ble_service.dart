import 'package:flutter/foundation.dart';
import 'package:ble_shield/src/native/native.dart';

class BleService {
  String uuid;
  List<BleCharacteristic> characteristics;

  BleService(String uuid, this.characteristics)
      : uuid = BleUuidParser.string(uuid);

  @override
  String toString() {
    return 'BleService{uuid: $uuid, characteristics: $characteristics}';
  }
}

class BleCharacteristic {
  String uuid;
  List<CharacteristicProperty> properties;
  List<BleDescriptor> descriptors;
  BleCharOperationMetadata? metaData;

  BleCharacteristic(String uuid, this.properties, this.descriptors)
      : uuid = BleUuidParser.string(uuid);

  BleCharacteristic.withMetaData({
    required String deviceId,
    required String serviceId,
    required String uuid,
    required this.properties,
    required this.descriptors,
  }) : uuid = BleUuidParser.string(uuid) {
    metaData = BleCharOperationMetadata(
      deviceId: deviceId,
      serviceId: BleUuidParser.string(serviceId),
      characteristicId: uuid,
    );
    descriptors = descriptors.map((e) => e.copyWithMetadata(metaData)).toList();
  }

  factory BleCharacteristic.fromJson(Map<String, dynamic> json) {
    final propertiesJson = (json['properties'] as List<dynamic>? ?? <dynamic>[])
        .whereType<String>()
        .map(_propertyFromName)
        .whereType<CharacteristicProperty>()
        .toList();
    final descriptorsJson =
        (json['descriptors'] as List<dynamic>? ?? <dynamic>[])
            .whereType<Map>()
            .map((e) => BleDescriptor.fromJson(Map<String, dynamic>.from(e)))
            .toList();
    return BleCharacteristic(
      json['uuid'] as String,
      propertiesJson,
      descriptorsJson,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uuid': uuid,
        'properties': properties.map((e) => e.name).toList(),
        'descriptors': descriptors.map((e) => e.toJson()).toList(),
      };

  @override
  String toString() {
    return 'BleCharacteristic{uuid: $uuid, properties: $properties}';
  }

  @override
  bool operator ==(Object other) {
    if (other is! BleCharacteristic) return false;
    if (other.uuid != uuid) return false;
    if (!listEquals(other.properties, properties)) return false;
    if (other.metaData?.deviceId != metaData?.deviceId) return false;
    if (other.metaData?.serviceId != metaData?.serviceId) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(uuid, Object.hashAll(properties), metaData);
}

class BleDescriptor {
  String uuid;
  BleDescriptor(String uuid) : uuid = BleUuidParser.string(uuid);
  BleCharOperationMetadata? metaData;

  BleDescriptor copyWithMetadata(BleCharOperationMetadata? value) {
    metaData = value;
    return this;
  }

  factory BleDescriptor.fromJson(Map<String, dynamic> json) {
    return BleDescriptor(json['uuid'] as String);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'uuid': uuid};

  @override
  String toString() => 'BleDescriptor{uuid: $uuid}';

  @override
  bool operator ==(Object other) {
    if (other is! BleDescriptor) return false;
    return other.uuid == uuid;
  }

  @override
  int get hashCode => uuid.hashCode;
}

CharacteristicProperty? _propertyFromName(String propertyName) {
  try {
    return CharacteristicProperty.values.byName(propertyName);
  } catch (_) {
    return null;
  }
}

/// Metadata attached with [BleCharacteristic] or [BleDescriptor] to use with
/// BLE operations
class BleCharOperationMetadata {
  String deviceId;
  String serviceId;
  String characteristicId;

  BleCharOperationMetadata({
    required this.deviceId,
    required this.serviceId,
    required this.characteristicId,
  });
}
