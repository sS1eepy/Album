import 'package:photo_manager/photo_manager.dart';

/// Simple media wrapper so different screens can share the same structure.
enum MediaType { image, video }

class MediaItem {
  MediaItem({
    required this.asset,
    required this.type,
  });

  final AssetEntity asset;
  final MediaType type;

  factory MediaItem.fromAsset(AssetEntity asset) {
    final type =
        asset.type == AssetType.video ? MediaType.video : MediaType.image;
    return MediaItem(asset: asset, type: type);
  }
}
