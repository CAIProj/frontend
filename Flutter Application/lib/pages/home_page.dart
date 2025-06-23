import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:tracking_app/functional/graph.dart';
import 'package:tracking_app/domain/measurement.dart';
import 'package:tracking_app/services/notification_controller.dart' as n;
import 'package:tracking_app/functional/utils.dart';
import 'package:tracking_app/pages/account_page.dart';
import 'package:tracking_app/pages/tracks_page.dart';
import 'package:tracking_app/services/gpx_handler.dart';
import 'package:tracking_app/constants/app_constants.dart';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

/* ======================== STATEFUL HOME =============================== */

enum TrackingStatus { TRACKING, PAUSED, STOPPED }

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  /* ---------- STATE --------------------------------------------------- */
  TrackingStatus _trackingStatus = TrackingStatus.STOPPED;

  late LocationSettings _locationSettings;

  final _meas = <Measurement>[];
  Position? _gpsPosition;
  double? _baroAlt;

  Timer? _gpsTimer;
  StreamSubscription? _gpsSub;
  StreamSubscription? _baroSub;

  bool _permissionsEnabled = false;

  GpxHandler _gpxHandler = GpxHandler();
  PageController _pageViewController = PageController();

  late final n.NotificationController _notificationController =
      Provider.of<n.NotificationController>(context, listen: false);

  /* ---------- LIFECYCLE ---------------------------------------------- */
  @override
  void initState() {
    super.initState();
    _initLocationSettings();
    _checkLocationPermission();

    _notificationController.initOverlay(context);
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _gpsSub?.cancel();
    _baroSub?.cancel();
    _pageViewController.dispose();
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
    _getInitialPosition();

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

  void _initLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      _locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 5),
        //(Optional) Set foreground notification config to keep the app alive
        //when going to the background
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText:
              "TrackIN will continue to receive your location in the background",
          notificationTitle: "Running in background",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      _locationSettings = AppleSettings(
        accuracy: LocationAccuracy.best,
        activityType: ActivityType.fitness,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: true,
        // Only set to true if our app will be started up in the background.
        showBackgroundLocationIndicator: false,
      );
    } else if (kIsWeb) {
      _locationSettings = WebSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        maximumAge: Duration(seconds: 5),
      );
    } else {
      _locationSettings = LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      );
    }
  }

  void _doTrack() {
    setState(() {
      _trackingStatus = TrackingStatus.TRACKING;
    });

    _gpsTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _capturePosition());

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen((Position position) {
      setState(() {
        _gpsPosition = position;
      });
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

  void _startTracking() {
    _doTrack();
    setState(() {
      _meas.clear();
      _capturePosition();
    });
  }

  void _pauseTracking() {
    setState(() {
      _trackingStatus = TrackingStatus.PAUSED;
    });

    _gpsTimer?.cancel();
    _gpsSub?.cancel();
    _baroSub?.cancel();

    _notificationController.addNotification(n.Notification(
        type: n.NotificationType.General, text: 'Tracking paused'));
  }

  void _resumeTracking() {
    _doTrack();
    _notificationController.addNotification(n.Notification(
        type: n.NotificationType.General, text: 'Tracking resumed'));
  }

  Future<void> _getInitialPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: _locationSettings,
      );

      _gpsPosition = pos;
      ;
    } on Exception catch (e) {
      _notificationController.addNotification(n.Notification(
          type: n.NotificationType.Error, text: 'GPS error: $e'));
    }
  }

  Future<void> _capturePosition() async {
    try {
      if (_gpsPosition == null) return;
      setState(() {
        _meas.add(Measurement(
          DateTime.now(),
          _gpsPosition!.latitude,
          _gpsPosition!.longitude,
          _gpsPosition!.altitude,
          _baroAlt,
        ));
      });
    } on Exception catch (e) {
      _notificationController.addNotification(n.Notification(
          type: n.NotificationType.Error, text: 'GPS error: $e'));
    }
  }

  Future<void> _stopAndSave() async {
    // Properly cancel all tracking services
    _gpsTimer?.cancel();
    _gpsTimer = null;
    _gpsSub?.cancel();
    _gpsSub = null;
    _baroSub?.cancel();
    _baroSub = null;

    if (_meas.length <= 1) {
      _notificationController.addNotification(n.Notification(
          type: n.NotificationType.General,
          text: 'Stopped without saving data (too short)'));
    } else {
      await _gpxHandler.saveMeasurementsToGpxFile(
          'Altitude Tracking Data', _meas);
      _notificationController.addNotification(n.Notification(
          type: n.NotificationType.Success, text: 'Stopped and saved track'));
    }

    setState(() {
      _trackingStatus = TrackingStatus.STOPPED;
      _meas.clear();
    });
  }

  /* ---------- UI HELPER WIDGETS -------------------------------------- */

  AppBar _buildAppBar() {
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
        // Login / Account button
        IconButton(
          icon: const Icon(Icons.account_circle),
          tooltip: 'Account',
          onPressed: _trackingStatus == TrackingStatus.STOPPED
              ? () => Navigator.push(context,
                  MaterialPageRoute(builder: (context) => AccountPage()))
              : null,
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
              Text('• HOLD and RELEASE to begin tracking'),
              Text('• TAP to pause tracking'),
              Text(
                  '• HOLD and RELEASE again to stop and save the recorded track'),
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
            padding: EdgeInsets.symmetric(vertical: 16),
            child: TrackOverviewWidget(
              permissionsEnabled: _permissionsEnabled,
              checkLocationPermission: _checkLocationPermission,
              measurements: _meas,
              trackingStatus: _trackingStatus,
              startTracking: _startTracking,
              pauseTracking: _pauseTracking,
              resumeTracking: _resumeTracking,
              stopAndSaveTracking: _stopAndSave,
              pageViewController: _pageViewController,
            ),
          ),
        ),
      ),
    );
  }
}

class TrackDetailedWidget extends StatefulWidget {
  final List<Measurement> measurements;

  TrackDetailedWidget({required this.measurements});
  @override
  _TrackDetailedState createState() => _TrackDetailedState();
}

class _TrackDetailedState extends State<TrackDetailedWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _scroll = ScrollController();
  int oldMeasurementLength = 0;

  Widget _buildCoordinatesDisplay() {
    if (widget.measurements.isEmpty) {
      return Text(
        'No location data available',
        style: TextStyle(
            fontSize: AppConstants.textSizeM,
            color: AppConstants.primaryTextColor),
      );
    }

    final pos = widget.measurements.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Latitude: ${pos.lat.toStringAsFixed(6)}°',
          style: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor),
        ),
        Text(
          'Longitude: ${pos.lon.toStringAsFixed(6)}°',
          style: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                'GPS Alt: ${pos.gpsAlt.toStringAsFixed(1)} m',
                style: TextStyle(
                    fontSize: AppConstants.textSizeM,
                    color: AppConstants.primaryTextColor),
              ),
            ),
            Expanded(
              child: Text(
                pos.baroAlt != null
                    ? 'Baro Alt: ${pos.baroAlt!.toStringAsFixed(1)} m'
                    : 'n/a',
                style: TextStyle(
                    fontSize: AppConstants.textSizeM,
                    color: AppConstants.primaryTextColor),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMeasurementsList() {
    if (widget.measurements.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'No measurements yet',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
        ),
      );
    }
    // Show only the last 100 points
    final truncatedMeasurements = widget.measurements.length > 100
        ? widget.measurements.sublist(widget.measurements.length - 100)
        : widget.measurements;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Tracking Data (${widget.measurements.length} points)',
            style: TextStyle(
              fontSize: AppConstants.textSizeL,
              color: AppConstants.primaryTextColor,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: truncatedMeasurements.length,
            itemBuilder: (_, i) {
              final m = truncatedMeasurements[i];
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                      '${widget.measurements.length - truncatedMeasurements.length + i + 1}'),
                ),
                title: Text(
                  '${m.lat.toStringAsFixed(6)}, ${m.lon.toStringAsFixed(6)}',
                  style: TextStyle(
                      fontSize: AppConstants.textSizeM,
                      color: AppConstants.primaryTextColor),
                ),
                subtitle: Text(
                  'Alt: ${m.gpsAlt.toStringAsFixed(1)}m | Baro: ${m.baroAlt?.toStringAsFixed(1) ?? 'n/a'}m',
                  style: TextStyle(
                      fontSize: AppConstants.textSizeM,
                      color: AppConstants.primaryTextColor),
                ),
                trailing: Text(
                  TimeOfDay.fromDateTime(m.t).format(context),
                  style: TextStyle(
                      fontSize: AppConstants.textSizeM,
                      color: AppConstants.primaryTextColor),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (oldMeasurementLength < widget.measurements.length) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 72,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      oldMeasurementLength = widget.measurements.length;
    }

    return ListView(
      children: [
        // Current status/file info card
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: AppConstants.primaryBackgroundColor,
            borderRadius: BorderRadius.circular(10),
          ),
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
        SizedBox(
          height: 400,
          child: TrackGraph(measurements: widget.measurements),
        ),

        // Tracking table
        SizedBox(
          height: 300,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: AppConstants.primaryBackgroundColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: _buildMeasurementsList(),
          ),
        ),
      ],
    );
  }
}

class TrackOverviewWidget extends StatefulWidget {
  final bool permissionsEnabled;
  final Function checkLocationPermission;
  final List<Measurement> measurements;
  final TrackingStatus trackingStatus;
  final Function startTracking;
  final Function pauseTracking;
  final Function resumeTracking;
  final Function stopAndSaveTracking;
  final PageController pageViewController;

  TrackOverviewWidget({
    required this.permissionsEnabled,
    required this.checkLocationPermission,
    required this.measurements,
    required this.trackingStatus,
    required this.startTracking,
    required this.pauseTracking,
    required this.resumeTracking,
    required this.stopAndSaveTracking,
    required this.pageViewController,
  });

  @override
  _TrackOverviewState createState() => _TrackOverviewState();
}

class _TrackOverviewState extends State<TrackOverviewWidget> {
  PageController _pageViewController = PageController();

  @override
  void dispose() {
    _pageViewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _pageViewController,
            children: [
              Column(
                children: [
                  Expanded(
                    flex: 50,
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
                                    trackingStatus: widget.trackingStatus,
                                  ),
                                  SplashTextWidget(
                                      trackingStatus: widget.trackingStatus),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 25,
                              child: StatisticsWidget(
                                measurements: widget.measurements,
                                trackingStatus: widget.trackingStatus,
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  Spacer(flex: 20),
                  Expanded(
                    flex: 30,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        widget.permissionsEnabled
                            ? StartRecordingWidget(
                                trackingStatus: widget.trackingStatus,
                                onTap: () {
                                  if (widget.trackingStatus ==
                                      TrackingStatus.TRACKING) {
                                    widget.pauseTracking();
                                  } else if (widget.trackingStatus ==
                                      TrackingStatus.PAUSED) {
                                    widget.resumeTracking();
                                  }
                                },
                                onLongHold: () {
                                  if (widget.trackingStatus ==
                                      TrackingStatus.STOPPED) {
                                    widget.startTracking();
                                  } else {
                                    widget.stopAndSaveTracking();
                                  }
                                },
                              )
                            : TextButton(
                                onPressed: () {
                                  widget.checkLocationPermission();
                                },
                                child: Text(
                                  'Please allow permissions for location access',
                                  style: TextStyle(
                                    fontSize: AppConstants.textSizeM,
                                    color: AppConstants.error,
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
              TrackDetailedWidget(measurements: widget.measurements)
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: SmoothPageIndicator(
            controller: _pageViewController,
            count: 2,
            effect: WormEffect(
              dotHeight: 10,
              dotWidth: 10,
              activeDotColor: AppConstants.primaryTextColor,
            ),
          ),
        )
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

class _TimeWidgetState extends State<TimeWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

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

  @override
  void dispose() {
    _timer.cancel();
    _ticker.stop();
    super.dispose();
  }

  String _getClockString() {
    return DateFormat('HH:mm').format(DateTime.now());
  }

  String _getStopwatchString() {
    return '${((accumulatedElapsed.inSeconds + elapsedBeforePause.inSeconds) ~/ 60).toString().padLeft(2, '0')}:${((accumulatedElapsed.inSeconds + elapsedBeforePause.inSeconds) % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
  late double _size = 40.0 * _ringCount;

  double _heldOpacity = 1.0;

  bool _nextReleaseIsLongHold = false;

  final ValueNotifier<int> _timeNotifier = ValueNotifier(0);
  // isHeld, timeHeld, isHoldCancelled
  final ValueNotifier<(bool, int, bool)> _isHeldNotifier =
      ValueNotifier((false, 0, false));
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
            _isHeldNotifier.value = (true, DateTime.now().millisecond, false);
          },
          onTapUp: (_) {
            _isHeldNotifier.value = (false, 0, false);
            if (_nextReleaseIsLongHold) {
              widget.onLongHold();
              _nextReleaseIsLongHold = false;
            } else {
              widget.onTap();
            }
          },
          onTapCancel: () {
            _isHeldNotifier.value = (false, 0, true);
            _nextReleaseIsLongHold = false;
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
                      trackingStatus: widget.trackingStatus,
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
  final TrackingStatus trackingStatus;
  final int index;
  final ValueNotifier<int> tickerTime;
  final ValueNotifier<(bool, int, bool)> isHeldNotifier;
  final Function onLongHold;
  final ValueNotifier<List<double>> sizeNotifier;
  final int timeOffset;
  final double heldSizeOffset;
  final double size;

  final double velocity;

  PulsingRingWidget({
    Key? key,
    required this.trackingStatus,
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
      final (isHeld, timeHeld, isHoldCancelled) = widget.isHeldNotifier.value;
      if (!isHeld) {
        maxSize = widget.size;
        // If previously held (aka released)
        if (wasPreviouslyHeld) {
          // and not cancelled, give a burst of velocity
          if (!isHoldCancelled) {
            double factor = ((indexesWhenHeld?[indexWhenHeld] ?? 0) + 1);
            currentVelocity += 300 * 0.7 * factor;
            currentAcceleration = 0;
          } else {
            // Else reset
            currentVelocity = widget.velocity;
            currentAcceleration = 0;
          }
        } else {
          // If released but not long enough
          currentVelocity += 50;
          currentAcceleration = 0;
        }
      } else {
        // Give some room for expansion
        maxSize = widget.size * 1.5;

        currentVelocity += 50;
        currentAcceleration = -400;
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
    final (isHeld, timeHeld, _) = widget.isHeldNotifier.value;

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

      final minimumSize =
          5 * (indexWhenHeld! + 1) + widget.heldSizeOffset * indexWhenHeld!;

      widget.sizeNotifier.value[widget.index] = max(
          (widget.sizeNotifier.value[widget.index] +
              deltaSecs * currentVelocity),
          minimumSize);

      // Min reached? Stop all movement (will overflow if held for too long)
      // Also holding for this long fires onLongHold
      if (widget.sizeNotifier.value[widget.index] <= minimumSize &&
          currentAcceleration != 0.0 &&
          currentVelocity != 0.0) {
        currentVelocity = 0.0;
        currentAcceleration = 0.0;
        // If largest when held
        if (indexWhenHeld! == widget.sizeNotifier.value.length - 1) {
          widget.onLongHold();
        }
      }
    }
    wasPreviouslyHeld = isHeld;

    final opacityCurve = Curves.easeIn.transform(
        (widget.sizeNotifier.value[widget.index] / maxSize).clamp(0.0, 1.0));

    final borderCurve = Curves.easeOutQuart.transform(
        (widget.sizeNotifier.value[widget.index] / maxSize).clamp(0.0, 1.0));

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
                  color: widget.trackingStatus == TrackingStatus.TRACKING
                      ? AppConstants.success
                      : AppConstants.primaryTextColor,
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
      return '${((td * 1000) * 10).truncate() / 10} m';
    }
    // Else in km
    return '${(td * 10).truncate() / 10} km';
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
            'Distance',
            style: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
          Text(
            '${_getDistanceString()}',
            style: TextStyle(
              fontSize: AppConstants.textSizeXL,
              color: AppConstants.primaryTextColor,
            ),
          ),
          // Current elevation
          Text(
            'Elevation',
            style: TextStyle(
              fontSize: AppConstants.textSizeM,
              color: AppConstants.primaryTextColor,
            ),
          ),
          Text(
            '${((widget.measurements.lastOrNull?.baroAlt ?? widget.measurements.lastOrNull?.gpsAlt ?? 0) * 10).truncate() / 10} m',
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
