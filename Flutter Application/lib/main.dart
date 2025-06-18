import 'package:flutter/material.dart';
import 'package:tracking_app/services/notification_controller.dart';
import 'package:provider/provider.dart';
import 'package:tracking_app/services/framework_controller.dart';
import 'pages/home_page.dart';

void main() => runApp(const TrackingApp());

/* ======================== ROOT ======================================== */

class TrackingApp extends StatelessWidget {
  const TrackingApp({super.key});

  @override
  Widget build(BuildContext ctx) => MaterialApp(
        title: 'TrackIN',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 2,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          cardTheme: const CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          actionIconTheme: ActionIconThemeData(
            backButtonIconBuilder: (BuildContext context) =>
                Icon(Icons.chevron_left),
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 2,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(120, 45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          cardTheme: const CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          actionIconTheme: ActionIconThemeData(
            backButtonIconBuilder: (BuildContext context) =>
                Icon(Icons.chevron_left),
          ),
        ),
        themeMode: ThemeMode.system,
        builder: (context, child) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => NotificationController()),
            ChangeNotifierProvider(create: (_) => FrameworkController())
          ],
          child: child,
        ),
        home: const HomePage(),
      );
}
