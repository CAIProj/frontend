import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracking_app/functional/graph.dart';
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

  _TrackPageState({required TrackFile this.trackFile});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, TrackChange? result) {
        if (didPop) {
          return;
        }

        Navigator.pop(context, wasUpdated ? TrackChange.Edited : null);
      },
      child: Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: EdgeInsets.only(top: 12),
          child: Column(
            children: [
              SizedBox(
                  height: 400,
                  child: TrackGraph(measurements: trackFile.measurements)),
              SizedBox(height: 12),
              TrackSummary(trackFile: trackFile),
              // Name / Rename of the track
              TextField(
                onSubmitted: (value) {
                  GpxHandler().setGpxName(trackFile.path, value);
                  wasUpdated = true;
                },
                decoration: InputDecoration(
                  hintText: trackFile.name ?? 'Unnamed track',
                ),
              ),
              // Share Button
              TextButton(
                  onPressed: () async {
                    // Show share dialog
                    await Share.shareXFiles(
                      [XFile(trackFile.path)],
                      subject:
                          'Altitude Tracking Data (${trackFile.measurements.length} points)',
                      text: 'Exported on ${DateTime.now().toLocal()}',
                    );
                  },
                  child: Text('Share')),
              // Delete Button
              TextButton(
                  onPressed: () {
                    _gpxHandler.deleteGpxFile(trackFile.path);
                    Navigator.pop(context, TrackChange.Deleted);
                  },
                  child: Text('Delete'))
            ],
          ),
        ),
      ),
    );
  }
}

class TrackSummary extends StatefulWidget {
  final TrackFile trackFile;

  const TrackSummary({super.key, required TrackFile this.trackFile});
  @override
  State<TrackSummary> createState() => _TrackSummaryState(trackFile: trackFile);
}

class _TrackSummaryState extends State<TrackSummary> {
  final TrackFile trackFile;

  _TrackSummaryState({required TrackFile this.trackFile});

  Widget _buildTrackSummary() {
    final distances = get_distances(trackFile.measurements);
    final totalDistance = distances.isEmpty ? 0.0 : distances.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Points: ${trackFile.pointCount}'),
        Text('Distance: ${totalDistance.toStringAsFixed(2)} km'),
        Text(
            'Date: ${DateFormat('dd.MM.yyyy - HH:mm').format(trackFile.date)}'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildTrackSummary();
  }
}
