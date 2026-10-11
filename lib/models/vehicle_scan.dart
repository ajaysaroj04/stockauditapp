/// One saved vehicle scan.
class VehicleScan {
  final int? id;
  final String rawData;
  final String vin;
  final String specCode;
  final String fuelType;
  final DateTime scannedAt;

  const VehicleScan({
    this.id,
    required this.rawData,
    required this.vin,
    required this.specCode,
    required this.fuelType,
    required this.scannedAt,
  });

  VehicleScan copyWith({
    int? id,
    String? rawData,
    String? vin,
    String? specCode,
    String? fuelType,
    DateTime? scannedAt,
  }) {
    return VehicleScan(
      id: id ?? this.id,
      rawData: rawData ?? this.rawData,
      vin: vin ?? this.vin,
      specCode: specCode ?? this.specCode,
      fuelType: fuelType ?? this.fuelType,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'raw_data': rawData,
        'vin': vin,
        'spec_code': specCode,
        'fuel_type': fuelType,
        'scanned_at': scannedAt.toIso8601String(),
      };

  factory VehicleScan.fromMap(Map<String, Object?> m) => VehicleScan(
        id: m['id'] as int?,
        rawData: m['raw_data'] as String,
        vin: m['vin'] as String,
        specCode: m['spec_code'] as String,
        fuelType: m['fuel_type'] as String,
        scannedAt: DateTime.parse(m['scanned_at'] as String),
      );
}
