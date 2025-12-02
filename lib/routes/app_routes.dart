import 'dart:typed_data';

class AppRoutes {
  static const String homePicker = '/home-picker';
}

class HomePickerArguments {
  const HomePickerArguments({
    this.selectionLimit = 1,
    this.preselectedAssetIds = const <String>[],
    this.preselectedScreenshots = const <String, Uint8List>{},
  });

  final int selectionLimit;
  final List<String> preselectedAssetIds;
  final Map<String, Uint8List> preselectedScreenshots;
}
