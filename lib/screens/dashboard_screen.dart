import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vehicle_scan.dart';
import '../services/database_service.dart';
import '../theme.dart';
import 'history_screen.dart';
import 'review_screen.dart';
import 'scanner_screen.dart';

class _DashData {
  final int total;
  final Map<String, int> fuel;
  final List<VehicleScan> recent;
  const _DashData(this.total, this.fuel, this.recent);
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashData> _future = _load();

  Future<_DashData> _load() async {
    final db = DatabaseService.instance;
    final results = await Future.wait([db.count(), db.fuelCounts(), db.recent()]);
    return _DashData(
      results[0] as int,
      results[1] as Map<String, int>,
      results[2] as List<VehicleScan>,
    );
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _startScan() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (mounted) _refresh();
  }

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
    if (mounted) _refresh();
  }

  Future<void> _openEdit(VehicleScan scan) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReviewScreen(scan: scan, isEdit: true)),
    );
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vehicle Scanner'),
        actions: [
          IconButton(
            tooltip: 'History',
            iconSize: 28,
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
          ),
        ],
      ),
      body: FutureBuilder<_DashData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return _ErrorView(
              message: 'Could not load data.\n${snap.error}',
              onRetry: _refresh,
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.qr_code_scanner, size: 30),
                  label: const Text('START SCAN'),
                ),
                const SizedBox(height: 16),
                _TotalCard(total: d.total),
                const SizedBox(height: 16),
                _FuelCard(fuel: d.fuel, total: d.total),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent scans',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: _openHistory,
                      child: const Text('View all', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (d.recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No scans yet.\nTap START SCAN to begin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                    ),
                  )
                else
                  ...d.recent.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ScanTile(scan: s, onTap: () => _openEdit(s)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final int total;
  const _TotalCard({required this.total});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.directions_car_filled, size: 44, color: Color(0xFF0B5FFF)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total vehicles scanned',
                      style: TextStyle(fontSize: 16, color: Colors.black54)),
                  Text('$total',
                      style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FuelCard extends StatelessWidget {
  final Map<String, int> fuel;
  final int total;
  const _FuelCard({required this.fuel, required this.total});

  @override
  Widget build(BuildContext context) {
    // Always show the four main fuel types, then any extras present.
    final keys = <String>['Petrol', 'Diesel', 'CNG', 'EV'];
    for (final k in fuel.keys) {
      if (!keys.contains(k)) keys.add(k);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('By fuel type',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (final k in keys) _FuelBar(label: k, count: fuel[k] ?? 0, total: total),
          ],
        ),
      ),
    );
  }
}

class _FuelBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  const _FuelBar({required this.label, required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final frac = total == 0 ? 0.0 : count / total;
    final color = fuelColor(label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 18,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text('$count',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _ScanTile extends StatelessWidget {
  final VehicleScan scan;
  final VoidCallback onTap;
  const _ScanTile({required this.scan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = fuelColor(scan.fuelType);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(Icons.local_gas_station, color: color),
        ),
        title: Text(scan.vin.isEmpty ? '(no VIN)' : scan.vin,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${scan.fuelType.isEmpty ? 'Unknown' : scan.fuelType}'
          '${scan.specCode.isEmpty ? '' : ' • ${scan.specCode}'}\n'
          '${DateFormat('dd MMM yyyy, hh:mm a').format(scan.scannedAt)}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
