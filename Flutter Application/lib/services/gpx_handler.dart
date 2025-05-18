import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tracking_app/domain/measurement.dart';
import 'package:tracking_app/domain/track_file.dart';
import 'package:xml/xml.dart';

class GpxHandler {
  /* ----------- GPX I/O -------------------------------------- */
  Future<Directory> get _directory async {
    final Directory dir =
        Directory((await getApplicationDocumentsDirectory()).path + '/files');

    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  String _fileStamp() =>
      'TrackIN_${DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}';

  Future<List<File>> _getAllGpxFiles() async {
    final List<FileSystemEntity> files =
        Directory((await _directory).path).listSync();
    List<Future<File>> futureFiles =
        files.map((f) async => await File(f.path)).toList();
    return await Future.wait(futureFiles);
  }

  Future<List<TrackFile>> getAllTrackFiles() async {
    return Future.wait(
        (await _getAllGpxFiles()).map((f) async => await loadGpxFile(f.path)));
  }

  Future<File> saveMeasurementsToGpxFile(
      String name, List<Measurement> points) async {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
          '<gpx version="1.1" creator="TrackIN" xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('<metadata>')
      ..writeln('  <name>$name</name>')
      ..writeln('  <time>${DateTime.now().toUtc().toIso8601String()}</time>')
      ..writeln('  <copyright author="TrackIN"/>')
      ..writeln('</metadata>')
      ..writeln('<trk><name>${_fileStamp()}</name><trkseg>');

    // Add track points
    for (final p in points) {
      buf
        ..writeln('<trkpt lat="${p.lat}" lon="${p.lon}">')
        ..writeln('<ele>${p.gpsAlt.toStringAsFixed(1)}</ele>')
        ..writeln('<time>${p.t.toUtc().toIso8601String()}</time>');

      // Add barometric altitude as extension if available
      if (p.baroAlt != null) {
        buf
          ..writeln('<extensions>')
          ..writeln('<baro:alt>${p.baroAlt!.toStringAsFixed(1)}</baro:alt>')
          ..writeln('</extensions>');
      }

      buf..writeln('</trkpt>');
    }

    buf..writeln('</trkseg></trk></gpx>');

    // Save file
    final file = File('${((await _directory).path)}/${_fileStamp()}.gpx');
    return file.writeAsString(buf.toString());
  }

  List<Measurement> parseGpxData(String gpxContent) {
    try {
      final measurements = <Measurement>[];

      // Parse XML
      final document = XmlDocument.parse(gpxContent);

      // Find track points
      final trackPoints = document.findAllElements('trkpt');

      for (final point in trackPoints) {
        try {
          // Get latitude and longitude
          final lat = double.parse(point.getAttribute('lat') ?? '0');
          final lon = double.parse(point.getAttribute('lon') ?? '0');

          // Get elevation (altitude)
          final eleElement = point.findElements('ele').firstOrNull;
          final elevation =
              eleElement != null ? double.parse(eleElement.innerText) : 0.0;

          // Get time
          final timeElement = point.findElements('time').firstOrNull;
          final timeString = timeElement?.innerText ?? '';
          final time = timeString.isNotEmpty
              ? DateTime.parse(timeString)
              : DateTime.now();

          // Check for barometric altitude in extensions
          double? baroAlt;
          final extensionsElement =
              point.findElements('extensions').firstOrNull;
          if (extensionsElement != null) {
            final baroElement =
                extensionsElement.findElements('baro:alt').firstOrNull;
            if (baroElement != null) {
              baroAlt = double.tryParse(baroElement.innerText);
            }
          }

          // Create and add measurement
          measurements.add(Measurement(time, lat, lon, elevation, baroAlt));
        } catch (e) {
          // Skip invalid points
          continue;
        }
      }

      return measurements;
    } catch (e) {
      // Return empty list on parsing error
      return [];
    }
  }

  Future<TrackFile> loadGpxFile(String path) async {
    // Read the file contents
    final file = File(path);
    final contents = await file.readAsString();

    // Find track name
    final name =
        XmlDocument.parse(contents).findAllElements('name').firstOrNull;

    // Parse GPX data
    final parsedMeasurements = parseGpxData(contents);

    // Create a TrackFile object
    return TrackFile(
      path: path,
      name: name?.innerText,
      date: parsedMeasurements.first.t,
      pointCount: parsedMeasurements.length,
      measurements: parsedMeasurements,
    );
  }

  Future<(bool, String?)> importGpxFile() async {
    try {
      // Open file picker to select GPX file
      FilePickerResult? result;

      // FilePicker for Android for custom extensions are broken somehow, allow all files, but ensure GPX file later
      // Can remove if future versions of FilePicker fix this
      if (Platform.isAndroid) {
        result = await FilePicker.platform.pickFiles();
      } else {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['gpx'],
        );
      }

      if (result == null || result.files.isEmpty) {
        return (false, 'File selection canceled');
      }

      // Get the file path
      String? filePath = result.files.single.path;
      if (filePath == null) {
        return (false, 'Could not get file path');
      }

      // Ensure GPX file
      if (!filePath.split('/').last.endsWith('.gpx')) {
        return (false, 'Selected file is not a GPX file');
      }

      // Read the file contents
      print('Reading GPX file...');
      final file = File(filePath);
      final contents = await file.readAsString();

      // TODO: Currently does not check if there's any file under the name of the imported file

      // Save file
      final copiedFile =
          File('${((await _directory).path)}/${file.path.split('/').last}');
      copiedFile.writeAsString(contents);
      return (true, null);
    } catch (e) {
      return (false, 'Error loading GPX file: $e');
    }
  }

  Future<void> deleteGpxFile(String path) async {
    final file = File(path);

    if (await file.exists()) {
      await file.delete();
    }
  }

  /* ----------- GPX EDITING ------------------------------------- */
  XmlElement _getMetadataElement(XmlDocument document) {
    XmlElement? metadata = document.findAllElements('metadata').firstOrNull;

    // Create metadata if it doesn't exist in the GPX file
    if (metadata == null) {
      var gpxElement = document.findElements('gpx').first;
      metadata = XmlElement(XmlName('metadata'));
      gpxElement.children.insert(1, metadata);
    }

    return metadata;
  }

  Future<void> setGpxName(String filePath, String name) async {
    File file = File(filePath);
    final contents = await file.readAsString();
    final document = XmlDocument.parse(contents);
    final nameElement = document.findAllElements('name').firstOrNull;

    // Create name if it doesn't exist in the GPX file
    if (nameElement == null) {
      final metadataElement = _getMetadataElement(document);
      metadataElement.children
          .insert(1, XmlElement(XmlName('name'), [], [XmlText(name)]));
    } else {
      nameElement.innerText = name;
    }
    file.writeAsString(document.toXmlString());
  }
}
