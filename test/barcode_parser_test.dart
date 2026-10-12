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

  group('barcodes seen on real Hyundai labels (code + serial only)', () {
    test('Code 39 value gives the serial and no VIN', () {
      final p = BarcodeParser.parse('FHY 429642');
      expect(p.serial, '429642');
      expect(p.vin, isEmpty);
    });

    test('two barcodes joined with | never create a false VIN', () {
      final p = BarcodeParser.parse('FHY 429642 | 33429642');
      expect(p.serial, '429642');
      expect(p.vin, isEmpty);
    });

    test('ITF value 33429642 gives the serial', () {
      expect(BarcodeParser.extractSerial('33429642'), '429642');
    });

    test('double space between code and serial', () {
      expect(BarcodeParser.extractSerial('SVA  429815'), '429815');
    });
  });

  group('parseLabel (OCR text of the printed label)', () {
    // As returned by an OCR engine: spaces lost, VIN prefix before "VIN:".
    const dieselOcr = 'PIO\n3282625070979\nINDIA\nSPEC:\n1.5UGLSM6\n'
        'FHW51MC57G1B5R4GYJR\nMALPC813LTM\nVIN:\n429642\nDIESEL\n'
        'D2607B418A10A\n09\nHYUNDAI MOTORINDIA\nPLEASE REMOVEIT BEFOREDELIVERY';
    const cngOcr = 'OK\n6292611091200\nINDIA\n1CNG\nSPEC:1.2 L M5\n'
        'HQS4K3615S166SAWT9Y\nVIN:\nMALB141CLTM\n521054\nPETROL\n'
        'D2609K887A10A\nHYUNDAIMOTORINDIA\nPLEASE REMOVE IT BEFORE DELIVERY';

    test('diesel label with barcode serial', () {
      final p = BarcodeParser.parseLabel(dieselOcr, serial: '429642');
      expect(p.vin, 'MALPC813LTM429642');
      expect(p.specCode, '1.5UGLSM6 FHW51MC57G1B5R4GYJR');
      expect(p.fuelType, 'Diesel');
      expect(p.note, isNull);
    });

    test('diesel label without barcode serial uses the printed one', () {
      final p = BarcodeParser.parseLabel(dieselOcr);
      expect(p.vin, 'MALPC813LTM429642');
    });

    test('CNG label (PETROL also printed) resolves to CNG', () {
      final p = BarcodeParser.parseLabel(cngOcr, serial: '521054');
      expect(p.vin, 'MALB141CLTM521054');
      expect(p.specCode, '1.2 L M5 HQS4K3615S166SAWT9Y');
      expect(p.fuelType, 'CNG');
    });

    test('line-based OCR with spaces', () {
      final p = BarcodeParser.parseLabel(
        'PIO 3282625070979\nINDIA\nSPEC: 1.5UGLS M6\nFHW51MC57 G1B5 R4G YJR\n'
        'VIN: MALPC813LTM\nDIESEL 429642\nD2607B418 A10A\nHYUNDAI MOTOR INDIA',
        serial: '429642',
      );
      expect(p.vin, 'MALPC813LTM429642');
      expect(p.specCode, '1.5UGLS M6 FHW51MC57 G1B5 R4G YJR');
    });

    test('OCR confusion I/O in the VIN prefix is corrected', () {
      final p = BarcodeParser.parseLabel(
        dieselOcr.replaceFirst('MALPC813LTM', 'MALPC8I3LTM'),
        serial: '429642',
      );
      expect(p.vin, 'MALPC813LTM429642');
    });

    test('serial mismatch between barcode and label is flagged', () {
      final p = BarcodeParser.parseLabel(dieselOcr, serial: '999999');
      expect(p.vin, 'MALPC813LTM999999'); // barcode serial is trusted
      expect(p.note, isNotNull);
    });

    test('VIN printed in one piece', () {
      final p = BarcodeParser.parseLabel(
        'SPEC: 1.5UGLS M6 VIN: MALPC813LTM429642 DIESEL',
      );
      expect(p.vin, 'MALPC813LTM429642');
    });
  });
}
