import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tracking_app/constants/app_constants.dart';
import 'package:tracking_app/domain/track_file.dart';
import 'package:tracking_app/services/notification_controller.dart' as n;
import 'package:tracking_app/pages/track_page.dart';
import 'package:tracking_app/services/gpx_handler.dart';

class TracksPage extends StatefulWidget {
  const TracksPage({super.key});
  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  GpxHandler _gpxHandler = GpxHandler();

  late final n.NotificationController _notificationController =
      Provider.of<n.NotificationController>(context, listen: false);

  TextEditingController _searchController = TextEditingController();

  List<TrackFile> _trackFiles = [];
  List<TrackFile> _displayedFiles = [];

  bool _loading = false;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    fetchFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void evaluateDisplayedFiles() {
    // Filter by name
    if (_isTyping) {
      _displayedFiles = _trackFiles
          .where((x) =>
              x.name
                  ?.toLowerCase()
                  .startsWith(_searchController.text.toLowerCase()) ??
              false)
          .toList();
    } else {
      _displayedFiles = _trackFiles;
    }

    // Sort by date descending
    setState(() {
      _displayedFiles.sort((x, y) => y.date.difference(x.date).inSeconds);
    });
  }

  void fetchFiles() async {
    setState(() {
      _loading = true;
    });
    final files = await _gpxHandler.getAllTrackFiles();
    setState(() {
      _trackFiles = files;
    });
    evaluateDisplayedFiles();

    setState(() {
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        foregroundColor: AppConstants.primaryTextColor,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: AppConstants.appBarGradient),
        ),
        title: Container(
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppConstants.primaryBackgroundColor,
            borderRadius: BorderRadius.circular(50),
          ),
          height: 38,
          width: MediaQuery.of(context).size.width * 0.6,
          child: Center(
            // Search bar
            child: IntrinsicWidth(
              child: TextField(
                controller: _searchController,
                onChanged: (String text) {
                  setState(() {
                    _isTyping = !_searchController.text.isEmpty;
                  });
                  evaluateDisplayedFiles();
                },
                maxLines: 1,
                textAlignVertical: TextAlignVertical.center,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppConstants.primaryTextColor,
                ),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Search',
                  hintStyle: TextStyle(
                    color: const Color.fromRGBO(255, 255, 255, 0.5),
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          // Load GPX file button
          IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Load GPX file',
              onPressed: () async {
                final (success, error) = await _gpxHandler.importGpxFile();
                if (success) {
                  _notificationController.addNotification(n.Notification(
                      type: n.NotificationType.Success,
                      text: 'Imported GPX File'));
                } else {
                  if (error != null) {
                    _notificationController.addNotification(
                      n.Notification(
                          type: n.NotificationType.Error, text: error),
                    );
                  }
                }
              }),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppConstants.appBodyGradient),
        child: _loading
            ? Center(
                child: CircularProgressIndicator(
                color: AppConstants.primaryTextColor,
              ))
            : ListView.separated(
                padding: EdgeInsets.symmetric(vertical: 16),
                itemCount: _displayedFiles.length,
                separatorBuilder: (context, index) => SizedBox(height: 16),
                itemBuilder: (context, index) {
                  TrackFile trackFile = _displayedFiles[index];
                  return TrackInstance(
                    key: ValueKey(trackFile),
                    trackFile: trackFile,
                    onDelete: () {
                      _trackFiles.remove(trackFile);
                      evaluateDisplayedFiles();
                    },
                  );
                },
              ),
      ),
    );
  }
}

enum TrackChange { Edited, Deleted }

class TrackInstance extends StatefulWidget {
  final TrackFile trackFile;
  final Function onDelete;

  const TrackInstance(
      {super.key, required this.trackFile, required Function this.onDelete});
  @override
  State<TrackInstance> createState() =>
      _TrackInstanceState(trackFile: trackFile);
}

class _TrackInstanceState extends State<TrackInstance> {
  GpxHandler _gpxHandler = GpxHandler();
  TrackFile trackFile;

  late final n.NotificationController _notificationController =
      Provider.of<n.NotificationController>(context, listen: false);

  _TrackInstanceState({required TrackFile this.trackFile});

  void _onUpdate() async {
    trackFile = await _gpxHandler.loadGpxFile(trackFile.path);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => TrackPage(
                      trackFile: trackFile,
                    ))).then((changes) {
          if (changes == TrackChange.Edited) {
            _onUpdate();
          } else if (changes == TrackChange.Deleted) {
            _notificationController.addNotification(n.Notification(
                type: n.NotificationType.General, text: 'Track deleted'));
            widget.onDelete();
          }
        });
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 20),
          decoration: BoxDecoration(
            color: AppConstants.primaryBackgroundColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.5),
                    child: Text(
                      trackFile.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppConstants.primaryTextColor,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '${trackFile.date.day}.${trackFile.date.month}.${trackFile.date.year}, ${trackFile.date.hour}:${trackFile.date.minute}',
                    style: TextStyle(
                      fontSize: AppConstants.textSizeM,
                      color: AppConstants.primaryTextColor,
                    ),
                  )
                ],
              ),
              Spacer(),
              Icon(
                Icons.chevron_right,
                color: AppConstants.primaryTextColor,
              )
            ],
          ),
        ),
      ),
    );
  }
}
