import "dart:convert";
import "dart:io";
import "package:flutter/foundation.dart";
import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart";
import "package:tracking_app/domain/track_file.dart";

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

  bool get isLoggedIn => authCredentials != null;

  FrameworkController() {
    // _fetchSavedTokenOnStart();
  }

  void doUnauthed() {
    authCredentials = null;
    notifyListeners();
  }

  Future<void> _fetchSavedTokenOnStart() async {
    File file = File((await _savedTokenDirectory).path);

    // Expect singular line containing token
    final contents = await file.readAsString();

    // Test if token is valid
    // If valid set as it
    authCredentials = contents;
    // Else stay as null
    notifyListeners();
  }

  Future<Directory> get _savedTokenDirectory async {
    final Directory dir = Directory(
        (await getApplicationDocumentsDirectory()).path + 'accountToken.txt');

    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }

    return dir;
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
        authCredentials = jsonDecode(response.body)['access_token'];
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
        return responseBody['file_id'];
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
