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
        title: 'Tracking App',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
        home: const HomePage(),
      );
}

/* ======================== STATEFUL HOME =============================== */

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /* ---------- STATE --------------------------------------------------- */
  final _meas = <Measurement>[];
  final _scroll = ScrollController();
  double? _baroAlt;
  Timer? _gpsTimer;
  StreamSubscription? _baroSub;
  bool _tracking = false;
  String _status = 'Bereit';

  /* ---------- LIFECYCLE ---------------------------------------------- */
  @override
  void dispose() {
    _gpsTimer?.cancel();
    _baroSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /* ---------- TRACKING ------------------------------------------------ */
  void _start() {
    setState(() {
      _tracking = true;
      _status = 'Tracking läuft …';
      _meas.clear();
    });

    _gpsTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _capturePosition());

    _baroSub = flutterBarometerEvents.listen((e) {
      const p0 = 1013.25;
      final alt =
          (44330 * (1 - pow(e.pressure / p0, 0.1903))).toDouble(); // num→double
      setState(() => _baroAlt = alt);
    });
  }

  Future<void> _capturePosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best);
      setState(() {
        _meas.add(Measurement(DateTime.now(), pos.latitude, pos.longitude,
            pos.altitude, _baroAlt));
        _status =
            'Fix: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      });
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 72,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      _scroll.animateTo(_scroll.position.maxScrollExtent + 72,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } on Exception catch (e) {
      setState(() => _status = 'GPS-Fehler: $e');
    }
  }

  Future<void> _stopAndSave() async {
    _gpsTimer?.cancel();
    _baroSub?.cancel();
    setState(() => _tracking = false);
    final file = await _writeGPX();
    await Share.shareXFiles([XFile(file.path)], subject: 'GPX-Export');
  }

  /* ---------- GPX EXPORT --------------------------------------------- */
  Future<File> _writeGPX() async {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
          '<gpx version="1.1" creator="tracking_app" xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('<metadata><copyright author="THI SS25"/></metadata>')
      ..writeln('<trk><name>${_fileStamp()}</name><trkseg>');
    for (final m in _meas) {
      buf
        ..writeln('<trkpt lat="${m.lat}" lon="${m.lon}">')
        ..writeln('<ele>${m.gpsAlt.toStringAsFixed(1)}</ele>')
        ..writeln('<time>${m.t.toUtc().toIso8601String()}</time>')
        ..writeln('</trkpt>');
    }
    buf..writeln('</trkseg></trk></gpx>');
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${_fileStamp()}.gpx');
    return file.writeAsString(buf.toString()).then((f) {
      setState(() => _status = 'Gespeichert: ${f.path}');
      return f;
    });
  }

  String _fileStamp() =>
      DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

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
    // Safety: zu wenig Daten oder nicht-steigend? -> Rohdaten zurückgeben
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

    for (var iter = 0; iter < iters; iter++) {
      final res = List<double>.filled(n, 0);
      for (var i = 0; i < n; i++) {
        // ---- k-nächste Nachbarn nach |x-xi|
        final idx = List<int>.generate(n, (j) => j)
          ..sort((a, b) => (x[a] - x[i]).abs().compareTo((x[b] - x[i]).abs()));
        final nn = idx.take(wSize).toList();

        // ---- Tricube-Gewichte
        final dMax = nn.map((j) => (x[j] - x[i]).abs()).reduce(max);
        final w = [
          for (final j in nn)
            pow(1 - pow(((x[j] - x[i]).abs() / dMax), 3), 3).toDouble()
        ];

        // ---- X-Matrix: [1, dx, dx²]
        final List<List<double>> X = [
          for (final j in nn)
            [
              1.0,
              (x[j] - x[i]),
              pow(x[j] - x[i], 2).toDouble(),
            ]
        ];

        // ---- X^T
        final List<List<double>> XT = List.generate(
          3,
          (k) => [for (final row in X) row[k]],
        );

        // ---- diag(W)
        final List<List<double>> W = List.generate(
          wSize,
          (r) => List.generate(wSize, (c) => r == c ? w[r] : 0.0),
        );

        final XT_W = _matMul(XT, W);

        final beta = _solve(
          _matMul(XT_W, X),
          _matVec(XT_W, [for (final j in nn) y[j]]),
        );

        yHat[i] = beta[0]; // da (x - xi) = 0
        res[i] = (y[i] - yHat[i]).abs();
      }
      if (res.reduce((a, b) => a + b) / n < 1e-6) break; // trivialer Stopp
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

  /* ======================== UI ======================================= */

  @override
  Widget build(BuildContext ctx) {
    final dist = _distances();
    final altRaw = _meas.map((m) => m.gpsAlt).toList();
    final altSm = _applyFilter(dist, altRaw);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking App'),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selFilter,
              items: _filterNames
                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                  .toList(),
              onChanged: (v) => setState(() => _selFilter = v!),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildChart(dist, altRaw, altSm)),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              controller: _scroll,
              child: ListView.separated(
                controller: _scroll,
                itemCount: _meas.length,
                separatorBuilder: (_, __) => const Divider(height: .5),
                itemBuilder: (_, i) => _MeasurementTile(m: _meas[i]),
              ),
            ),
          ),
          Text(_status),
          const SizedBox(height: 4),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _tracking ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _tracking ? _stopAndSave : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop & GPX'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ---------------- CHART -------------------------------------------- */

  Widget _buildChart(List<double> x, List<double> raw, List<double> sm) {
    if (x.length < 2) return const Center(child: Text('Noch keine Daten'));
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: x.last,
          gridData: FlGridData(show: true),
          lineTouchData: const LineTouchData(enabled: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: true, reservedSize: 32)),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
          ),
          lineBarsData: [
            _line(raw, x, Colors.blue, false),
            _line(sm, x, Colors.orange, true),
          ],
        ),
      ),
    );
  }

  LineChartBarData _line(List<double> y, List<double> x, Color c, bool dash) =>
      LineChartBarData(
        spots: [
          for (var i = 0; i < x.length; i++) FlSpot(x[i], y[i]),
        ],
        isCurved: true,
        color: c,
        barWidth: 2,
        dashArray: dash ? [8, 4] : null,
      );
}

/* ---------------- LIST-TILE ------------------------------------------- */

class _MeasurementTile extends StatelessWidget {
  final Measurement m;
  const _MeasurementTile({required this.m});

  @override
  Widget build(BuildContext ctx) => ListTile(
        title: Text('${m.lat.toStringAsFixed(6)}, ${m.lon.toStringAsFixed(6)}'),
        subtitle: Text('GPS ${m.gpsAlt.toStringAsFixed(1)} m | '
            'Baro ${m.baroAlt?.toStringAsFixed(1) ?? 'n/a'} m'),
        trailing: Text(
          TimeOfDay.fromDateTime(m.t).format(ctx),
          style: const TextStyle(fontSize: 12),
        ),
      );
}
