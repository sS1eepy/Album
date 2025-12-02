import 'dart:convert';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import 'media_item.dart';

class AlbumPhoto {
  const AlbumPhoto({
    this.mediaItem,
    this.imageUrl,
    this.imageBytes,
    this.assetId,
  });

  final MediaItem? mediaItem;
  final String? imageUrl;
  final Uint8List? imageBytes;
  final String? assetId;

  Map<String, dynamic> toJson() {
    if (imageBytes != null && imageBytes!.isNotEmpty) {
      return {
        'type': 'bytes',
        'value': base64Encode(imageBytes!),
        if (mediaItem != null) 'asset': mediaItem!.asset.id,
        if (assetId != null) 'asset': assetId,
      };
    }
    if (mediaItem != null) {
      return {
        'type': 'asset',
        'value': mediaItem!.asset.id,
      };
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return {
        'type': 'url',
        'value': imageUrl,
      };
    }
    return {
      'type': 'empty',
    };
  }

  static Future<AlbumPhoto> fromJson(Map<String, dynamic> json) async {
    final type = json['type'];
    final value = json['value'];
    if (type == 'asset' && value is String) {
      final asset = await AssetEntity.fromId(value);
      if (asset != null) {
        return AlbumPhoto(mediaItem: MediaItem.fromAsset(asset));
      }
    } else if (type == 'bytes' && value is String) {
      try {
        final decoded = base64Decode(value);
        final assetRef = json['asset'];
        MediaItem? mediaItem;
        if (assetRef is String) {
          final asset = await AssetEntity.fromId(assetRef);
          if (asset != null) {
            mediaItem = MediaItem.fromAsset(asset);
          }
        }
        return AlbumPhoto(
          imageBytes: decoded,
          mediaItem: mediaItem,
          assetId: assetRef is String ? assetRef : null,
        );
      } catch (_) {
        return const AlbumPhoto();
      }
    } else if (type == 'url' && value is String) {
      return AlbumPhoto(imageUrl: value);
    }
    return const AlbumPhoto();
  }
}
