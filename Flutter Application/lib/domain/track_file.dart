import 'package:tracking_app/domain/measurement.dart';

class TrackFile {
  final String path;
  final String? name;
  final DateTime date;
  final int pointCount;
  final List<Measurement> measurements;

  TrackFile({
    required this.path,
    required this.name,
    required this.date,
    required this.pointCount,
    required this.measurements,
  });
}
