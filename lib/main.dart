import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'routes/app_routes.dart';
import 'screens/folder.dart';
import 'screens/home.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const AlbumBook(),
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.homePicker) {
          final args = settings.arguments as HomePickerArguments?;
          return MaterialPageRoute(
            builder: (_) => HomePage(
              selectionMode: true,
              selectionLimit: args?.selectionLimit ?? 1,
              preselectedAssetIds: args?.preselectedAssetIds ?? const <String>[],
              preselectedScreenshots:
                  args?.preselectedScreenshots ?? const <String, Uint8List>{},
            ),
          );
        }
        return null;
      },
    );

  }
}
