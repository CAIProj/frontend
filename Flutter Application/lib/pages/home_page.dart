import 'dart:async';
import 'dart:math';
import 'package:provider/provider.dart';
import 'package:tracking_app/functional/graph.dart';
import 'package:tracking_app/domain/measurement.dart';
import 'package:tracking_app/functional/notification.dart' as n;
import 'package:tracking_app/pages/tracks_page.dart';
import 'package:tracking_app/services/gpx_handler.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

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

  GpxHandler _gpxHandler = GpxHandler();

  /* ---------- LIFECYCLE ---------------------------------------------- */
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLocationPermission();

    context.read<n.NotificationController>().initOverlay(context);
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

  void _doTrack() {
    _gpsTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _capturePosition());

    _baroSub = barometerEventStream(samplingPeriod: Duration(seconds: 1))
        .listen((BarometerEvent e) {
      const p0 = 1013.25;
      final alt = (44330 * (1 - pow(e.pressure / p0, 0.1903))).toDouble();
      setState(() => _baroAlt = alt);
    });
  }

  void _start() {
    _doTrack();
    setState(() {
      _tracking = true;
      _status = 'Tracking in progress...';
      _meas.clear();
    });
  }

  void _pauseTracking() {
    _gpsTimer?.cancel();
    _baroSub?.cancel();
    setState(() => _status = 'Tracking paused');
  }

  void _resumeTracking() {
    _doTrack();
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

    final file = await _gpxHandler.saveMeasurementsToGpxFile(
        'Altitude Tracking Data', _meas);
    setState(() => _status = 'Saved: ${file.path}');
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
    n.NotificationController _popUpController =
        context.read<n.NotificationController>();
    return AppBar(
      title: const Text('TrackIN'),
      actions: [
        // All recordings button
        IconButton(
          icon: const Icon(Icons.list),
          tooltip: 'All Recordings',
          onPressed: !_tracking
              ? () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => TracksPage()))
              : null,
        ),
        // Load GPX file button
        IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Load GPX file',
            onPressed: () async {
              if (!_tracking) {
                final (success, error) = await _gpxHandler.importGpxFile();
                if (success) {
                  _popUpController.addNotification(n.Notification(
                      type: n.NotificationType.Success,
                      text: 'Imported GPX File'));
                } else {
                  _popUpController.addNotification(n.Notification(
                      type: n.NotificationType.Error,
                      text: error ?? 'Unknown Error'));
                }
              }
            }),
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
                        Text('Current Status',
                            style: Theme.of(context).textTheme.titleMedium),
                        _tracking ? _buildStatusIndicator() : Container(),
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
            Expanded(flex: 2, child: TrackGraph(measurements: _meas)),

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

  Widget _buildBottomAppBar() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Start tracking button - disabled during tracking or when viewing a loaded file
            ElevatedButton.icon(
              onPressed: (!_tracking) ? _start : null,
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
          ],
        ),
      ),
    );
  }
}
