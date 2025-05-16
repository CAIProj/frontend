import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracking_app/constants/app_constants.dart';
import 'package:tracking_app/functional/graph.dart';
import 'package:tracking_app/functional/pop_up_dialogue.dart';
import 'package:tracking_app/functional/utils.dart';
import 'package:tracking_app/domain/track_file.dart';
import 'package:tracking_app/pages/tracks_page.dart';
import 'package:tracking_app/services/gpx_handler.dart';

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

  _TrackPageState({required TrackFile this.trackFile});
  @override
  void initState() {
    super.initState();
    _editNameController = TextEditingController(text: trackFile.displayName);
  }

  @override
  Widget build(BuildContext context) {
    final distances = get_distances(trackFile.measurements);
    final totalDistance = distances.isEmpty ? 0.0 : distances.last;
    final totalDuration = trackFile.measurements.last.t
        .difference(trackFile.measurements.first.t);
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
                TrackFile t = await GpxHandler().loadGpxFile(trackFile.path);
                setState(() {
                  trackFile = t;
                });
                wasUpdated = true;
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
                    child: TrackGraph(measurements: trackFile.measurements)),
                SizedBox(height: 30),

                // Information
                Container(
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
                                      fontSize: AppConstants.textSizeLarge,
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
                                    Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 14),
                                      child: Tooltip(
                                        message: 'Points',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.polyline_outlined,
                                              color:
                                                  AppConstants.primaryTextColor,
                                            ),
                                            SizedBox(
                                              width: 8,
                                            ),
                                            Text(
                                              '${trackFile.pointCount}',
                                              style: TextStyle(
                                                fontSize:
                                                    AppConstants.textSizeMedium,
                                                color: AppConstants
                                                    .primaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 14),
                                      child: Tooltip(
                                        message: 'Distance',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.route_outlined,
                                              color:
                                                  AppConstants.primaryTextColor,
                                            ),
                                            SizedBox(
                                              width: 8,
                                            ),
                                            Text(
                                              '${totalDistance.toStringAsFixed(2)} km',
                                              style: TextStyle(
                                                fontSize:
                                                    AppConstants.textSizeMedium,
                                                color: AppConstants
                                                    .primaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 14),
                                      child: Tooltip(
                                        message: 'Duration',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.schedule_outlined,
                                              color:
                                                  AppConstants.primaryTextColor,
                                            ),
                                            SizedBox(
                                              width: 8,
                                            ),
                                            Text(
                                              '${totalDuration.inHours}h ${totalDuration.inMinutes % 60}m ${totalDuration.inSeconds % 60}s',
                                              style: TextStyle(
                                                fontSize:
                                                    AppConstants.textSizeMedium,
                                                color: AppConstants
                                                    .primaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 14),
                                      child: Tooltip(
                                        message: 'Barometer',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.edgesensor_high_outlined,
                                              color:
                                                  AppConstants.primaryTextColor,
                                            ),
                                            SizedBox(
                                              width: 8,
                                            ),
                                            Text(
                                              '${hasBarometer[0].toUpperCase() + hasBarometer.substring(1)}',
                                              style: TextStyle(
                                                fontSize:
                                                    AppConstants.textSizeMedium,
                                                color: AppConstants
                                                    .primaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
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
                                            style: ButtonStyle(
                                              backgroundColor:
                                                  WidgetStatePropertyAll(
                                                      AppConstants
                                                          .secondaryBackgroundColor),
                                            ),
                                            onPressed:
                                                _editNameFocusNode.requestFocus,
                                            child: Text(
                                              'Rename',
                                              style: TextStyle(
                                                fontSize:
                                                    AppConstants.textSizeMedium,
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
                                            style: ButtonStyle(
                                              backgroundColor:
                                                  WidgetStatePropertyAll(
                                                      AppConstants
                                                          .secondaryBackgroundColor),
                                            ),
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
                                                    AppConstants.textSizeMedium,
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
                                            style: ButtonStyle(
                                              backgroundColor:
                                                  WidgetStatePropertyAll(
                                                      AppConstants
                                                          .secondaryBackgroundColor),
                                            ),
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
                                                    AppConstants.textSizeMedium,
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
