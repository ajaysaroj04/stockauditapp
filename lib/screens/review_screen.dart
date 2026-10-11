import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/vehicle_scan.dart';
import '../services/barcode_parser.dart';
import '../services/database_service.dart';

const List<String> kFuelTypes = ['Petrol', 'Diesel', 'CNG', 'EV', 'Hybrid', 'LPG', 'Other'];

/// Editable form to verify / correct a scan before saving (or to edit a saved one).
/// Pops with `true` when saved, `false`/null when discarded.
class ReviewScreen extends StatefulWidget {
  final VehicleScan scan;
  final bool isEdit;
  final String? warning;

  const ReviewScreen({
    super.key,
    required this.scan,
    this.isEdit = false,
    this.warning,
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
              TextFormField(
                controller: _vin,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                maxLength: 17,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'VIN (17 characters)',
                  prefixIcon: Icon(Icons.pin),
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
