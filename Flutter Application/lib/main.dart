import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_barometer/flutter_barometer.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';

// Modell für eine Messung
class Measurement {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double gpsAltitude;
  final double? altimeterHeight;

  Measurement({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.gpsAltitude,
    this.altimeterHeight,
  });
}

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracking App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Position? _currentPosition;
  String _status = "Bereit";
  double? _altimeterHeight;
  Timer? _locationTimer;
  StreamSubscription? _barometerSubscription;
  // Liste, in der alle Messungen gespeichert werden
  List<Measurement> _measurements = [];
  bool _isTracking = false;

  // Startet das Tracking: Timer für GPS und Abonnement des Barometer-Streams
  void _startTracking() {
    setState(() {
      _measurements.clear();
      _isTracking = true;
      _status = "Tracking gestartet";
    });
    // Starte GPS-Messung alle 5 Sekunden
    _locationTimer =
        Timer.periodic(Duration(seconds: 5), (_) => _fetchLocation());
    // Starte Barometer-Stream (nur auf iOS, falls verfügbar)
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      _barometerSubscription =
          flutterBarometerEvents.listen((FlutterBarometerEvent event) {
        // event ist vom Typ BarometerEvent, der den Luftdruck enthält
        double pressure = event.pressure; // in hPa
        const double seaLevelPressure = 1013.25;
        double altitude =
            44330 * (1 - pow(pressure / seaLevelPressure, 0.1903).toDouble());
        setState(() {
          _altimeterHeight = altitude;
        });
      });
    }
  }

  // Stoppt das Tracking
  void _stopTracking() {
    _locationTimer?.cancel();
    _barometerSubscription?.cancel();
    setState(() {
      _isTracking = false;
      _status = "Tracking gestoppt";
    });
  }

  // GPS-Daten abrufen und Messung speichern
  Future<void> _fetchLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _status = "Standortdienste sind deaktiviert.");
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _status = "Keine Standort-Berechtigung.");
      return;
    }
    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _currentPosition = pos;
        _status =
            "Messung erfasst: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}";
        // Erstelle eine Messung mit aktuellem Zeitpunkt und den Werten
        _measurements.add(
          Measurement(
            timestamp: DateTime.now(),
            latitude: pos.latitude,
            longitude: pos.longitude,
            gpsAltitude: pos.altitude,
            altimeterHeight: _altimeterHeight,
          ),
        );
      });
    } catch (e) {
      setState(() => _status = "Fehler: $e");
    }
  }

  // Speichert die gesammelten Daten als GPX-Datei
  Future<void> _saveGPXFile() async {
    if (_measurements.isEmpty) return;

    StringBuffer gpxBuffer = StringBuffer();
    gpxBuffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    gpxBuffer.writeln(
        '<gpx version="1.1" creator="TrackingApp" xmlns="http://www.topografix.com/GPX/1/1">');
    gpxBuffer.writeln('<trk>');
    gpxBuffer.writeln('<name>Tracking Data</name>');
    gpxBuffer.writeln('<trkseg>');
    for (var m in _measurements) {
      gpxBuffer.writeln('<trkpt lat="${m.latitude}" lon="${m.longitude}">');
      // Hier wird die GPS-Höhe verwendet – alternativ kann auch der Barometerwert genutzt werden
      gpxBuffer.writeln('<ele>${m.gpsAltitude.toStringAsFixed(1)}</ele>');
      gpxBuffer
          .writeln('<time>${m.timestamp.toUtc().toIso8601String()}</time>');
      gpxBuffer.writeln('</trkpt>');
    }
    gpxBuffer.writeln('</trkseg>');
    gpxBuffer.writeln('</trk>');
    gpxBuffer.writeln('</gpx>');

    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = directory.path;
      final file = File('$path/tracking_data.gpx');
      await file.writeAsString(gpxBuffer.toString());
      setState(() {
        _status = "GPX-Datei gespeichert: $path/tracking_data.gpx";
      });
    } catch (e) {
      setState(() {
        _status = "Fehler beim Speichern der GPX-Datei: $e";
      });
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _barometerSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pos = _currentPosition;
    return Scaffold(
      appBar: AppBar(title: Text('Tracking App mit GPX Export')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Anzeige der aktuellen Messung
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: pos != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Aktuelle Messung:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Zeit: ${DateTime.now().toLocal()}'),
                        Text('Latitude: ${pos.latitude.toStringAsFixed(6)}'),
                        Text('Longitude: ${pos.longitude.toStringAsFixed(6)}'),
                        Text('GPS-Höhe: ${pos.altitude.toStringAsFixed(1)} m'),
                        if (_altimeterHeight != null)
                          Text(
                              'Barometer-Höhe: ${_altimeterHeight!.toStringAsFixed(1)} m'),
                        SizedBox(height: 10),
                        Text(_status, style: TextStyle(color: Colors.grey)),
                      ],
                    )
                  : Text('$_status'),
            ),
            Divider(),
            // Das Koordinatensystem als Diagramm
            Container(
              height: 200,
              padding: EdgeInsets.all(8.0),
              child: CustomPaint(
                painter: CoordinateChartPainter(_measurements),
                child: Container(),
              ),
            ),
            Divider(),
            // Tabelle mit allen Messungen
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Gesammelte Messungen:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Container(
              height: 300, // Feste Höhe, anpassbar
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Zeit')),
                    DataColumn(label: Text('Latitude')),
                    DataColumn(label: Text('Longitude')),
                    DataColumn(label: Text('GPS-Höhe (m)')),
                    DataColumn(label: Text('Barometer (m)')),
                  ],
                  rows: _measurements.map((m) {
                    return DataRow(cells: [
                      DataCell(Text(m.timestamp.toLocal().toString())),
                      DataCell(Text(m.latitude.toStringAsFixed(6))),
                      DataCell(Text(m.longitude.toStringAsFixed(6))),
                      DataCell(Text(m.gpsAltitude.toStringAsFixed(1))),
                      DataCell(Text(m.altimeterHeight != null
                          ? m.altimeterHeight!.toStringAsFixed(1)
                          : 'n/a')),
                    ]);
                  }).toList(),
                ),
              ),
            ),
            Divider(),
            // Start-/Stop-Buttons und GPX-Export
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _isTracking ? null : _startTracking,
                    child: Text("Start"),
                  ),
                  ElevatedButton(
                    onPressed: _isTracking
                        ? () {
                            _stopTracking();
                            _saveGPXFile();
                          }
                        : null,
                    child: Text("Ende & Speichern"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoordinateChartPainter extends CustomPainter {
  final List<Measurement> measurements;

  CoordinateChartPainter(this.measurements);

  @override
  void paint(Canvas canvas, Size size) {
    final paintAxis = Paint()
      ..color = Colors.black
      ..strokeWidth = 2.0;
    final paintPoint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4.0;

    // Zeichne X- und Y-Achsen (hier einfach am unteren und linken Rand)
    canvas.drawLine(
      Offset(40, size.height - 40),
      Offset(size.width - 10, size.height - 40),
      paintAxis,
    );
    canvas.drawLine(Offset(40, size.height - 40), Offset(40, 10), paintAxis);

    if (measurements.isEmpty) return;

    // Bestimme min/max für Latitude und Longitude, um zu skalieren
    double minLat = measurements.first.latitude;
    double maxLat = measurements.first.latitude;
    double minLon = measurements.first.longitude;
    double maxLon = measurements.first.longitude;
    for (var m in measurements) {
      if (m.latitude < minLat) minLat = m.latitude;
      if (m.latitude > maxLat) maxLat = m.latitude;
      if (m.longitude < minLon) minLon = m.longitude;
      if (m.longitude > maxLon) maxLon = m.longitude;
    }
    if (minLat == maxLat) {
      minLat -= 0.001;
      maxLat += 0.001;
    }
    if (minLon == maxLon) {
      minLon -= 0.001;
      maxLon += 0.001;
    }
    final double leftMargin = 40;
    final double bottomMargin = 40;
    final double drawWidth = size.width - leftMargin - 10;
    final double drawHeight = size.height - bottomMargin - 10;
    for (var m in measurements) {
      double normLon = (m.longitude - minLon) / (maxLon - minLon);
      double normLat = (m.latitude - minLat) / (maxLat - minLat);
      double x = leftMargin + normLon * drawWidth;
      double y = 10 + (1 - normLat) * drawHeight;
      canvas.drawCircle(Offset(x, y), 3.0, paintPoint);
    }
  }

  @override
  bool shouldRepaint(covariant CoordinateChartPainter oldDelegate) {
    return oldDelegate.measurements != measurements;
  }
}
