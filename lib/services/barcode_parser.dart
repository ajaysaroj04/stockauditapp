/// Result of parsing a raw barcode string.
class ParsedBarcode {
  final String rawData;
  final String vin;
  final String specCode;
  final String fuelType;

  const ParsedBarcode({
    required this.rawData,
    required this.vin,
    required this.specCode,
    required this.fuelType,
  });

  bool get hasValidVin => BarcodeParser.isValidVin(vin);
  bool get isComplete => hasValidVin && specCode.isNotEmpty && fuelType.isNotEmpty;
}

/// Turns the raw string inside a vehicle barcode into structured fields.
///
/// Dealer/OEM labels differ, so this is deliberately tolerant:
///  * VIN: a labelled "VIN: ..." value, or any 17-character VIN-shaped run
///    (also when the VIN is printed in two parts, e.g. `MALPC813LTM 429642`).
///  * Spec: the text after "SPEC", else a pattern like `1.5UGLS M6` / `1.2 L M5`.
///  * Fuel: PETROL / DIESEL / CNG / EV / HYBRID / LPG keyword anywhere.
/// Anything not found is returned empty so the user can fill it in on the
/// review screen.
class BarcodeParser {
  BarcodeParser._();

  /// Valid VINs never contain the letters I, O or Q.
  static final RegExp _vinRe = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');

  static bool isValidVin(String vin) => _vinRe.hasMatch(vin.toUpperCase());

  static ParsedBarcode parse(String raw) {
    final text = raw.trim();
    final upper = text.toUpperCase();
    return ParsedBarcode(
      rawData: text,
      vin: _extractVin(upper),
      specCode: _extractSpec(upper),
      fuelType: _extractFuel(upper),
    );
  }

  static bool _looksLikeVin(String s) =>
      isValidVin(s) &&
      RegExp(r'[0-9]').hasMatch(s) &&
      RegExp(r'[A-Z]').hasMatch(s);

  static String _extractVin(String upper) {
    // 1. Explicit "VIN: xxxxx" label (VIN may be split by a space).
    final labelled = RegExp(r'VIN\s*[:=\-]?\s*([A-Z0-9 ]{17,26})').firstMatch(upper);
    if (labelled != null) {
      final collapsed = labelled.group(1)!.replaceAll(RegExp(r'\s+'), '');
      if (collapsed.length >= 17) {
        final candidate = collapsed.substring(0, 17);
        if (_looksLikeVin(candidate)) return candidate;
      }
    }

    // 2. Join up to three adjacent tokens until they make exactly 17 chars.
    final tokens =
        upper.split(RegExp(r'[^A-Z0-9]+')).where((t) => t.isNotEmpty).toList();
    for (var i = 0; i < tokens.length; i++) {
      var joined = '';
      for (var span = 0; span < 3 && i + span < tokens.length; span++) {
        joined += tokens[i + span];
        if (joined.length == 17 && _looksLikeVin(joined)) return joined;
        if (joined.length > 17) break;
      }
    }

    // 3. Last resort: slide a 17-char window across the alphanumerics and
    //    accept one that starts with two letters (WMI) and has several digits.
    final flat = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    for (var i = 0; i + 17 <= flat.length; i++) {
      final w = flat.substring(i, i + 17);
      if (_looksLikeVin(w) &&
          RegExp(r'^[A-Z]{2}').hasMatch(w) &&
          RegExp(r'[0-9]').allMatches(w).length >= 4) {
        return w;
      }
    }
    return '';
  }

  static String _extractSpec(String upper) {
    final labelled = RegExp(
      r'SPEC\s*[:=\-]?\s*([A-Z0-9.\-\s]+?)(?=VIN|FUEL|PETROL|DIESEL|CNG|$)',
    ).firstMatch(upper);
    if (labelled != null) {
      final v = labelled.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (v.isNotEmpty) return v;
    }
    final pattern =
        RegExp(r'\b\d\.\d\s*[A-Z]*\s*[A-Z]\d\b').firstMatch(upper);
    return pattern?.group(0)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  }

  static String _extractFuel(String upper) {
    // CNG first: bi-fuel labels print both "PETROL" and "CNG".
    if (upper.contains('CNG')) return 'CNG';
    if (upper.contains('DIESEL')) return 'Diesel';
    if (upper.contains('PETROL')) return 'Petrol';
    if (upper.contains('ELECTRIC') || RegExp(r'\bEV\b').hasMatch(upper)) {
      return 'EV';
    }
    if (upper.contains('HYBRID') || RegExp(r'\bHEV\b').hasMatch(upper)) {
      return 'Hybrid';
    }
    if (RegExp(r'\bLPG\b').hasMatch(upper)) return 'LPG';
    return '';
  }
}
