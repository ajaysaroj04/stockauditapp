import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vehicle_scan.dart';

class ExportService {
  ExportService._();

  /// Writes [scans] to a CSV file and opens the system share sheet so the
  /// user can save it to Drive / Files, email it or send it on WhatsApp.
  /// Returns the file path. Throws if there is nothing to export.
  static Future<String> exportCsv(List<VehicleScan> scans) async {
    if (scans.isEmpty) {
      throw StateError('There are no scans to export.');
    }
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final rows = <List<dynamic>>[
      ['ID', 'VIN', 'Spec Code', 'Fuel Type', 'Scanned At', 'Raw Barcode Data'],
      for (final s in scans)
        [s.id, s.vin, s.specCode, s.fuelType, fmt.format(s.scannedAt), s.rawData],
    ];
    final csv = const ListToCsvConverter().convert(rows);

    final dir = await getTemporaryDirectory();
    final name =
        'vehicle_scans_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${dir.path}/$name');
    // BOM so Excel opens the file as UTF-8.
    await file.writeAsString('﻿$csv', flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Vehicle scans export',
    );
    return file.path;
  }
}
