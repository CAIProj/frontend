import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';

// Import des flutter_barometer-Pakets:
import 'package:flutter_barometer/flutter_barometer.dart';
import 'package:path_provider/path_provider.dart';

// Neuer Import für den Graphen:
import 'package:fl_chart/fl_chart.dart';

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
  // Deklaration der benötigten Variablen und Stream-Abonnements
  Position? _currentPosition;
  String _status = "Bereit";
  double? _relativeAltitude;

  StreamSubscription<Position>?
      _positionSub; // Falls du später den Stream nutzen möchtest
  StreamSubscription? _barometerSub;
  Timer? _locationTimer;

  // Gespeicherte Messungen
  List<Measurement> _measurements = [];
  bool _isTracking = false;

  @override
  void initState() {
    super.initState();
    // Tracking wird erst durch Buttonstart initiiert.
  }

  // Holt den aktuellen Standort über getCurrentPosition (ältere API-Version)
  Future<void> _fetchLocation() async {
    setState(() {
      _status = "Frage Berechtigung an...";
    });
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = "Standortdienste sind deaktiviert.";
      });
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _status = "Keine Standort-Berechtigung.";
      });
      return;
    }
    setState(() {
      _status = "Standort wird ermittelt...";
    });
    try {
      // Verwenden der älteren API mit desiredAccuracy
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _currentPosition = pos;
        _status = "Standort aktualisiert";
      });
    } catch (e) {
      setState(() {
        _status = "Fehler: $e";
      });
    }
  }

  // Startet den Barometer-Stream mithilfe des flutter_barometer-Pakets.
  void _startBarometer() {
    if (_barometerSub != null) return;
    if (!Platform.isIOS)
      return; // Barometer-Werte werden hier nur auf iOS erwartet.

    _barometerSub =
        flutterBarometerEvents.listen((FlutterBarometerEvent event) {
      double pressure = event.pressure; // in hPa
      const double seaLevelPressure = 1013.25; // hPa
      // Berechne die Höhe aus dem Luftdruck; toDouble() für den Fall, dass pow nicht direkt double liefert.
      double altitude =
          44330 * (1 - pow(pressure / seaLevelPressure, 0.1903).toDouble());
      setState(() {
        _relativeAltitude = altitude;
      });
    }, onError: (error) {
      setState(() {
        _status = "Barometer error: $error";
      });
    });
  }

  // Startet das Tracking: GPS-Daten werden alle 5 Sekunden abgerufen und eine Messung aufgezeichnet.
  void _startTracking() {
    setState(() {
      _measurements.clear();
      _isTracking = true;
      _status = "Tracking started";
    });

    // Alle 5 Sekunden wird _fetchLocation() aufgerufen
    _locationTimer = Timer.periodic(Duration(seconds: 5), (_) {
      _fetchLocation();
      _recordMeasurement();
    });

    _startBarometer();
  }

  // Fügt eine Messung basierend auf den neuesten Sensorwerten hinzu.
  void _recordMeasurement() {
    if (_currentPosition != null) {
      final now = DateTime.now();
      Measurement measurement = Measurement(
        timestamp: now,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        gpsAltitude: _currentPosition!.altitude,
        altimeterHeight: _relativeAltitude,
      );
      setState(() {
        _measurements.add(measurement);
        _status = "Measurement captured at ${now.toLocal()}";
      });
    }
  }

  // Stoppt das Tracking und speichert die Messungen als GPX-Datei.
  Future<void> _stopTrackingAndSave() async {
    _locationTimer?.cancel();
    await _positionSub?.cancel();
    await _barometerSub?.cancel();
    setState(() {
      _isTracking = false;
      _status = "Tracking stopped";
    });
    await _saveGPXFile();
  }

  // Speichert die gesammelten Messungen als GPX-Datei in einem eigenen Ordner mit Zeitstempel.
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
      final now = DateTime.now();
      final folderName = "Tracking_${now.millisecondsSinceEpoch}";
      final newFolder = Directory('$path/$folderName');
      await newFolder.create();
      final timestamp = now.toIso8601String().replaceAll(':', '-');
      final file = File('${newFolder.path}/tracking_data_$timestamp.gpx');
      await file.writeAsString(gpxBuffer.toString());
      setState(() {
        _status = "GPX file saved: ${file.path}";
      });
    } catch (e) {
      setState(() {
        _status = "Error saving GPX file: $e";
      });
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _positionSub?.cancel();
    _barometerSub?.cancel();
    super.dispose();
  }

  /// Erstellt eine Liste von FlSpot (x,y) für den Graphen.
  /// Hier nutzen wir den Index als x-Achsen-Wert und die GPS-Höhe als y-Achse.
  List<FlSpot> _createGraphSpots() {
    List<FlSpot> spots = [];
    for (int i = 0; i < _measurements.length; i++) {
      // Nutze den Index als x-Koordinate; oder berechne z. B. Sekunden seit Beginn.
      spots.add(FlSpot(i.toDouble(), _measurements[i].gpsAltitude));
    }
    return spots;
  }

  // Einfache Graph-Darstellung: Zeigt den Verlauf der GPS-Höhe.
  Widget _buildGraph() {
    final spots = _createGraphSpots();
    // Falls keine Daten vorliegen, gib eine Platzhalteranzeige:
    if (spots.isEmpty) {
      return Center(child: Text("Keine Graph-Daten vorhanden."));
    }
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: SizedBox(
        height: 300,
        child: LineChart(
          LineChartData(
            // minimale und maximale Werte können dynamisch gesetzt werden:
            minX: 0,
            maxX: spots.last.x,
            minY: spots.map((s) => s.y).reduce(min) - 5,
            maxY: spots.map((s) => s.y).reduce(max) + 5,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                barWidth: 3,
                dotData: FlDotData(show: false),
              ),
            ],
            gridData: FlGridData(show: true),
            titlesData: FlTitlesData(show: true),
            borderData: FlBorderData(show: true),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _currentPosition;
    return Scaffold(
      appBar: AppBar(title: const Text('Tracking App with GPX Export')),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Aktuelle Messung
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: pos != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Current Measurement:',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Time: ${DateTime.now().toLocal()}'),
                        Text('Latitude: ${pos.latitude.toStringAsFixed(6)}'),
                        Text('Longitude: ${pos.longitude.toStringAsFixed(6)}'),
                        Text(
                            'GPS Altitude: ${pos.altitude.toStringAsFixed(1)} m'),
                        if (_relativeAltitude != null)
                          Text(
                              'Barometer Altitude: ${_relativeAltitude!.toStringAsFixed(1)} m'),
                        const SizedBox(height: 10),
                        Text(_status,
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(_status),
                    ),
            ),
            const Divider(),
            // Graph anzeigen
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Graph (GPS Altitude over Time):',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            _buildGraph(),
            const Divider(),
            // Collected Measurements: Wir packen die DataTable in einen scrollbaren Container in beiden Richtungen.
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('Collected Measurements:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            // Zwei ScrollViews: zuerst horizontal, dann vertikal
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Time')),
                    DataColumn(label: Text('Latitude')),
                    DataColumn(label: Text('Longitude')),
                    DataColumn(label: Text('GPS Altitude (m)')),
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
            const Divider(),
            // Steuerungsbuttons
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _isTracking ? null : _startTracking,
                    child: const Text("Start"),
                  ),
                  ElevatedButton(
                    onPressed: _isTracking ? _stopTrackingAndSave : null,
                    child: const Text("Stop & Save"),
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
