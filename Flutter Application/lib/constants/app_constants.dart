import 'package:flutter/material.dart';

class AppConstants {
  AppConstants._();

  static final appBarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[
      const Color.fromARGB(255, 46, 46, 46),
      const Color.fromARGB(255, 105, 105, 105),
    ],
  );

  static final appBodyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      const Color.fromARGB(255, 105, 105, 105),
      const Color.fromARGB(255, 92, 92, 92),
      const Color.fromARGB(255, 68, 68, 68),
      const Color.fromARGB(255, 32, 32, 32)
    ],
  );

  static final listPrimaryTextStyle = TextStyle(fontSize: 12);

  static final primaryTextColor = const Color.fromRGBO(255, 255, 255, 0.8);
  static final primaryBackgroundColor =
      const Color.fromRGBO(255, 255, 255, 0.1);

  static final secondaryBackgroundColor =
      const Color.fromRGBO(255, 255, 255, 0.05);

  static final primarySolidBackgroundColor =
      const Color.fromRGBO(100, 100, 100, 1);

  static final double textSizeXXL = 52;
  static final double textSizeXL = 24;
  static final double textSizeL = 16;
  static final double textSizeM = 14;

  static final Color general = Color.fromRGBO(51, 51, 51, 1);
  static final Color success = Color.fromRGBO(90, 182, 118, 1);
  static final Color error = Color.fromRGBO(231, 105, 116, 1);

  static final primaryButtonStyle = ButtonStyle(
    backgroundColor:
        WidgetStatePropertyAll(AppConstants.secondaryBackgroundColor),
  );
}
