import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracking_app/constants/app_constants.dart';
import 'package:tracking_app/functional/graph.dart';
import 'package:tracking_app/functional/pop_up_dialogue.dart';
import 'package:tracking_app/functional/utils.dart';
import 'package:tracking_app/domain/track_file.dart';
import 'package:tracking_app/pages/tracks_page.dart';
import 'package:tracking_app/services/framework_controller.dart';
import 'package:tracking_app/services/gpx_handler.dart';
import 'package:tracking_app/services/notification_controller.dart' as n;

class TrackPage extends StatefulWidget {
  final TrackFile trackFile;

  const TrackPage({super.key, required TrackFile this.trackFile});
  @override
  State<TrackPage> createState() => _TrackPageState(trackFile: trackFile);
}

class _TrackPageState extends State<TrackPage> {
  GpxHandler _gpxHandler = GpxHandler();
  TrackFile trackFile;
  bool wasUpdated = false;

  TextEditingController _editNameController = TextEditingController();
  FocusNode _editNameFocusNode = FocusNode();

  bool _isDoingFrameworkRequest = false;

  late final _notificationController =
      Provider.of<n.NotificationController>(context, listen: false);

  _TrackPageState({required TrackFile this.trackFile});
  @override
  void initState() {
    super.initState();
    _editNameController = TextEditingController(text: trackFile.displayName);
  }

  @override
  void dispose() {
    _editNameController.dispose();
    _editNameFocusNode.dispose();
    super.dispose();
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

  Future<void> triggerFileChange() async {
    // Reload file and set wasUpdated flag for parent
    TrackFile t = await _gpxHandler.loadGpxFile(trackFile.path);
    setState(() {
      trackFile = t;
    });

    wasUpdated = true;
  }

  void onUploadToServerClick(FrameworkController frameworkController,
      n.NotificationController notificationController) async {
    if (_isDoingFrameworkRequest) return;
    setState(() {
      _isDoingFrameworkRequest = true;
    });
    final uploadId = await frameworkController.uploadGPXFile(trackFile);

    if (uploadId != null) {
      notificationController.addNotification(n.Notification(
          type: n.NotificationType.Success,
          text: 'Uploaded with ID $uploadId'));
      await _gpxHandler.setFileUploadId(
        trackFile.path,
        uploadId,
      );

      triggerFileChange();
    }

    setState(() {
      _isDoingFrameworkRequest = false;
    });
  }

  void onDeleteFromServerClick(FrameworkController frameworkController,
      n.NotificationController notificationController) async {
    if (_isDoingFrameworkRequest) return;
    setState(() {
      _isDoingFrameworkRequest = true;
    });

    final success =
        await frameworkController.deleteGPXFile(trackFile.uploadedTrackId!);

    if (success) {
      notificationController.addNotification(n.Notification(
          type: n.NotificationType.Success,
          text:
              'Deleted file with ID ${trackFile.uploadedTrackId} from server'));
      await _gpxHandler.setFileUploadId(
        trackFile.path,
        null,
      );

      triggerFileChange();
    }

    setState(() {
      _isDoingFrameworkRequest = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final frameworkController =
        Provider.of<FrameworkController>(context, listen: true);

    final distances = get_distances(trackFile.measurements);
    final totalDistance = distances.isEmpty ? 0.0 : distances.last;
    final totalDuration = trackFile.measurements.last.t
        .difference(trackFile.measurements.first.t);
    final elevations =
        trackFile.measurements.map((m) => m.baroAlt ?? m.gpsAlt).toList();
    final minElevation = elevations.reduce(min);
    final maxElevation = elevations.reduce(max);
    final elevationGain = _calculateElevationGain(elevations);
    final hasBarometer =
        (trackFile.measurements.first.baroAlt != null).toString();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, TrackChange? result) {
        if (didPop) {
          return;
        }

        Navigator.pop(context, wasUpdated ? TrackChange.Edited : null);
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          foregroundColor: AppConstants.primaryTextColor,
          centerTitle: true,
          flexibleSpace: Container(
            decoration: BoxDecoration(gradient: AppConstants.appBarGradient),
          ),
          title: Container(
            width: MediaQuery.of(context).size.width * 0.6,
            child: TextField(
              textAlign: TextAlign.center,
              focusNode: _editNameFocusNode,
              controller: _editNameController,
              onSubmitted: (value) async {
                await GpxHandler().setGpxName(trackFile.path, value);
                triggerFileChange();
              },
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: trackFile.name == null || trackFile.name!.isEmpty
                    ? trackFile.displayName
                    : null,
              ),
              style:
                  TextStyle(fontSize: 22, color: AppConstants.primaryTextColor),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(gradient: AppConstants.appBodyGradient),
          child: Padding(
            padding: EdgeInsets.only(top: 12),
            child: ListView(
              children: [
                SizedBox(
                  height: 400,
                  child: TrackGraph(measurements: trackFile.measurements),
                ),
                SizedBox(height: 12),

                // Information
                Container(
                  margin: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryBackgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Container(
                      width: double.infinity,
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Date
                                Text(
                                    '${trackFile.date.day}.${trackFile.date.month}.${trackFile.date.year}, ${trackFile.date.hour}:${trackFile.date.minute}',
                                    style: TextStyle(
                                      fontSize: AppConstants.textSizeL,
                                      color: AppConstants.primaryTextColor,
                                    )),
                              ],
                            ),
                          ),
                          SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Stats
                              Expanded(
                                flex: 6,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TrackStatistic(
                                        icon: Icons.polyline_outlined,
                                        tooltip: 'Number of points',
                                        text: '${trackFile.pointCount} points'),
                                    TrackStatistic(
                                        icon: Icons.route_outlined,
                                        tooltip: 'Distance',
                                        text:
                                            '${totalDistance.toStringAsFixed(2)} km'),
                                    TrackStatistic(
                                        icon: Icons.schedule_outlined,
                                        tooltip: 'Duration',
                                        text:
                                            '${(totalDuration.inHours).toString().padLeft(2, '0')}h ${(totalDuration.inMinutes % 60).toString().padLeft(2, '0')}m ${(totalDuration.inSeconds % 60).toString().padLeft(2, '0')}s'),
                                    TrackStatistic(
                                        icon: Icons
                                            .vertical_align_bottom_outlined,
                                        tooltip: 'Minimum elevation',
                                        text:
                                            '${minElevation.toStringAsFixed(2)} m'),
                                    TrackStatistic(
                                        icon: Icons.vertical_align_top_outlined,
                                        tooltip: 'Maximum elevation',
                                        text:
                                            '${maxElevation.toStringAsFixed(2)} m'),
                                    TrackStatistic(
                                        icon: Icons.height_outlined,
                                        tooltip: 'Elevation range ',
                                        text:
                                            '${(maxElevation - minElevation).toStringAsFixed(2)} m'),
                                    TrackStatistic(
                                        icon: Icons.trending_up_outlined,
                                        tooltip: 'Total ascent',
                                        text:
                                            '${elevationGain.toStringAsFixed(2)} m'),
                                    TrackStatistic(
                                        icon: Icons.edgesensor_high_outlined,
                                        tooltip: 'Barometer',
                                        text:
                                            '${hasBarometer[0].toUpperCase() + hasBarometer.substring(1)}'),
                                  ],
                                ),
                              ),
                              // Actions
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    // Rename Button
                                    Container(
                                        width: double.infinity,
                                        margin:
                                            EdgeInsets.symmetric(horizontal: 8),
                                        child: TextButton(
                                            style:
                                                AppConstants.primaryButtonStyle,
                                            onPressed:
                                                _editNameFocusNode.requestFocus,
                                            child: Text(
                                              'Rename',
                                              style: TextStyle(
                                                fontSize:
                                                    AppConstants.textSizeM,
                                                color: AppConstants
                                                    .primaryTextColor,
                                              ),
                                            ))),
                                    SizedBox(height: 5),
                                    // Share Button
                                    Container(
                                        width: double.infinity,
                                        margin:
                                            EdgeInsets.symmetric(horizontal: 8),
                                        child: TextButton(
                                            style:
                                                AppConstants.primaryButtonStyle,
                                            onPressed: () {
                                              // Show share dialog
                                              Share.shareXFiles(
                                                [XFile(trackFile.path)],
                                                subject:
                                                    'Altitude Tracking Data (${trackFile.measurements.length} points)',
                                                text:
                                                    'Exported on ${DateTime.now().toLocal()}',
                                              );
                                            },
                                            child: Text(
                                              'Share',
                                              style: TextStyle(
                                                fontSize:
                                                    AppConstants.textSizeM,
                                                color: AppConstants
                                                    .primaryTextColor,
                                              ),
                                            ))),
                                    SizedBox(height: 5),
                                    // Upload Button
                                    Container(
                                        width: double.infinity,
                                        margin:
                                            EdgeInsets.symmetric(horizontal: 8),
                                        child: TextButton(
                                            style:
                                                AppConstants.primaryButtonStyle,
                                            onPressed: !frameworkController
                                                    .isLoggedIn
                                                // Do nothing if not logged in
                                                ? () {}
                                                : trackFile.uploadedTrackId ==
                                                        null
                                                    ? () => onUploadToServerClick(
                                                        frameworkController,
                                                        _notificationController)
                                                    : () => onDeleteFromServerClick(
                                                        frameworkController,
                                                        _notificationController),
                                            child: _isDoingFrameworkRequest
                                                ? CircularProgressIndicator(
                                                    color: AppConstants
                                                        .primaryTextColor)
                                                : Text(
                                                    !frameworkController
                                                            .isLoggedIn
                                                        ? 'Log in to upload'
                                                        : trackFile.uploadedTrackId ==
                                                                null
                                                            ? 'Upload'
                                                            : 'Delete from Server',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: AppConstants
                                                          .textSizeM,
                                                      color: AppConstants
                                                          .primaryTextColor,
                                                    ),
                                                  ))),
                                    SizedBox(height: 5),
                                    // Delete Button
                                    Container(
                                        width: double.infinity,
                                        margin:
                                            EdgeInsets.symmetric(horizontal: 8),
                                        child: TextButton(
                                            style:
                                                AppConstants.primaryButtonStyle,
                                            onPressed: () async {
                                              bool? result =
                                                  await showPopUpDialogue(
                                                      context,
                                                      'Delete track file',
                                                      'Are you sure you want to delete this file?',
                                                      {
                                                    'Delete': true,
                                                    'Cancel': false
                                                  });
                                              if (result == true) {
                                                _gpxHandler.deleteGpxFile(
                                                    trackFile.path);
                                                Navigator.pop(context,
                                                    TrackChange.Deleted);
                                              }
                                            },
                                            child: Text(
                                              'Delete',
                                              style: TextStyle(
                                                fontSize:
                                                    AppConstants.textSizeM,
                                                color: AppConstants
                                                    .primaryTextColor,
                                              ),
                                            )))
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TrackStatistic extends StatelessWidget {
  IconData icon;
  String text;
  String tooltip;

  TrackStatistic(
      {required IconData this.icon,
      required String this.text,
      required String this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Tooltip(
        message: tooltip,
        child: Row(
          children: [
            Icon(
              icon,
              color: AppConstants.primaryTextColor,
            ),
            SizedBox(
              width: 8,
            ),
            Text(
              text,
              style: TextStyle(
                fontSize: AppConstants.textSizeM,
                color: AppConstants.primaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
