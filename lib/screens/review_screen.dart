import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/vehicle_scan.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;

import '../services/barcode_parser.dart';
import '../services/database_service.dart';
import '../services/label_ocr_service.dart';

const List<String> kFuelTypes = ['Petrol', 'Diesel', 'CNG', 'EV', 'Hybrid', 'LPG', 'Other'];

/// Editable form to verify / correct a scan before saving (or to edit a saved one).
/// Pops with `true` when saved, `false`/null when discarded.
class ReviewScreen extends StatefulWidget {
  final VehicleScan scan;
  final bool isEdit;
  final String? warning;

  /// 6-digit serial read from the barcode (= last 6 characters of the VIN).
  final String? barcodeSerial;

  const ReviewScreen({
    super.key,
    required this.scan,
    this.isEdit = false,
    this.warning,
    this.barcodeSerial,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _raw =
      TextEditingController(text: widget.scan.rawData);
  late final TextEditingController _vin =
      TextEditingController(text: widget.scan.vin);
  late final TextEditingController _spec =
      TextEditingController(text: widget.scan.specCode);
  late String? _fuel = widget.scan.fuelType.isEmpty ? null : widget.scan.fuelType;
  bool _saving = false;
  bool _ocrBusy = false;
  String? _note;

  List<String> get _fuelOptions => [
        ...kFuelTypes,
        if (_fuel != null && !kFuelTypes.contains(_fuel)) _fuel!,
      ];

  @override
  void dispose() {
    _raw.dispose();
    _vin.dispose();
    _spec.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String message, String yes) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);

    final db = DatabaseService.instance;
    final vin = _vin.text.trim().toUpperCase();
    try {
      if (await db.vinExists(vin, excludeId: widget.scan.id)) {
        final ok = await _confirm(
          'Duplicate VIN',
          'A vehicle with VIN $vin is already saved. Save this as another entry?',
          'Save anyway',
        );
        if (!ok) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
      final updated = widget.scan.copyWith(
        rawData: _raw.text.trim(),
        vin: vin,
        specCode: _spec.text.trim().toUpperCase(),
        fuelType: _fuel ?? '',
      );
      if (widget.isEdit && updated.id != null) {
        await db.update(updated);
      } else {
        await db.insert(updated);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  /// Photograph / pick the label, OCR it, and fill VIN, spec and fuel type.
  Future<void> _readLabel(ImageSource source) async {
    if (_ocrBusy) return;
    setState(() => _ocrBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final text = await LabelOcrService.readLabel(source);
      if (text == null) return; // cancelled
      if (text.trim().isEmpty) {
        messenger.showSnackBar(const SnackBar(
          content: Text('No text found. Retake the photo closer, in good light, without glare.'),
        ));
        return;
      }
      final vinNow = _vin.text.trim();
      final serial = widget.barcodeSerial ??
          (vinNow.length == 17 ? vinNow.substring(11) : null);
      final p = BarcodeParser.parseLabel(text, serial: serial);
      if (!mounted) return;
      setState(() {
        if (p.vin.isNotEmpty) _vin.text = p.vin;
        if (p.specCode.isNotEmpty) _spec.text = p.specCode;
        if (p.fuelType.isNotEmpty) _fuel = p.fuelType;
        _note = p.note;
        // Keep the barcode part of the raw data and append the OCR text so
        // misreads can be diagnosed later.
        final barcodePart = _raw.text.split('\nOCR:').first.trim();
        final ocrLine = text.trim().replaceAll(RegExp(r'\s*\n\s*'), ' | ');
        _raw.text = '${barcodePart.isEmpty || barcodePart.startsWith('OCR:') ? '' : '$barcodePart\n'}OCR: $ocrLine';
      });
      final missing = <String>[
        if (p.vin.isEmpty) 'VIN',
        if (p.specCode.isEmpty) 'spec',
        if (p.fuelType.isEmpty) 'fuel type',
      ];
      messenger.showSnackBar(SnackBar(
        content: Text(missing.isEmpty
            ? 'Label read. Please check the values before saving.'
            : 'Could not read: ${missing.join(', ')}. Type them in or retake the photo.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not read the label: $e')));
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.scan.id;
    if (id == null) return;
    final ok = await _confirm('Delete entry?', 'This cannot be undone.', 'Delete');
    if (!ok) return;
    await DatabaseService.instance.delete(id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final ts = DateFormat('dd MMM yyyy, hh:mm:ss a').format(widget.scan.scannedAt);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit entry' : 'Review scan'),
        actions: [
          if (widget.isEdit)
            IconButton(
              tooltip: 'Delete',
              iconSize: 28,
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.warning != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4CE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFB26A00)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(widget.warning!, style: const TextStyle(fontSize: 15)),
                      ),
                    ],
                  ),
                ),
              if (_note != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE3E3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xFFC92A2A)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_note!, style: const TextStyle(fontSize: 15))),
                    ],
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Fill from the printed label',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      const Text(
                        'The barcode only holds the serial number. Photograph the '
                        'label (hold close, avoid glare) to read VIN, spec and fuel type.',
                        style: TextStyle(fontSize: 15, color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _ocrBusy ? null : () => _readLabel(ImageSource.camera),
                        icon: _ocrBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 3, color: Colors.white),
                              )
                            : const Icon(Icons.document_scanner),
                        label: Text(_ocrBusy ? 'READING...' : 'PHOTOGRAPH LABEL'),
                      ),
                      TextButton(
                        onPressed: _ocrBusy ? null : () => _readLabel(ImageSource.gallery),
                        child: const Text('Choose an existing photo',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vin,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                maxLength: 17,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                decoration: InputDecoration(
                  labelText: 'VIN (17 characters)',
                  prefixIcon: const Icon(Icons.pin),
                  helperText: widget.barcodeSerial == null
                      ? null
                      : 'Barcode serial ${widget.barcodeSerial} = last 6 characters',
                ),
                validator: (v) {
                  final s = (v ?? '').trim().toUpperCase();
                  if (s.isEmpty) return 'VIN is required';
                  if (s.length != 17) return 'VIN must be exactly 17 characters (${s.length} entered)';
                  if (!BarcodeParser.isValidVin(s)) {
                    return 'VIN cannot contain the letters I, O or Q';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _spec,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                style: const TextStyle(fontSize: 18),
                decoration: const InputDecoration(
                  labelText: 'Spec / Model code',
                  prefixIcon: Icon(Icons.tune),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _fuel,
                isExpanded: true,
                style: const TextStyle(fontSize: 18, color: Colors.black87),
                decoration: const InputDecoration(
                  labelText: 'Fuel type',
                  prefixIcon: Icon(Icons.local_gas_station),
                ),
                items: [
                  for (final f in _fuelOptions)
                    DropdownMenuItem(value: f, child: Text(f)),
                ],
                onChanged: (v) => setState(() => _fuel = v),
                validator: (v) => (v == null || v.isEmpty) ? 'Select a fuel type' : null,
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Scanned at',
                  prefixIcon: Icon(Icons.schedule),
                ),
                child: Text(ts, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _raw,
                minLines: 2,
                maxLines: 6,
                autocorrect: false,
                style: const TextStyle(fontSize: 15, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'Raw barcode data',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(widget.isEdit ? 'SAVE CHANGES' : 'SAVE ENTRY'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: Text(widget.isEdit ? 'Cancel' : 'Discard & rescan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
