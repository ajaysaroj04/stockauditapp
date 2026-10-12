/// Result of parsing a barcode string or the OCR text of a label.
class ParsedBarcode {
  final String rawData;
  final String vin;
  final String specCode;
  final String fuelType;

  /// 6-digit serial (last 6 characters of the VIN) when known.
  final String serial;

  /// Optional message for the user (e.g. a mismatch between barcode and label).
  final String? note;

  const ParsedBarcode({
    required this.rawData,
    required this.vin,
    required this.specCode,
    required this.fuelType,
    this.serial = '',
    this.note,
  });

  bool get hasValidVin => BarcodeParser.isValidVin(vin);
  bool get isComplete => hasValidVin && specCode.isNotEmpty && fuelType.isNotEmpty;
}

class _VinPrefix {
  final String raw; // as read
  final String fixed; // OCR look-alikes corrected (O->0, I->1, Q->0)
  const _VinPrefix(this.raw, this.fixed);
}

/// Turns scanned barcode text and OCR'd label text into structured fields.
///
/// What the real Hyundai window labels contain (verified by decoding photos):
///  * The barcodes hold only a 3-letter code and the 6-digit serial, e.g.
///    `FHY 429642`. That serial is the last 6 characters of the VIN.
///  * The full VIN (`MALPC813LTM` + `429642`), the SPEC lines and the fuel are
///    printed as text only.
/// So: [parse] extracts the serial from the barcode, and [parseLabel] reads the
/// printed text (via OCR) and joins the 11-character VIN prefix with the serial.
class BarcodeParser {
  BarcodeParser._();

  /// Valid VINs never contain the letters I, O or Q.
  static final RegExp _vinRe = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');

  static bool isValidVin(String vin) => _vinRe.hasMatch(vin.toUpperCase());

  // ---------------------------------------------------------------- barcode

  static ParsedBarcode parse(String raw) {
    final text = raw.trim();
    final upper = text.toUpperCase();
    return ParsedBarcode(
      rawData: text,
      vin: _extractVin(upper),
      specCode: _extractSpec(upper),
      fuelType: _extractFuel(upper),
      serial: extractSerial(text) ?? '',
    );
  }

  /// `FHY 429642` -> `429642`; `33429642` -> `429642`; null if none.
  static String? extractSerial(String raw) {
    final u = raw.toUpperCase();
    final coded = RegExp(r'\b[A-Z]{3}\s+(\d{6})\b').firstMatch(u);
    if (coded != null) return coded.group(1);
    final tail = RegExp(r'(\d{6})\s*$').firstMatch(u.trim());
    return tail?.group(1);
  }

  // ------------------------------------------------------------- label text

  /// Parses OCR text of the label. [serial] is the barcode serial, if known;
  /// it is trusted over the OCR'd digits.
  static ParsedBarcode parseLabel(String ocrText, {String? serial}) {
    final text = ocrText.trim();
    final upper = text.toUpperCase();
    final known = (serial ?? '').trim();

    var working = upper;
    var vin = '';
    var usedSerial = known;
    String? note;

    final prefix = _findVinPrefix(upper);
    if (prefix != null) {
      working = working.replaceFirst(prefix.raw, ' ');
      final ocrSerial = _findSerial(working);
      if (known.isNotEmpty && ocrSerial != null && ocrSerial != known) {
        note = 'Serial in the label text ($ocrSerial) differs from the barcode '
            'serial ($known). Please verify the VIN.';
      }
      usedSerial = known.isNotEmpty ? known : (ocrSerial ?? '');
      if (usedSerial.isNotEmpty) {
        final candidate = prefix.fixed + usedSerial;
        if (isValidVin(candidate)) vin = candidate;
      }
      if (ocrSerial != null) working = working.replaceFirst(ocrSerial, ' ');
    }
    if (vin.isEmpty) vin = _extractVin(upper, strict: true);

    return ParsedBarcode(
      rawData: text,
      vin: vin,
      specCode: _extractSpec(working),
      fuelType: _extractFuel(upper),
      serial: usedSerial,
      note: note,
    );
  }

  /// First 11-character token that looks like a VIN prefix (two letters first,
  /// at least one digit). OCR confusions O/I/Q are corrected since a VIN can
  /// never contain those letters.
  static _VinPrefix? _findVinPrefix(String upper) {
    final tokens = upper.split(RegExp(r'[^A-Z0-9]+')).where((t) => t.isNotEmpty);
    for (final t in tokens) {
      if (t.length != 11) continue;
      if (!RegExp(r'^[A-Z]{2}').hasMatch(t)) continue;
      if (!RegExp(r'[0-9]').hasMatch(t)) continue;
      final fixed = t.replaceAll('O', '0').replaceAll('I', '1').replaceAll('Q', '0');
      if (RegExp(r'^[A-HJ-NPR-Z0-9]{11}$').hasMatch(fixed)) {
        return _VinPrefix(t, fixed);
      }
    }
    return null;
  }

  /// First standalone 6-digit token.
  static String? _findSerial(String upper) {
    for (final t in upper.split(RegExp(r'[^A-Z0-9]+'))) {
      if (RegExp(r'^\d{6}$').hasMatch(t)) return t;
    }
    return null;
  }

  // ----------------------------------------------------------------- shared

  static bool _looksLikeVin(String s) =>
      isValidVin(s) &&
      RegExp(r'[0-9]').hasMatch(s) &&
      RegExp(r'[A-Z]').hasMatch(s);

  /// [strict] (used for OCR text) only accepts a labelled VIN or a single
  /// 17-character token, to avoid false positives from long spec codes.
  static String _extractVin(String upper, {bool strict = false}) {
    // 1. Explicit "VIN: xxxxx" label (VIN may be split by a space).
    final labelled = RegExp(r'VIN\s*[:=\-]?\s*([A-Z0-9 ]{17,26})').firstMatch(upper);
    if (labelled != null) {
      final collapsed = labelled.group(1)!.replaceAll(RegExp(r'\s+'), '');
      if (collapsed.length >= 17) {
        final candidate = collapsed.substring(0, 17);
        if (_looksLikeVin(candidate)) return candidate;
      }
    }

    // Several barcodes / lines are separated by '|' or newlines; never join
    // tokens across them.
    final segments = upper.split(RegExp(r'[|\n\r]+'));

    // 2. Join up to three adjacent tokens (same segment) into exactly 17 chars.
    for (final seg in segments) {
      final tokens =
          seg.split(RegExp(r'[^A-Z0-9]+')).where((t) => t.isNotEmpty).toList();
      for (var i = 0; i < tokens.length; i++) {
        var joined = '';
        final maxSpan = strict ? 1 : 3;
        for (var span = 0; span < maxSpan && i + span < tokens.length; span++) {
          joined += tokens[i + span];
          if (joined.length == 17 && _looksLikeVin(joined)) return joined;
          if (joined.length > 17) break;
        }
      }
    }
    if (strict) return '';

    // 3. Last resort: slide a 17-char window across a segment's alphanumerics.
    for (final seg in segments) {
      final flat = seg.replaceAll(RegExp(r'[^A-Z0-9]'), '');
      for (var i = 0; i + 17 <= flat.length; i++) {
        final w = flat.substring(i, i + 17);
        if (_looksLikeVin(w) &&
            RegExp(r'^[A-Z]{2}').hasMatch(w) &&
            RegExp(r'[0-9]').allMatches(w).length >= 4) {
          return w;
        }
      }
    }
    return '';
  }

  static String _extractSpec(String upper) {
    final labelled = RegExp(
      r'SPEC\s*[:=\-]?\s*([A-Z0-9.\-\s]+?)(?=VIN|FUEL|PETROL|DIESEL|CNG|HYUNDAI|PLEASE|MMH|$)',
    ).firstMatch(upper);
    if (labelled != null) {
      final v = labelled.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (v.isNotEmpty) return v;
    }
    final pattern = RegExp(r'\b\d\.\d\s*[A-Z]*\s*[A-Z]\d\b').firstMatch(upper);
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
