import 'dart:convert';

import 'package:crypto/crypto.dart';

String getHash(String input) {
  return sha256.convert(utf8.encode(input)).toString();
}
