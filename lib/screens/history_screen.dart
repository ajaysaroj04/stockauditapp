import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vehicle_scan.dart';
import '../services/database_service.dart';
import '../services/export_service.dart';
import '../theme.dart';
import 'review_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _fuel;
  late Future<List<VehicleScan>> _future = _load();
  List<VehicleScan> _current = const [];

  Future<List<VehicleScan>> _load() async {
    final rows = await DatabaseService.instance.all(query: _search.text, fuel: _fuel);
    _current = rows;
    return rows;
  }

  void _reload() => setState(() => _future = _load());

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _reload);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Export what is currently filtered; fall back to everything if nothing loaded.
      final data = _current.isNotEmpty ? _current : await DatabaseService.instance.all();
      await ExportService.exportCsv(data);
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _edit(VehicleScan s) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReviewScreen(scan: s, isEdit: true)),
    );
    if (mounted) _reload();
  }

  Future<bool> _confirmDelete(VehicleScan s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('Remove ${s.vin.isEmpty ? 'this entry' : s.vin}? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && s.id != null) {
      await DatabaseService.instance.delete(s.id!);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan history'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            iconSize: 28,
            icon: const Icon(Icons.ios_share),
            onPressed: _export,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Search VIN, spec or raw data',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _reload();
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                _chip('All', null),
                for (final f in kFuelTypes.where((f) => f != 'Other')) _chip(f, f),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<VehicleScan>>(
              future: _future,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Could not load history.\n${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data!;
                if (rows.isEmpty) {
                  return const Center(
                    child: Text('No matching scans.',
                        style: TextStyle(fontSize: 16, color: Colors.black54)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: rows.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Text('${rows.length} entr${rows.length == 1 ? 'y' : 'ies'}',
                          style: const TextStyle(fontSize: 14, color: Colors.black54));
                    }
                    final s = rows[i - 1];
                    final color = fuelColor(s.fuelType);
                    return Dismissible(
                      key: ValueKey(s.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmDelete(s),
                      onDismissed: (_) => _reload(),
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white, size: 32),
                      ),
                      child: Card(
                        child: ListTile(
                          onTap: () => _edit(s),
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.15),
                            child: Icon(Icons.local_gas_station, color: color),
                          ),
                          title: Text(s.vin.isEmpty ? '(no VIN)' : s.vin,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${s.fuelType.isEmpty ? 'Unknown' : s.fuelType}'
                            '${s.specCode.isEmpty ? '' : ' • ${s.specCode}'}\n'
                            '${DateFormat('dd MMM yyyy, hh:mm a').format(s.scannedAt)}',
                          ),
                          isThreeLine: true,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? value) {
    final selected = _fuel == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 16)),
        selected: selected,
        onSelected: (_) {
          _fuel = value;
          _reload();
        },
      ),
    );
  }
}
