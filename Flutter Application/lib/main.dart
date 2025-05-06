import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:xml/xml.dart' as xml;

import 'package:equations/equations.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_barometer/flutter_barometer.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

void main() => runApp(const TrackingApp());

/* ======================== DOMAIN ====================================== */

class Measurement {
  final DateTime t;
  final double lat, lon, gpsAlt;
  final double? baroAlt;
  Measurement(this.t, this.lat, this.lon, this.gpsAlt, this.baroAlt);
}

class TrackFile {
  final String name;
  final DateTime date;
  final int pointCount;
  final List<Measurement> measurements;

  TrackFile({
    required this.name,
    required this.date,
    required this.pointCount,
    required this.measurements,
  });
}

/* ======================== ROOT ======================================== */

class TrackingApp extends StatelessWidget {
  const TrackingApp({super.key});

  @override
  Widget build(BuildContext ctx) => MaterialApp(
        title: 'TrackIN',
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

  // Track loading status and currently loaded file
  bool _isLoadedTrack = false;
  TrackFile? _loadedTrack;

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
    // Properly cancel all tracking services
    _gpsTimer?.cancel();
    _gpsTimer = null;
    _baroSub?.cancel();
    _baroSub = null;

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
          '<gpx version="1.1" creator="TrackIN" xmlns="http://www.topografix.com/GPX/1/1">')
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
  // Add the ability to show both raw and smoothed data
  bool _showRaw = true;
  bool _showSmoothed = true;
  final _filterNames = ['Raw', 'Spline', 'LOESS'];
  String _selFilter = 'Spline';

  List<double> _applyFilter(List<double> x, List<double> y) {
    // Safety: too few data or non-increasing? -> Return raw data
    if (x.length < 3) return List<double>.from(y);

    // Ensure x values are sorted and unique for proper interpolation
    List<double> xVals = List<double>.from(x);
    List<double> yVals = List<double>.from(y);

    // For completely identical values, return the original
    if (xVals.toSet().length <= 1) return yVals;

    switch (_selFilter) {
      case 'Spline':
        try {
          // Create a clean list of nodes with strictly increasing x values
          final nodes = <InterpolationNode>[];
          double lastX = double.negativeInfinity;

          for (var i = 0; i < xVals.length; i++) {
            if (xVals[i] > lastX) {
              nodes.add(InterpolationNode(x: xVals[i], y: yVals[i]));
              lastX = xVals[i];
            }
          }

          // Need at least 3 points for a proper spline
          if (nodes.length < 3) return yVals;

          final spline = SplineInterpolation(nodes: nodes);

          // Now compute the spline for each original x value
          List<double> smoothed = [];
          for (var i = 0; i < xVals.length; i++) {
            try {
              smoothed.add(spline.compute(xVals[i]));
            } catch (e) {
              // Fallback to original if spline computation fails
              smoothed.add(yVals[i]);
            }
          }
          return smoothed;
        } catch (e) {
          // If any error occurs, return the original data
          return yVals;
        }

      case 'LOESS':
        try {
          return _loess(xVals, yVals, window: .25, iters: 3);
        } catch (e) {
          return yVals;
        }

      default:
        return yVals;
    }
  }

  /* ---------- MINIMAL LOESS ------------------------------------------ */
  List<double> _loess(List<double> x, List<double> y,
      {double window = .1, int iters = 2}) {
    try {
      final n = x.length;
      if (n < 3)
        return List<double>.from(y); // Return original if too few points

      // Calculate window size - at least 3 points, at most n points
      final wSize = max(3, min(n, (window * n).round()));

      // Start with original values
      var yHat = List<double>.from(y);

      // Optimize: pre-compute distances between points
      final distances =
          List.generate(n, (i) => List.generate(n, (j) => (x[i] - x[j]).abs()));

      // Run multiple iterations of LOESS for robustness
      for (var iter = 0; iter < iters; iter++) {
        final res = List<double>.filled(n, 0); // Store residuals

        // For each point, fit a local polynomial
        for (var i = 0; i < n; i++) {
          try {
            // Get distances from current point to all others
            final dists = distances[i];

            // Find indices of nearest neighbors
            final indices = List.generate(n, (j) => j);
            indices.sort((a, b) => dists[a].compareTo(dists[b]));
            final nn = indices.take(wSize).toList();

            // Calculate max distance in this neighborhood
            double dMax = nn.map((j) => dists[j]).reduce(max);
            if (dMax <= 0) dMax = 1.0; // Avoid division by zero

            // Compute tricube weights: w(x) = (1 - (d/dMax)³)³
            final w = [
              for (final j in nn)
                dists[j] >= dMax
                    ? 0.0
                    : pow(1 - pow((dists[j] / dMax), 3), 3).toDouble()
            ];

            // Check if weights are valid
            if (w.every((weight) => weight == 0)) {
              // All weights are zero, skip this point
              continue;
            }

            // Create design matrix X with columns [1, dx, dx²]
            final List<List<double>> X = [
              for (final j in nn)
                [
                  1.0, // Constant term
                  (x[j] - x[i]), // Linear term
                  pow(x[j] - x[i], 2).toDouble(), // Quadratic term
                ]
            ];

            // Compute X transpose
            final List<List<double>> XT = List.generate(
              3,
              (k) => [for (final row in X) row[k]],
            );

            // Create diagonal weight matrix
            final List<List<double>> W = List.generate(
              wSize,
              (r) => List.generate(wSize, (c) => r == c ? w[r] : 0.0),
            );

            // Matrix calculations for weighted least squares
            final XT_W = _matMul(XT, W);
            final XTW_X = _matMul(XT_W, X);
            final XTW_y = _matVec(XT_W, [for (final j in nn) y[j]]);

            // Solve for coefficients
            final beta = _solve(XTW_X, XTW_y);

            // Predict at the current point (since x[i] - x[i] = 0, only beta[0] matters)
            yHat[i] = beta[0];

            // Calculate absolute residual
            res[i] = (y[i] - yHat[i]).abs();
          } catch (e) {
            // If calculation fails for this point, keep original value
            // and continue with next point
            yHat[i] = y[i];
          }
        }
      }

      return yHat;
    } catch (e) {
      // Return original data if anything goes wrong
      return List<double>.from(y);
    }
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

  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('TrackIN'),
      actions: [
        // Load GPX file button
        IconButton(
          icon: const Icon(Icons.folder_open),
          tooltip: 'Load GPX file',
          onPressed: !_tracking ? _loadGpxFile : null,
        ),
        // Track info button (visible when track is loaded)
        if (_isLoadedTrack)
          IconButton(
            icon: const Icon(Icons.info),
            tooltip: 'Track Info',
            onPressed: () => _showTrackInfoDialog(context),
          ),
        // Smoothing filter selection
        PopupMenuButton<String>(
          icon: const Icon(Icons.tune),
          tooltip: 'Change smoothing algorithm',
          onSelected: (value) => setState(() => _selFilter = value),
          itemBuilder: (context) => _filterNames
              .map((f) => PopupMenuItem(value: f, child: Text(f)))
              .toList(),
        ),
        // Help/about button
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: 'Help',
          onPressed: () => _showInfoDialog(context),
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

  /* ---------- GPX LOADING FUNCTIONALITY -------------------------------- */

  Future<void> _loadGpxFile() async {
    try {
      // Show loading indicator
      setState(() => _status = 'Selecting GPX file...');

      // Open file picker to select GPX file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _status = 'File selection canceled');
        return;
      }

      // Get the file path
      String? filePath = result.files.single.path;
      if (filePath == null) {
        setState(() => _status = 'Could not get file path');
        return;
      }

      // Read the file contents
      setState(() => _status = 'Reading GPX file...');
      final file = File(filePath);
      final contents = await file.readAsString();

      // Parse GPX data
      setState(() => _status = 'Parsing GPX data...');
      final parsedMeasurements = _parseGpxData(contents);

      if (parsedMeasurements.isEmpty) {
        setState(() => _status = 'No valid data found in GPX file');
        return;
      }

      // Create a TrackFile object
      final trackName = result.files.single.name;
      final firstPoint = parsedMeasurements.first;

      final loadedTrack = TrackFile(
        name: trackName,
        date: firstPoint.t,
        pointCount: parsedMeasurements.length,
        measurements: parsedMeasurements,
      );

      // Update state with loaded data
      setState(() {
        _isLoadedTrack = true;
        _loadedTrack = loadedTrack;
        _meas.clear();
        _meas.addAll(parsedMeasurements);
        _status = 'Loaded ${parsedMeasurements.length} points from $trackName';
      });
    } catch (e) {
      setState(() => _status = 'Error loading GPX file: $e');
    }
  }

  List<Measurement> _parseGpxData(String gpxContent) {
    try {
      final measurements = <Measurement>[];

      // Parse XML
      final document = xml.XmlDocument.parse(gpxContent);

      // Find track points
      final trackPoints = document.findAllElements('trkpt');

      for (final point in trackPoints) {
        try {
          // Get latitude and longitude
          final lat = double.parse(point.getAttribute('lat') ?? '0');
          final lon = double.parse(point.getAttribute('lon') ?? '0');

          // Get elevation (altitude)
          final eleElement = point.findElements('ele').firstOrNull;
          final elevation =
              eleElement != null ? double.parse(eleElement.innerText) : 0.0;

          // Get time
          final timeElement = point.findElements('time').firstOrNull;
          final timeString = timeElement?.innerText ?? '';
          final time = timeString.isNotEmpty
              ? DateTime.parse(timeString)
              : DateTime.now();

          // Check for barometric altitude in extensions
          double? baroAlt;
          final extensionsElement =
              point.findElements('extensions').firstOrNull;
          if (extensionsElement != null) {
            final baroElement =
                extensionsElement.findElements('baro:alt').firstOrNull;
            if (baroElement != null) {
              baroAlt = double.tryParse(baroElement.innerText);
            }
          }

          // Create and add measurement
          measurements.add(Measurement(time, lat, lon, elevation, baroAlt));
        } catch (e) {
          // Skip invalid points
          continue;
        }
      }

      return measurements;
    } catch (e) {
      // Return empty list on parsing error
      return [];
    }
  }

  void _showTrackInfoDialog(BuildContext context) {
    if (_loadedTrack == null) return;

    // Calculate some stats
    final track = _loadedTrack!;
    final distances = _distances();
    final totalDistance = distances.isEmpty ? 0.0 : distances.last;
    final elevations = track.measurements.map((m) => m.gpsAlt).toList();
    final minElevation = elevations.reduce(min);
    final maxElevation = elevations.reduce(max);
    final elevationGain = _calculateElevationGain(elevations);

    final startTime = track.measurements.first.t;
    final endTime = track.measurements.last.t;
    final duration = endTime.difference(startTime);

    // Format duration
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    final durationString =
        '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Track: ${track.name}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  'Date: ${DateFormat('dd.MM.yyyy - HH:mm').format(track.date)}'),
              const SizedBox(height: 8),
              Text('Points: ${track.pointCount}'),
              Text('Distance: ${totalDistance.toStringAsFixed(2)} km'),
              Text('Duration: $durationString'),
              const SizedBox(height: 8),
              Text('Min Elevation: ${minElevation.toStringAsFixed(1)} m'),
              Text('Max Elevation: ${maxElevation.toStringAsFixed(1)} m'),
              Text(
                  'Elevation Range: ${(maxElevation - minElevation).toStringAsFixed(1)} m'),
              Text('Total Ascent: ${elevationGain.toStringAsFixed(1)} m'),
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

  double _calculateElevationGain(List<double> elevations) {
    if (elevations.length <= 1) return 0;

    double totalGain = 0;
    for (int i = 1; i < elevations.length; i++) {
      final diff = elevations[i] - elevations[i - 1];
      if (diff > 0) totalGain += diff;
    }

    return totalGain;
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About TrackIN'),
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
              Text('TrackIN v1.1.0'),
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
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            // Current status/file info card
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
                        _isLoadedTrack
                            ? Text(
                                'Loaded Track: ${_loadedTrack?.name ?? "Unknown"}',
                                style: Theme.of(context).textTheme.titleMedium)
                            : Text('Current Status',
                                style: Theme.of(context).textTheme.titleMedium),
                        _tracking ? _buildStatusIndicator() : Container(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(_status,
                        style: TextStyle(
                          color: _tracking
                              ? Colors.green
                              : _isLoadedTrack
                                  ? Colors.blue
                                  : Colors.grey,
                        )),
                    const Divider(),
                    _isLoadedTrack
                        ? _buildTrackSummary()
                        : _buildCoordinatesDisplay(),
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
                  child: Column(
                    children: [
                      // Graph visibility controls
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Raw data toggle
                            Row(
                              children: [
                                Checkbox(
                                  value: _showRaw,
                                  onChanged: (val) {
                                    setState(() => _showRaw = val ?? true);
                                  },
                                ),
                                const Text('Raw Data'),
                              ],
                            ),
                            const SizedBox(width: 16),
                            // Smoothed data toggle
                            Row(
                              children: [
                                Checkbox(
                                  value: _showSmoothed,
                                  onChanged: (val) {
                                    setState(() => _showSmoothed = val ?? true);
                                  },
                                ),
                                const Text('Smoothed'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // The chart
                      Expanded(
                        child: _buildChart(dist, altRaw, altSm),
                      ),
                    ],
                  ),
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
      bottomNavigationBar: _buildBottomAppBar(),
    );
  }

  Widget _buildTrackSummary() {
    if (_loadedTrack == null) return Container();

    final distances = _distances();
    final totalDistance = distances.isEmpty ? 0.0 : distances.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Points: ${_loadedTrack!.pointCount}'),
        Text('Distance: ${totalDistance.toStringAsFixed(2)} km'),
        Text(
            'Date: ${DateFormat('dd.MM.yyyy - HH:mm').format(_loadedTrack!.date)}'),
      ],
    );
  }

  Widget _buildBottomAppBar() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Start tracking button - disabled during tracking or when viewing a loaded file
            ElevatedButton.icon(
              onPressed: (!_tracking && !_isLoadedTrack) ? _start : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
            ),
            const SizedBox(width: 16),
            // Stop & Save button - only enabled during tracking
            ElevatedButton.icon(
              onPressed: _tracking ? _stopAndSave : null,
              icon: const Icon(Icons.stop),
              label: const Text('Stop & Save'),
            ),
            // Clear loaded track button - only visible when a track is loaded
            if (_isLoadedTrack) ...[
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoadedTrack = false;
                    _loadedTrack = null;
                    _meas.clear();
                    _status = 'Ready';
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade100,
                  foregroundColor: Colors.red.shade700,
                ),
              ),
            ],
          ],
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

    // Create the line bars data based on visibility settings
    final lineBarsData = <LineChartBarData>[];

    // Add raw data line if visible
    if (_showRaw) {
      lineBarsData.add(_line(raw, x, Colors.blue, false, 'Raw'));
    }

    // Add smoothed data line if visible
    if (_showSmoothed) {
      lineBarsData
          .add(_line(sm, x, Colors.orange, true, 'Smoothed ($_selFilter)'));
    }

    // Chart legend
    final legend = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_showRaw) ...[
          Container(
            width: 16,
            height: 3,
            color: Colors.blue,
          ),
          const SizedBox(width: 5),
          const Text('Raw'),
          const SizedBox(width: 20),
        ],
        if (_showSmoothed) ...[
          Container(
            width: 16,
            height: 3,
            color: Colors.orange,
          ),
          const SizedBox(width: 5),
          Text('Smoothed ($_selFilter)'),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
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
                lineBarsData: lineBarsData,
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          legend, // Display the legend at the bottom
        ],
      ),
    );
  }

  LineChartBarData _line(
          List<double> y, List<double> x, Color c, bool dash, String title) =>
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
