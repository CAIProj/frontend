import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:tracking_app/domain/track_file.dart";
import "package:tracking_app/services/gpx_handler.dart";
import "package:tracking_app/services/hash.dart";

class UploadedGPXFile {
  final int id;
  final String filename;
  final DateTime date;

  UploadedGPXFile({
    required this.id,
    required this.filename,
    required this.date,
  });
}

class FrameworkController with ChangeNotifier {
  final String baseUrl = "https://trackin-api-nj15.onrender.com/";

  String? authCredentials = null;
  Map<String, int>? localToUploadedMapping = null;

  bool get isLoggedIn => authCredentials != null;

  Future<void> doAuthed(String credentials) async {
    authCredentials = credentials;
    localToUploadedMapping = await mapLocalToUploadedFiles();
    notifyListeners();
  }

  void doUnauthed() {
    authCredentials = null;
    localToUploadedMapping = null;
    notifyListeners();
  }

  Future<Map<String, int>> mapLocalToUploadedFiles() async {
    final uploaded = await downloadAllGPXFiles();
    final Map<String, UploadedGPXFile> uploadedHashes = Map();

    for (final v in uploaded.entries) {
      if (v.value != null) {
        uploadedHashes[getHash(v.value!)] = v.key;
      }
    }

    final List<TrackFile> locals = await GpxHandler().getAllTrackFiles();

    final Map<String, int> mapping = Map();

    locals.forEach((v) {
      File file = File(v.path);
      final hash = getHash(file.readAsStringSync());
      final uploadedData = uploadedHashes[hash];
      if (uploadedData != null) {
        mapping[v.path] = uploadedData.id;
      }
    });

    return mapping;
  }

  Future<bool> isTokenValid(String token) async {
    return false;
  }

  Future<(bool, String?)> register(
      String username, String email, String password) async {
    final url = Uri.parse(baseUrl + "register");
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(
            {"username": username, "email": email, "password": password}),
      );
      if (response.statusCode == 200) {
        return (true, null);
      } else {
        print("Request failed with status: ${response.statusCode}");
        throw jsonDecode(response.body)?['detail'];
      }
    } catch (e) {
      return (false, e.toString());
    }
  }

  Future<bool> login(String username, String password) async {
    final url = Uri.parse(baseUrl + "login");
    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {"username": username, "password": password},
      );
      if (response.statusCode == 200) {
        await doAuthed(jsonDecode(response.body)['access_token']);
        return true;
      } else {
        print("Request failed with status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error: $e");
    }
    return false;
  }

  void logout() {
    doUnauthed();
  }

  Future<int?> uploadGPXFile(TrackFile trackFile) async {
    final url = Uri.parse(baseUrl + "upload/");
    try {
      File file = File(trackFile.path);

      var request = http.MultipartRequest('POST', url);

      request.headers.addAll({
        'Authorization': 'Bearer $authCredentials',
      });

      request.fields.addAll({"filename": trackFile.displayName});

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
        ),
      );

      var response = await request.send();

      if (response.statusCode == 200) {
        final responseBody =
            jsonDecode((await http.Response.fromStream(response)).body);

        final id = responseBody['file_id'];
        localToUploadedMapping?[trackFile.path] = id;
        notifyListeners();

        return id;
      } else if (response.statusCode == 403) {
        doUnauthed();
      } else {
        print("Request failed with status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error: $e");
    }
    return null;
  }

  Future<String?> downloadGPXFile(int uploadedId) async {
    final url = Uri.parse(baseUrl + "files/$uploadedId");
    try {
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $authCredentials',
      });

      if (response.statusCode == 200) {
        return response.body;
      } else if (response.statusCode == 403) {
        doUnauthed();
      } else {
        print("Request failed with status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error: $e");
    }
    return null;
  }

  Future<Map<UploadedGPXFile, String?>> downloadAllGPXFiles() async {
    final uploadedData = await getUploadedGPXFiles();
    final Map<UploadedGPXFile, String?> map = Map();

    for (final v in uploadedData ?? []) {
      final fileContents = await downloadGPXFile(v.id);
      map[v] = fileContents;
    }
    return map;
  }

  Future<List<UploadedGPXFile>?> getUploadedGPXFiles() async {
    final url = Uri.parse(baseUrl + "files/");
    try {
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer $authCredentials',
      });

      if (response.statusCode == 200) {
        List<dynamic> objects = jsonDecode(response.body);
        List<UploadedGPXFile> files = [];
        objects.forEach(
          (v) => files.add(
            UploadedGPXFile(
              id: v['id'],
              filename: v['filename'],
              date: DateTime.parse(
                v['date'],
              ),
            ),
          ),
        );
        return files;
      } else if (response.statusCode == 403) {
        doUnauthed();
      } else {
        print("Request failed with status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error: $e");
    }
    return null;
  }

  Future<bool> deleteGPXFile(int fileId) async {
    final url = Uri.parse(baseUrl + "files/" + fileId.toString());
    try {
      final response = await http.delete(url, headers: {
        'Authorization': 'Bearer $authCredentials',
      });

      if (response.statusCode == 200) {
        final key = localToUploadedMapping?.entries
            .firstWhere((entry) => entry.value == fileId);
        localToUploadedMapping?.remove(key);

        notifyListeners();
        return true;
      } else if (response.statusCode == 403) {
        doUnauthed();
      } else {
        print("Request failed with status: ${response.statusCode}");
      }
    } catch (e) {
      print("Error: $e");
    }
    return false;
  }
}
