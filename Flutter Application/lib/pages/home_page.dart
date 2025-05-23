import 'dart:async';
import 'dart:math';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:tracking_app/functional/graph.dart';
import 'package:tracking_app/domain/measurement.dart';
import 'package:tracking_app/functional/notification.dart' as n;
import 'package:tracking_app/functional/utils.dart';
import 'package:tracking_app/pages/tracks_page.dart';
import 'package:tracking_app/services/gpx_handler.dart';
import 'package:tracking_app/constants/app_constants.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/* ======================== STATEFUL HOME =============================== */

enum TrackingStatus { TRACKING, PAUSED, STOPPED }

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
  TrackingStatus _trackingStatus = TrackingStatus.STOPPED;
  Position? _currentPosition;
  final _maxPoints = 1000; // Maximum points to store for memory optimization

  bool _permissionsEnabled = false;

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
      if (_trackingStatus == TrackingStatus.TRACKING) {
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
      _showLocationDialog();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showPermissionSettingsDialog();
      return;
    }

    // Get position once to show initial coordinates
    _capturePosition();

    setState(() {
      _permissionsEnabled = true;
    });
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

    setState(() {
      _trackingStatus = TrackingStatus.TRACKING;
    });
    _baroSub = barometerEventStream(samplingPeriod: Duration(seconds: 1))
        .listen((BarometerEvent e) {
      const p0 = 1013.25;
      final alt = (44330 * (1 - pow(e.pressure / p0, 0.1903))).toDouble();
      setState(() {
        _baroAlt = alt;
      });
    });
  }

  void _start() {
    _doTrack();
    setState(() {
      _meas.clear();
    });
  }

  void _pauseTracking() {
    setState(() {
      _trackingStatus = TrackingStatus.PAUSED;
    });
    _gpsTimer?.cancel();
    _baroSub?.cancel();

    context.read<n.NotificationController>().addNotification(n.Notification(
        type: n.NotificationType.General, text: 'Tracking paused'));
  }

  void _resumeTracking() {
    _doTrack();
    context.read<n.NotificationController>().addNotification(n.Notification(
        type: n.NotificationType.General, text: 'Tracking resumed'));
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
      });

      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 72,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } on Exception catch (e) {
      context.read<n.NotificationController>().addNotification(n.Notification(
          type: n.NotificationType.Error, text: 'GPS error: $e'));
    }
  }

  Future<void> _stopAndSave() async {
    final _notificationController = context.read<n.NotificationController>();

    // Properly cancel all tracking services
    _gpsTimer?.cancel();
    _gpsTimer = null;
    _baroSub?.cancel();
    _baroSub = null;

    setState(() {
      _trackingStatus = TrackingStatus.STOPPED;
    });

    if (_meas.isEmpty) {
      _notificationController.addNotification(n.Notification(
          type: n.NotificationType.Error,
          text: 'No tracking data available to export'));
      return;
    }

    await _gpxHandler.saveMeasurementsToGpxFile(
        'Altitude Tracking Data', _meas);
    _notificationController.addNotification(n.Notification(
        type: n.NotificationType.Success, text: 'Stopped and saved track'));
  }

  /* ---------- UI HELPER WIDGETS -------------------------------------- */
  Widget _buildStatusIndicator() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: _trackingStatus == TrackingStatus.TRACKING
            ? Colors.green
            : Colors.red,
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
      elevation: 0,
      foregroundColor: AppConstants.primaryTextColor,
      centerTitle: true,
      flexibleSpace: Container(
        decoration: BoxDecoration(gradient: AppConstants.appBarGradient),
      ),
      title: Text('TrackIN',
          style: TextStyle(color: AppConstants.primaryTextColor)),
      actions: [
        // All recordings button
        IconButton(
          icon: const Icon(Icons.list),
          tooltip: 'All Recordings',
          onPressed: _trackingStatus == TrackingStatus.STOPPED
              ? () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => TracksPage()))
              : null,
        ),
        // Load GPX file button
        IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Load GPX file',
            onPressed: _trackingStatus == TrackingStatus.STOPPED
                ? () async {
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
                : null),
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
      body: Container(
        decoration: BoxDecoration(gradient: AppConstants.appBodyGradient),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: PageView(
              scrollDirection: Axis.horizontal,
              children: [
                trackOverview(),
                trackDetailed(),
              ],
            ),
          ),
        ),
      ),
      // bottomNavigationBar: _buildBottomAppBar(),
    );
  }

  Widget trackOverview() {
    return Column(
      children: [
        Expanded(
          flex: 5,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Spacer(flex: 25),
                  Expanded(
                    flex: 50,
                    child: Column(
                      children: [
                        TimeWidget(
                          trackingStatus: _trackingStatus,
                        ),
                        SplashTextWidget(trackingStatus: _trackingStatus),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 25,
                    child: StatisticsWidget(
                      measurements: _meas,
                      trackingStatus: _trackingStatus,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
        Spacer(flex: 2),
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _permissionsEnabled
                  ? StartRecordingWidget(
                      trackingStatus: _trackingStatus,
                      onTap: () {
                        if (_trackingStatus == TrackingStatus.TRACKING) {
                          _pauseTracking();
                        } else if (_trackingStatus == TrackingStatus.PAUSED) {
                          _resumeTracking();
                        }
                      },
                      onLongHold: () {
                        if (_trackingStatus != TrackingStatus.TRACKING) {
                          _start();
                        } else {
                          _stopAndSave();
                        }
                      },
                    )
                  : TextButton(
                      onPressed: () {
                        _checkLocationPermission();
                      },
                      child: Text(
                        'Please allow permissions for location access',
                        style: TextStyle(
                          fontSize: AppConstants.textSizeM,
                          color: AppConstants.error,
                        ),
                      ),
                    )
            ],
          ),
        ),
      ],
    );
  }

  // TEMP, WILL MERGE THE TWO INTO A MORE SUITABLE FORMAT

  Widget trackDetailed() {
    return Column(
      children: [
        // Current status/file info card
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
    );
  }
}

class SplashTextWidget extends StatefulWidget {
  final TrackingStatus trackingStatus;

  SplashTextWidget({required this.trackingStatus});

  @override
  _SplashTextState createState() => _SplashTextState();
}

class _SplashTextState extends State<SplashTextWidget> {
  String _getGreetingText() {
    final hour = DateTime.now().hour;

    if (hour >= 3 && hour < 12) {
      return 'Good Morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 400),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: Text(
        widget.trackingStatus == TrackingStatus.STOPPED
            ? _getGreetingText()
            : 'mm:ss',
        key: ValueKey<bool>(widget.trackingStatus == TrackingStatus.STOPPED),
        style: TextStyle(
          color: AppConstants.primaryTextColor,
          fontSize: AppConstants.textSizeL,
        ),
      ),
    );
  }
}

class TimeWidget extends StatefulWidget {
  final TrackingStatus trackingStatus;

  TimeWidget({required this.trackingStatus});

  @override
  _TimeWidgetState createState() => _TimeWidgetState();
}

class _TimeWidgetState extends State<TimeWidget> {
  late Timer _timer;
  late Ticker _ticker;

  late String _clockString;
  late String _stopwatchString;

  Duration accumulatedElapsed = Duration.zero;
  Duration elapsedBeforePause = Duration.zero;

  @override
  void initState() {
    super.initState();
    _clockString = _getClockString();
    _stopwatchString = _getStopwatchString();

    _timer = Timer.periodic(Duration(seconds: 1), (Timer t) {
      setState(() {
        _clockString = _getClockString();
      });
    });
    _ticker = Ticker(
      (elapsed) {
        setState(() {
          _stopwatchString = _getStopwatchString();
          elapsedBeforePause = elapsed;
        });
      },
    );
  }

  String _getClockString() {
    return DateFormat('HH:mm').format(DateTime.now());
  }

  String _getStopwatchString() {
    return '${((accumulatedElapsed.inSeconds + elapsedBeforePause.inSeconds) ~/ 60).toString().padLeft(2, '0')}:${((accumulatedElapsed.inSeconds + elapsedBeforePause.inSeconds) % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer.cancel();
    _ticker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.trackingStatus == TrackingStatus.TRACKING) {
      if (!_ticker.isActive) {
        _ticker.start();
      }
    } else if (widget.trackingStatus == TrackingStatus.PAUSED) {
      accumulatedElapsed += elapsedBeforePause;
      if (_ticker.isActive) {
        elapsedBeforePause = Duration.zero;
        _ticker.stop();
      }
    } else {
      accumulatedElapsed = Duration.zero;
      elapsedBeforePause = Duration.zero;
      if (_ticker.isActive) {
        _ticker.stop();
      }
    }

    return AnimatedSwitcher(
      duration: Duration(milliseconds: 400),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: Text(
        widget.trackingStatus == TrackingStatus.STOPPED
            ? _clockString
            : _stopwatchString,
        key: ValueKey<bool>(widget.trackingStatus == TrackingStatus.STOPPED),
        style: TextStyle(
          color: AppConstants.primaryTextColor,
          fontSize: AppConstants.textSizeXXL,
        ),
      ),
    );
  }
}

class StartRecordingWidget extends StatefulWidget {
  final Function onTap;
  final Function onLongHold;
  final TrackingStatus trackingStatus;

  StartRecordingWidget(
      {Key? key,
      required this.onTap,
      required this.onLongHold,
      required this.trackingStatus})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _StartRecordingState();
}

class _StartRecordingState extends State<StartRecordingWidget>
    with TickerProviderStateMixin {
  late Ticker _timeTicker;

  int _ringCount = 3;
  int _timeOffset = 1000;
  double _heldSizeOffset = 5;
  late double _size = 30.0 * _ringCount;

  double _heldOpacity = 1.0;

  bool _nextReleaseIsLongHold = false;

  final ValueNotifier<int> _timeNotifier = ValueNotifier(0);
  final ValueNotifier<(bool, int)> _isHeldNotifier = ValueNotifier((false, 0));
  late final ValueNotifier<List<double>> _currentSizeNotifier =
      ValueNotifier(List.filled(_ringCount, 0));

  @override
  void initState() {
    super.initState();

    _timeTicker = Ticker((elapsed) {
      setState(() {
        _timeNotifier.value = elapsed.inMilliseconds;
      });
    })
      ..start();
  }

  @override
  void dispose() {
    _timeTicker.dispose();
    _timeNotifier.dispose();
    _isHeldNotifier.dispose();
    _currentSizeNotifier.dispose();
    super.dispose();
  }

  String getText() {
    switch (widget.trackingStatus) {
      case TrackingStatus.STOPPED:
        return 'Tap and hold to start recording';
      case TrackingStatus.TRACKING:
        return 'Tap to pause, tap and hold to stop recording';
      case TrackingStatus.PAUSED:
        return 'Tap to resume tracking, tap and hold to stop recording';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isHeldNotifier.value.$1) {
      _heldOpacity = 0.0;
    } else {
      _heldOpacity = 1.0;
    }

    return Column(
      children: [
        GestureDetector(
          onTapDown: (_) {
            _isHeldNotifier.value = (true, DateTime.now().millisecond);
          },
          onTapUp: (_) {
            _isHeldNotifier.value = (false, 0);
            if (_nextReleaseIsLongHold) {
              widget.onLongHold();
              _nextReleaseIsLongHold = false;
            } else {
              widget.onTap();
            }
          },
          child: SizedBox(
            height: _size,
            child: Stack(
              alignment: Alignment.center,
              children: List.generate(
                _ringCount,
                (index) {
                  return Positioned(
                    top: 0,
                    child: PulsingRingWidget(
                      key: Key(index.toString()),
                      index: index,
                      tickerTime: _timeNotifier,
                      isHeldNotifier: _isHeldNotifier,
                      onLongHold: () {
                        if (!_nextReleaseIsLongHold) {
                          HapticFeedback.mediumImpact();
                        }
                        _nextReleaseIsLongHold = true;
                      },
                      sizeNotifier: _currentSizeNotifier,
                      timeOffset: _timeOffset,
                      heldSizeOffset: _heldSizeOffset,
                      velocity: _size / _ringCount,
                      size: _size,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        SizedBox(height: 12),
        AnimatedOpacity(
          opacity: _heldOpacity,
          duration: Duration(milliseconds: 400),
          key: ValueKey<bool>(widget.trackingStatus == TrackingStatus.STOPPED),
          child: Text(
            getText(),
            style: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
        )
      ],
    );
  }
}

class PulsingRingWidget extends StatefulWidget {
  final int index;
  final ValueNotifier<int> tickerTime;
  final ValueNotifier<(bool, int)> isHeldNotifier;
  final Function onLongHold;
  final ValueNotifier<List<double>> sizeNotifier;
  final int timeOffset;
  final double heldSizeOffset;
  final double size;

  final double velocity;

  PulsingRingWidget({
    Key? key,
    required this.index,
    required this.tickerTime,
    required this.isHeldNotifier,
    required this.onLongHold,
    required this.sizeNotifier,
    required this.timeOffset,
    required this.heldSizeOffset,
    required this.size,
    required this.velocity,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PulsingRingState();
}

class _PulsingRingState extends State<PulsingRingWidget>
    with TickerProviderStateMixin {
  bool wasPreviouslyHeld = false;

  double currentAcceleration = 0.0;
  double currentVelocity = 0.0;

  // Map of current indexes to index by size when it was held
  Map<int, int>? indexesWhenHeld;
  int? indexWhenHeld;
  late double maxSize = widget.size;

  // Initialized this way to simulate delay
  late int previousTimestamp = widget.timeOffset * widget.index;

  @override
  void initState() {
    super.initState();
    currentVelocity = widget.velocity;

    widget.isHeldNotifier.addListener(() {
      final (isHeld, timeHeld) = widget.isHeldNotifier.value;
      if (!isHeld) {
        maxSize = widget.size;
        // If previously held (aka released), give a burst of velocity
        if (wasPreviouslyHeld) {
          double factor = ((indexesWhenHeld?[indexWhenHeld] ?? 0) + 1);
          currentVelocity += 300 * 0.7 * factor;
          currentAcceleration = 0;
        } else {
          // If released but not long enough
          currentVelocity += 50;
          currentAcceleration = 0;
        }
      } else {
        // Give some room for expansion
        maxSize = widget.size * 1.5;

        currentVelocity += 50;
        currentAcceleration = -250;
      }

      wasPreviouslyHeld = isHeld;
    });
  }

  int getIndexBySize() {
    // Reverse indexBySizeToIndex to indexToindexBySize
    // Cannot do a simple find since that doesn't handle same values
    return Map.fromEntries(getIndexBySizeToIndex()
        .entries
        .map((e) => MapEntry(e.value, e.key)))[widget.index]!;
  }

  Map<int, int> getIndexBySizeToIndex() {
    // Sorted ascending
    var map = [...widget.sizeNotifier.value].asMap();
    List<int> indexes = Map.fromEntries(
            map.entries.toList()..sort((a, b) => a.value.compareTo(b.value)))
        .keys
        .toList();

    return indexes.asMap();
  }

  @override
  Widget build(BuildContext context) {
    final deltaSecs =
        max((widget.tickerTime.value - previousTimestamp) / 1000, 0);

    if (widget.tickerTime.value > previousTimestamp) {
      previousTimestamp = widget.tickerTime.value;
    }
    final (isHeld, timeHeld) = widget.isHeldNotifier.value;

    currentVelocity += currentAcceleration * deltaSecs;

    // If not held, size should loop back
    if (!isHeld) {
      // If rings are too close to one another, make them want to seperate, like magnets
      if (indexWhenHeld != null) {
        double resultantForce = 0.0;
        widget.sizeNotifier.value.asMap().forEach((index, x) {
          if (index != widget.index) {
            double thisComparisonSize = widget.sizeNotifier.value[widget.index];
            double sizeDiff = thisComparisonSize - x;

            double aimedSizeDiff = widget.timeOffset * (widget.velocity / 1000);

            // Only care if it is too close (repulsive, not attractive)
            double diff = sizeDiff.abs() < aimedSizeDiff
                ? sizeDiff.sign * pow((aimedSizeDiff - sizeDiff), 0.7)
                : 0;
            resultantForce += diff;
          }
        });

        currentVelocity += resultantForce * 0.1;
      }

      // When released but not held long
      // If not held, and velocity is not equal to widget.velocity, it should be easing into widget.velocity
      if (currentVelocity != widget.velocity) {
        // Velocity easing into supposed velocity (like drag)
        final differenceVelocity = widget.velocity - currentVelocity;
        currentVelocity += differenceVelocity * 0.08;
      }

      widget.sizeNotifier.value[widget.index] =
          (widget.sizeNotifier.value[widget.index] +
                  deltaSecs * currentVelocity) %
              maxSize;
    }
    // If held, size should lock when reducing
    else {
      // Minimum size offset should be based on order of current sizes
      indexWhenHeld = getIndexBySize();
      indexesWhenHeld = getIndexBySizeToIndex();

      final minimumSize = 2 + widget.heldSizeOffset * indexWhenHeld!;

      widget.sizeNotifier.value[widget.index] = max(
          (widget.sizeNotifier.value[widget.index] +
                  deltaSecs * currentVelocity) %
              maxSize,
          minimumSize);

      // Min reached? Stop all movement (will overflow if held for too long)
      // Also holding for this long fires onLongHold
      if (widget.sizeNotifier.value[widget.index] <= minimumSize &&
          currentAcceleration != 0.0 &&
          currentVelocity != 0.0) {
        currentVelocity = 0.0;
        currentAcceleration = 0.0;
        widget.onLongHold();
      }
    }
    wasPreviouslyHeld = isHeld;

    final opacityCurve = Curves.easeIn
        .transform(widget.sizeNotifier.value[widget.index] / maxSize);

    final borderCurve = Curves.easeOutQuart
        .transform(widget.sizeNotifier.value[widget.index] / maxSize);

    return Container(
      height: widget.size,
      width: widget.size,
      clipBehavior: Clip.none,
      child: Center(
        child: Opacity(
          opacity: 1 - opacityCurve,
          child: OverflowBox(
            maxHeight: double.infinity,
            maxWidth: double.infinity,
            child: Container(
              width: widget.sizeNotifier.value[widget.index],
              height: widget.sizeNotifier.value[widget.index],
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppConstants.primaryTextColor,
                  width: 3 * borderCurve,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatisticsWidget extends StatefulWidget {
  final List<Measurement> measurements;
  final TrackingStatus trackingStatus;

  StatisticsWidget({required this.measurements, required this.trackingStatus});

  @override
  _StatisticsState createState() => _StatisticsState();
}

class _StatisticsState extends State<StatisticsWidget> {
  double _opacity = 0.0;

  String _getDistanceString() {
    final distances = get_distances(widget.measurements);

    final double td = distances.isEmpty ? 0.0 : distances.last;
    if (td < 1) {
      // Show in meters
      return '${(td * 1000).toString().padLeft(1, '0')} m';
    }
    // Else in km
    return '${td.toString().padLeft(1, '0')} km';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.trackingStatus == TrackingStatus.STOPPED) {
      _opacity = 0.0;
    } else {
      _opacity = 1.0;
    }
    return AnimatedOpacity(
      opacity: _opacity,
      duration: Duration(milliseconds: 400),
      child: Column(
        children: [
          // Total distance
          Text(
            '${_getDistanceString()}',
            style: TextStyle(
              fontSize: AppConstants.textSizeXL,
              color: AppConstants.primaryTextColor,
            ),
          ),
          // Current elevation
          Text(
            '${(widget.measurements.lastOrNull?.baroAlt ?? widget.measurements.lastOrNull?.gpsAlt ?? 0).toString()} m',
            style: TextStyle(
              fontSize: AppConstants.textSizeXL,
              color: AppConstants.primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
}
