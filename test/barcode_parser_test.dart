import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_scanner/services/barcode_parser.dart';

void main() {
  group('VIN validation', () {
    test('accepts the two sample label VINs', () {
      expect(BarcodeParser.isValidVin('MALPC813LTM429642'), isTrue);
      expect(BarcodeParser.isValidVin('MALB141CLTM521054'), isTrue);
    });

    test('rejects wrong length and I/O/Q', () {
      expect(BarcodeParser.isValidVin('MALPC813LTM42964'), isFalse);
      expect(BarcodeParser.isValidVin('MALPC813LTM42964O'), isFalse);
    });
  });

  group('parse', () {
    test('diesel label text (VIN printed in two parts)', () {
      final p = BarcodeParser.parse(
        'SPEC: 1.5UGLS M6\nFHW51MC57 G1B5 R4G YJR\n'
        'VIN: MALPC813LTM 429642\nDIESEL',
      );
      expect(p.vin, 'MALPC813LTM429642');
      expect(p.specCode, '1.5UGLS M6 FHW51MC57 G1B5 R4G YJR');
      expect(p.fuelType, 'Diesel');
      expect(p.isComplete, isTrue);
    });

    test('CNG bi-fuel label resolves to CNG', () {
      final p = BarcodeParser.parse(
        'INDIA 1CNG SPEC:1.2 L M5 HQS4K3615 S166 SAW T9Y '
        'VIN: MALB141CLTM 521054 PETROL',
      );
      expect(p.vin, 'MALB141CLTM521054');
      expect(p.fuelType, 'CNG');
      expect(p.specCode, '1.2 L M5 HQS4K3615 S166 SAW T9Y');
    });

    test('bare VIN only', () {
      final p = BarcodeParser.parse('MALB141CLTM521054');
      expect(p.vin, 'MALB141CLTM521054');
      expect(p.fuelType, isEmpty);
      expect(p.isComplete, isFalse);
    });

    test('VIN embedded in delimited string', () {
      final p = BarcodeParser.parse('3282625070979|MALPC813LTM429642|PETROL');
      expect(p.vin, 'MALPC813LTM429642');
      expect(p.fuelType, 'Petrol');
    });

    test('spec fallback pattern without SPEC label', () {
      final p = BarcodeParser.parse('1.5UGLS M6 MALPC813LTM429642 DIESEL');
      expect(p.specCode, '1.5UGLS M6');
    });

    test('garbage returns empty fields, keeps raw', () {
      final p = BarcodeParser.parse('  hello world  ');
      expect(p.rawData, 'hello world');
      expect(p.vin, isEmpty);
      expect(p.hasValidVin, isFalse);
    });
  });
}
