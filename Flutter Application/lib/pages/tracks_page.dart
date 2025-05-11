import 'package:flutter/material.dart';
import 'package:tracking_app/constants/app_constants.dart';
import 'package:tracking_app/domain/track_file.dart';
import 'package:tracking_app/pages/track_page.dart';
import 'package:tracking_app/services/gpx_handler.dart';

class TracksPage extends StatefulWidget {
  const TracksPage({super.key});
  @override
  State<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends State<TracksPage> {
  GpxHandler _gpxHandler = GpxHandler();

  TextEditingController _searchController = TextEditingController();

  List<TrackFile> _trackFiles = [];
  List<TrackFile> _displayedFiles = [];

  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    fetchFiles();
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
    final files = await _gpxHandler.getAllTrackFiles();
    setState(() {
      _trackFiles = files;
      evaluateDisplayedFiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Container(
          padding: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceBright,
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
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Search',
                ),
              ),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.only(top: 12),
        child: ListView.separated(
          itemCount: _displayedFiles.length,
          separatorBuilder: (context, index) => SizedBox(height: 12),
          itemBuilder: (context, index) {
            return TrackInstance(
              key: ValueKey(_displayedFiles[index]),
              trackFile: _displayedFiles[index],
              onDelete: () {
                _trackFiles.removeAt(index);
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
      _TrackInstanceState(trackFile: trackFile, onDelete: onDelete);
}

class _TrackInstanceState extends State<TrackInstance> {
  GpxHandler _gpxHandler = GpxHandler();
  TrackFile trackFile;
  Function onDelete;

  _TrackInstanceState(
      {required TrackFile this.trackFile, required Function this.onDelete});

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
              onDelete();
            }
          });
        },
        child: Padding(
            padding: EdgeInsets.only(left: 16, right: 16),
            child: Container(
                padding:
                    EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trackFile.name ?? "Unnamed track",
                          style: AppConstants.listPrimaryTextStyle,
                        ),
                        SizedBox(height: 8),
                        Text(
                            '${trackFile.date.month}.${trackFile.date.day}.${trackFile.date.year} ${trackFile.date.hour}:${trackFile.date.minute}',
                            style: AppConstants.listPrimaryTextStyle)
                      ],
                    ),
                    Spacer(),
                    Icon(Icons.chevron_right)
                  ],
                ))));
  }
}
