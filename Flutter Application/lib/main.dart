import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:equations/equations.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_barometer/flutter_barometer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const TrackingApp());

/* ======================== DOMAIN ====================================== */

class Measurement {
  final DateTime t;
  final double lat, lon, gpsAlt;
  final double? baroAlt;
  Measurement(this.t, this.lat, this.lon, this.gpsAlt, this.baroAlt);
}

/* ======================== ROOT ======================================== */

class TrackingApp extends StatelessWidget {
  const TrackingApp({super.key});

  @override
  Widget build(BuildContext ctx) => MaterialApp(
        title: 'Altitude Tracker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 2,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          cardTheme: CardTheme(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 2,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          cardTheme: CardTheme(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        themeMode: ThemeMode.system,
        home: const HomePage(),
      );
}

/* ======================== STATEFUL HOME =============================== */

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  /* ---------- STATE --------------------------------------------------- */
  final _meas = <Measurement>[];
  final _scroll = ScrollController();
  double? _baroAlt;
  Timer? _gpsTimer;
  StreamSubscription? _baroSub;
  bool _tracking = false;
  String _status = 'Ready';
  Position? _currentPosition;
  final _maxPoints = 1000; // Maximum points to store for memory optimization

  /* ---------- LIFECYCLE ---------------------------------------------- */
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLocationPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes to properly manage resources
    if (state == AppLifecycleState.paused) {
      // App goes to background
      _pauseTracking();
    } else if (state == AppLifecycleState.resumed) {
      // App comes to foreground
      if (_tracking) {
        _resumeTracking();
      }
    }
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _baroSub?.cancel();
    _scroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /* ---------- PERMISSION HANDLING ------------------------------------- */
  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _status = 'Location services disabled');
      _showLocationDialog();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _status = 'Location permission denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _status = 'Location permissions permanently denied');
      _showPermissionSettingsDialog();
      return;
    }

    // Ready to track
    setState(() => _status = 'Ready to track');
    // Get position once to show initial coordinates
    _capturePosition();
  }

  void _showLocationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Location Services Required'),
        content: const Text(
            'This app needs location services to track your position and altitude. '
            'Please enable location services in your device settings.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPermissionSettingsDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
            'This app needs location permission to track your position and altitude. '
            'Please enable location permission in your device settings.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /* ---------- TRACKING ------------------------------------------------ */
  void _start() {
    setState(() {
      _tracking = true;
      _status = 'Tracking in progress...';
      _meas.clear();
    });

    _gpsTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _capturePosition());

    _baroSub = flutterBarometerEvents.listen((e) {
      const p0 = 1013.25;
      final alt = (44330 * (1 - pow(e.pressure / p0, 0.1903))).toDouble();
      setState(() => _baroAlt = alt);
    });
  }

  void _pauseTracking() {
    _gpsTimer?.cancel();
    _baroSub?.cancel();
    setState(() => _status = 'Tracking paused');
  }

  void _resumeTracking() {
    _gpsTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _capturePosition());

    _baroSub = flutterBarometerEvents.listen((e) {
      const p0 = 1013.25;
      final alt = (44330 * (1 - pow(e.pressure / p0, 0.1903))).toDouble();
      setState(() => _baroAlt = alt);
    });

    setState(() => _status = 'Tracking resumed');
  }

  Future<void> _capturePosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best);

      setState(() {
        _currentPosition = pos;
        _meas.add(Measurement(DateTime.now(), pos.latitude, pos.longitude,
            pos.altitude, _baroAlt));

        // Memory optimization: limit the number of points stored
        if (_meas.length > _maxPoints) {
          _meas.removeAt(0);
        }

        _status = 'Location updated';
      });

      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 72,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } on Exception catch (e) {
      setState(() => _status = 'GPS error: $e');
    }
  }

  Future<void> _stopAndSave() async {
    _gpsTimer?.cancel();
    _baroSub?.cancel();
    setState(() {
      _tracking = false;
      _status = 'Tracking stopped';
    });

    if (_meas.isEmpty) {
      _showNoDataDialog();
      return;
    }

    final file = await _writeGPX();

    // Show share dialog
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Altitude Tracking Data (${_meas.length} points)',
      text: 'Exported on ${DateTime.now().toLocal()}',
    );
  }

  void _showNoDataDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No Data'),
        content: const Text('No tracking data available to export.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /* ---------- GPX EXPORT --------------------------------------------- */
  Future<File> _writeGPX() async {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
          '<gpx version="1.1" creator="Altitude Tracker" xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('<metadata>')
      ..writeln('  <name>Altitude Tracking Data</name>')
      ..writeln('  <time>${DateTime.now().toUtc().toIso8601String()}</time>')
      ..writeln('  <copyright author="AltitudeTracker"/>')
      ..writeln('</metadata>')
      ..writeln('<trk><name>${_fileStamp()}</name><trkseg>');

    // Add track points
    for (final m in _meas) {
      buf
        ..writeln('<trkpt lat="${m.lat}" lon="${m.lon}">')
        ..writeln('<ele>${m.gpsAlt.toStringAsFixed(1)}</ele>')
        ..writeln('<time>${m.t.toUtc().toIso8601String()}</time>');

      // Add barometric altitude as extension if available
      if (m.baroAlt != null) {
        buf
          ..writeln('<extensions>')
          ..writeln('<baro:alt>${m.baroAlt!.toStringAsFixed(1)}</baro:alt>')
          ..writeln('</extensions>');
      }

      buf..writeln('</trkpt>');
    }

    buf..writeln('</trkseg></trk></gpx>');

    // Save file
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${_fileStamp()}.gpx');

    return file.writeAsString(buf.toString()).then((f) {
      setState(() => _status = 'Saved: ${file.path}');
      return f;
    });
  }

  String _fileStamp() =>
      'AltitudeTrack_${DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}';

  /* ---------- DISTANCES ---------------------------------------------- */
  List<double> _distances() {
    double cum = 0;
    final list = <double>[0];
    for (var i = 1; i < _meas.length; i++) {
      cum += _haversine(_meas[i - 1], _meas[i]);
      list.add(cum);
    }
    return list; // km
  }

  static const _rEarth = 6371.0; // km
  double _haversine(Measurement a, Measurement b) {
    final dLat = _deg(b.lat - a.lat);
    final dLon = _deg(b.lon - a.lon);
    final lat1 = _deg(a.lat);
    final lat2 = _deg(b.lat);
    final h =
        pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
    return 2 * _rEarth * asin(sqrt(h));
  }

  double _deg(double d) => d * pi / 180;

  /* ---------- SMOOTHING ---------------------------------------------- */
  final _filterNames = ['Raw', 'Spline', 'LOESS'];
  String _selFilter = 'Raw';

  List<double> _applyFilter(List<double> x, List<double> y) {
    // Safety: too few data or non-increasing? -> Return raw data
    if (x.length < 3 || x.toSet().length != x.length) return y;

    switch (_selFilter) {
      case 'Spline':
        final nodes = <InterpolationNode>[];
        for (var i = 0; i < x.length; i++) {
          if (i == 0 || x[i] > x[i - 1]) {
            nodes.add(InterpolationNode(x: x[i], y: y[i]));
          }
        }
        final spline = SplineInterpolation(nodes: nodes);
        return x.map(spline.compute).toList();

      case 'LOESS':
        return _loess(x, y, window: .15, iters: 2);

      default:
        return y;
    }
  }

  /* ---------- MINIMAL LOESS ------------------------------------------ */
  List<double> _loess(List<double> x, List<double> y,
      {double window = .1, int iters = 2}) {
    final n = x.length;
    final wSize = max(3, (window * n).round());
    var yHat = List<double>.from(y);

    // Optimize: pre-compute distances between points
    final distances =
        List.generate(n, (i) => List.generate(n, (j) => (x[i] - x[j]).abs()));

    for (var iter = 0; iter < iters; iter++) {
      final res = List<double>.filled(n, 0);

      for (var i = 0; i < n; i++) {
        // Find nearest neighbors more efficiently
        final dists = distances[i];
        final indices = List.generate(n, (j) => j);
        indices.sort((a, b) => dists[a].compareTo(dists[b]));
        final nn = indices.take(wSize).toList();

        // Tricube weights
        final dMax = nn.map((j) => dists[j]).reduce(max);
        final w = [
          for (final j in nn) pow(1 - pow((dists[j] / dMax), 3), 3).toDouble()
        ];

        // X-Matrix: [1, dx, dx²]
        final List<List<double>> X = [
          for (final j in nn)
            [
              1.0,
              (x[j] - x[i]),
              pow(x[j] - x[i], 2).toDouble(),
            ]
        ];

        // X^T
        final List<List<double>> XT = List.generate(
          3,
          (k) => [for (final row in X) row[k]],
        );

        // diag(W)
        final List<List<double>> W = List.generate(
          wSize,
          (r) => List.generate(wSize, (c) => r == c ? w[r] : 0.0),
        );

        final XT_W = _matMul(XT, W);

        final beta = _solve(
          _matMul(XT_W, X),
          _matVec(XT_W, [for (final j in nn) y[j]]),
        );

        yHat[i] = beta[0]; // since (x - xi) = 0
        res[i] = (y[i] - yHat[i]).abs();
      }

      // Early stopping for convergence
      if (res.reduce((a, b) => a + b) / n < 1e-6) break;
    }

    return yHat;
  }

  /* ---------- LINEAR-ALGEBRA HELPERS ---------------------------------- */
  List<List<double>> _matMul(List<List<double>> A, List<List<double>> B) {
    final m = A.length, n = B[0].length, k = B.length;
    return List.generate(
      m,
      (i) => List.generate(
        n,
        (j) => Iterable<int>.generate(k)
            .map((l) => A[i][l] * B[l][j])
            .reduce((a, b) => a + b),
      ),
    );
  }

  List<double> _matVec(List<List<double>> A, List<double> v) => [
        for (final row in A)
          Iterable<int>.generate(v.length)
              .map((i) => row[i] * v[i])
              .reduce((a, b) => a + b)
      ];

  List<double> _solve(List<List<double>> A, List<double> b) {
    double det(List<List<double>> m) =>
        m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
        m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
        m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

    final d = det(A);
    if (d.abs() < 1e-12) return [0, 0, 0];

    List<double> col(int c) => [for (final r in A) r[c]];
    final dx = det([b, col(1), col(2)]);
    final dy = det([col(0), b, col(2)]);
    final dz = det([col(0), col(1), b]);
    return [dx / d, dy / d, dz / d];
  }

  /* ---------- UI HELPER WIDGETS -------------------------------------- */
  Widget _buildStatusIndicator() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: _tracking ? Colors.green : Colors.red,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildCoordinatesDisplay() {
    if (_currentPosition == null) {
      return const Text('No location data available');
    }

    final pos = _currentPosition!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Latitude: ${pos.latitude.toStringAsFixed(6)}°'),
        Text('Longitude: ${pos.longitude.toStringAsFixed(6)}°'),
        Row(
          children: [
            Expanded(
              child: Text('GPS Alt: ${pos.altitude.toStringAsFixed(1)} m'),
            ),
            if (_baroAlt != null)
              Expanded(
                child: Text('Baro Alt: ${_baroAlt!.toStringAsFixed(1)} m'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildMeasurementsList() {
    if (_meas.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('No measurements yet',
              style: TextStyle(fontStyle: FontStyle.italic)),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Tracking Data (${_meas.length} points)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: _meas.length,
            itemBuilder: (_, i) {
              final m = _meas[i];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text('${i + 1}'),
                ),
                title: Text(
                    '${m.lat.toStringAsFixed(6)}, ${m.lon.toStringAsFixed(6)}'),
                subtitle: Text(
                    'Alt: ${m.gpsAlt.toStringAsFixed(1)}m | Baro: ${m.baroAlt?.toStringAsFixed(1) ?? 'n/a'}m'),
                trailing: Text(
                  TimeOfDay.fromDateTime(m.t).format(context),
                  style: const TextStyle(fontSize: 12),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About Altitude Tracker'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'This app tracks your location and altitude using GPS and barometric sensors.'),
              SizedBox(height: 8),
              Text('• Tap START to begin tracking'),
              Text('• Tap STOP & SAVE to export as GPX'),
              SizedBox(height: 8),
              Text(
                  'Your data is stored only on your device and can be shared as a GPX file.'),
              SizedBox(height: 16),
              Text('Altitude Tracker v1.1.0'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /* ======================== UI ======================================= */
  @override
  Widget build(BuildContext ctx) {
    final dist = _distances();
    final altRaw = _meas.map((m) => m.gpsAlt).toList();
    final altSm = _applyFilter(dist, altRaw);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Altitude Tracker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.tune),
            onSelected: (value) => setState(() => _selFilter = value),
            itemBuilder: (context) => _filterNames
                .map((f) => PopupMenuItem(value: f, child: Text(f)))
                .toList(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Current status card
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Current Status',
                            style: Theme.of(context).textTheme.titleMedium),
                        _buildStatusIndicator(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_status,
                        style: TextStyle(
                          color: _tracking ? Colors.green : Colors.grey,
                        )),
                    const Divider(),
                    _buildCoordinatesDisplay(),
                  ],
                ),
              ),
            ),

            // Altitude graph
            Expanded(
              flex: 2,
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: _buildChart(dist, altRaw, altSm),
                ),
              ),
            ),

            // Tracking table
            Expanded(
              flex: 2,
              child: Card(
                margin: const EdgeInsets.all(12),
                child: _buildMeasurementsList(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _tracking ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _tracking ? _stopAndSave : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop & Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ---------------- CHART -------------------------------------------- */
  Widget _buildChart(List<double> x, List<double> raw, List<double> sm) {
    if (x.length < 2) {
      return const Center(
        child: Text('No data available for chart'),
      );
    }

    final minY = (raw.isEmpty ? 0 : raw.reduce(min)).toDouble() - 10;
    final maxY = (raw.isEmpty ? 100 : raw.reduce(max)).toDouble() + 10;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: x.isEmpty ? 1 : x.last,
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            drawHorizontalLine: true,
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor:
                  Theme.of(context).colorScheme.surface.withOpacity(0.8),
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  return LineTooltipItem(
                    '${spot.y.toStringAsFixed(1)} m\n${spot.x.toStringAsFixed(2)} km',
                    TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      value.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
              axisNameWidget: const Text('Distance (km)'),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(
                      value.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
              axisNameWidget: const Text('Altitude (m)'),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          lineBarsData: [
            _line(raw, x, Colors.blue, false),
            _line(sm, x, Colors.orange, true),
          ],
          borderData: FlBorderData(
            show: true,
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
              width: 1,
            ),
          ),
        ),
      ),
    );
  }

  LineChartBarData _line(List<double> y, List<double> x, Color c, bool dash) =>
      LineChartBarData(
        spots: [
          for (var i = 0; i < y.length; i++) FlSpot(x[i], y[i]),
        ],
        isCurved: true,
        color: c,
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(show: false),
        dashArray: dash ? [8, 4] : null,
        belowBarData: BarAreaData(
          show: true,
          color: c.withOpacity(0.2),
        ),
      );
}
