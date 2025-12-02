import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../models/album_photo.dart';
import '../models/media_item.dart';
import 'folder.dart' show AlbumBook;
import 'detail_video_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.selectionMode = false,
    this.selectionLimit = 11,
    this.preselectedAssetIds = const <String>[],
    this.preselectedScreenshots = const <String, Uint8List>{},
  });

  final bool selectionMode;
  final int selectionLimit;
  final List<String> preselectedAssetIds;
  final Map<String, Uint8List> preselectedScreenshots;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<MediaItem> mediaList = [];
  final List<MediaItem> selectedItems = [];
  final List<_PickerSelection> pickerSelections = [];
  final Map<String, Uint8List> _videoSnapshots = {};
  bool showThisMonthOnly = false;
  bool isLoading = true;
  bool _initialSelectionsRestored = false;

  @override
  void initState() {
    super.initState();
    loadAllMediaFromDevice();
  }

  /// โหลดสื่อทั้งหมดจากทุกอัลบั้ม
  Future<void> loadAllMediaFromDevice() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      PhotoManager.openSetting();
      return;
    }

    List<AssetPathEntity> albums =
        await PhotoManager.getAssetPathList(type: RequestType.all);

    List<AssetEntity> allAssets = [];

    for (var album in albums) {
      int page = 0;
      const int pageSize = 500;
      while (true) {
        final assets = await album.getAssetListPaged(page: page, size: pageSize);
        if (assets.isEmpty) break;
        allAssets.addAll(assets);
        if (assets.length < pageSize) break;
        page++;
      }
    }

    // กรองเดือนนี้ถ้าต้องการ
    if (showThisMonthOnly) {
      final now = DateTime.now();
      allAssets = allAssets.where((a) {
        final dt = a.createDateTime;
        return dt.year == now.year && dt.month == now.month;
      }).toList();
    }

    // เรียงจากใหม่ไปเก่า
    allAssets.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));

    final seenIds = <String>{};
    final filteredAssets = <AssetEntity>[];
    for (final asset in allAssets) {
      if (seenIds.add(asset.id)) {
        filteredAssets.add(asset);
      }
    }

    final List<MediaItem> temp = filteredAssets.map((a) {
      return MediaItem(
        asset: a,
        type: a.type == AssetType.video ? MediaType.video : MediaType.image,
      );
    }).toList();

    setState(() {
      mediaList
        ..clear()
        ..addAll(temp);
      isLoading = false;
    });
    _restoreInitialSelections();
  }

  void toggleThisMonth(bool value) async {
    setState(() {
      showThisMonthOnly = value;
      isLoading = true;
    });
    await loadAllMediaFromDevice();
  }

  MediaItem? _findMediaById(String id) {
    for (final item in mediaList) {
      if (item.asset.id == id) {
        return item;
      }
    }
    return null;
  }

  Widget _buildThumbnailContent(MediaItem item, Uint8List? defaultBytes) {
    final snapshotBytes = _videoSnapshots[item.asset.id];
    if (snapshotBytes != null && snapshotBytes.isNotEmpty) {
      return Image.memory(snapshotBytes, fit: BoxFit.cover);
    }
    if (defaultBytes != null) {
      return Image.memory(defaultBytes, fit: BoxFit.cover);
    }
    return Container(color: Colors.grey.shade300);
  }

  Widget _buildSelectionPreview() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              "รูปที่เลือกไว้",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            height: 110,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: widget.selectionLimit,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _buildSelectionTile(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionTile(int index) {
    final selection =
        index < pickerSelections.length ? pickerSelections[index] : null;
    return GestureDetector(
      onTap: selection == null ? null : () => _handleSelectionModeTap(selection.mediaItem),
      child: Container(
        width: 95,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selection == null ? Colors.grey.shade400 : Colors.blue,
            width: 2,
          ),
          color: selection == null ? Colors.grey.shade100 : Colors.transparent,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (selection != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildSelectedPreviewImage(selection),
              )
            else
              const Icon(Icons.add_photo_alternate_outlined,
                  color: Colors.grey, size: 32),
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "${index + 1}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPreviewImage(_PickerSelection selection) {
    final bytes =
        selection.imageBytes ?? _videoSnapshots[selection.mediaItem.asset.id];
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.cover);
    }
    return FutureBuilder<Uint8List?>(
      future:
          selection.mediaItem.asset.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(color: Colors.grey.shade300);
        }
        return Image.memory(snapshot.data!, fit: BoxFit.cover);
      },
    );
  }

  Future<void> _handleSelectionModeTap(MediaItem item) async {
    final itemId = item.asset.id;
    final existingIndex =
        pickerSelections.indexWhere((entry) => entry.mediaItem.asset.id == itemId);
    if (existingIndex != -1) {
      setState(() {
        pickerSelections.removeAt(existingIndex);
      });
      return;
    }
    if (pickerSelections.length >= widget.selectionLimit) {
      _showLimitSnackBar();
      return;
    }
    if (item.type == MediaType.video) {
      final bytes = await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(
          builder: (_) => DetailVideoPage(item: item),
        ),
      );
      if (bytes == null) return;
      setState(() {
        _videoSnapshots[item.asset.id] = bytes;
        pickerSelections.add(_PickerSelection(mediaItem: item, imageBytes: bytes));
      });
    } else {
      setState(() {
        pickerSelections.add(_PickerSelection(mediaItem: item));
      });
    }
    if (widget.selectionLimit == 1 && pickerSelections.isNotEmpty) {
      _completePickerSelection();
    }
  }

  void _completePickerSelection() {
    if (!mounted) return;
    final photos = pickerSelections
        .map(
          (entry) => entry.imageBytes != null
              ? AlbumPhoto(mediaItem: entry.mediaItem, imageBytes: entry.imageBytes)
              : AlbumPhoto(mediaItem: entry.mediaItem),
        )
        .toList();
    Navigator.of(context).pop(photos);
  }

  void _showLimitSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        "เลือกได้สูงสุด ${widget.selectionLimit} ไฟล์เท่านั้น",
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 2),
    ));
  }

  int? _selectionIndexFor(MediaItem item) {
    if (widget.selectionMode) {
      final idx = pickerSelections
          .indexWhere((entry) => entry.mediaItem.asset.id == item.asset.id);
      return idx == -1 ? null : idx + 1;
    }
    final idx = selectedItems.indexOf(item);
    return idx == -1 ? null : idx + 1;
  }

  void _restoreInitialSelections() {
    if (!widget.selectionMode || _initialSelectionsRestored) return;
    if (mediaList.isEmpty) return;
    for (final id in widget.preselectedAssetIds) {
      if (pickerSelections.length >= widget.selectionLimit) break;
      final match = _findMediaById(id);
      if (match == null) continue;
      final alreadyAdded = pickerSelections
          .any((entry) => entry.mediaItem.asset.id == match.asset.id);
      if (!alreadyAdded) {
        final screenshot = widget.preselectedScreenshots[id];
        if (screenshot != null) {
          _videoSnapshots[id] = screenshot;
        }
        pickerSelections.add(
          _PickerSelection(
            mediaItem: match,
            imageBytes: screenshot,
          ),
        );
      }
    }
    _initialSelectionsRestored = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MEDIA VIEW", style: TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          if (widget.selectionMode) _buildSelectionPreview(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "แสดงเฉพาะเดือนนี้",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Switch(
                  value: showThisMonthOnly,
                  onChanged: toggleThisMonth,
                  thumbColor: WidgetStateProperty.resolveWith<Color?>(
                    (states) =>
                        states.contains(WidgetState.selected) ? Colors.green : null,
                  ),
                  trackColor: WidgetStateProperty.resolveWith<Color?>(
                    (states) => states.contains(WidgetState.selected)
                        ? Colors.green.withValues(alpha: 0.4)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: mediaList.length,
                    itemBuilder: (context, index) {
                      final item = mediaList[index];
                      final selectionIndex = _selectionIndexFor(item);
                      final isSelected = widget.selectionMode
                          ? selectionIndex != null
                          : selectedItems.contains(item);
                      return FutureBuilder<Uint8List?>(
                        future: item.asset.thumbnailDataWithSize(
                            const ThumbnailSize(300, 300)),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Container(color: Colors.grey.shade300);
                          }
                          return GestureDetector(
                            onTap: () async {
                              if (widget.selectionMode) {
                                await _handleSelectionModeTap(item);
                                if (widget.selectionLimit == 1 &&
                                    pickerSelections.isNotEmpty) {
                                  _completePickerSelection();
                                }
                                return;
                              }
                              Uint8List? capturedBytes;
                              if (item.type == MediaType.video) {
                                capturedBytes = await Navigator.push<Uint8List?>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetailVideoPage(item: item),
                                  ),
                                );
                                if (capturedBytes == null) return;
                              }
                              setState(() {
                                if (isSelected) {
                                  selectedItems.remove(item);
                                } else {
                                  if (selectedItems.length >= widget.selectionLimit) {
                                    _showLimitSnackBar();
                                    return;
                                  }
                                  if (capturedBytes != null) {
                                    _videoSnapshots[item.asset.id] = capturedBytes;
                                  }
                                  selectedItems.add(item);
                                }
                              });
                            },
                            child: Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    border: isSelected
                                        ? Border.all(
                                            color: Colors.green, width: 3)
                                        : null,
                                  ),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _buildThumbnailContent(item, snapshot.data),
                                      if (item.type == MediaType.video)
                                        const Align(
                                          alignment: Alignment.bottomRight,
                                          child: Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.play_circle_fill,
                                              color: Colors.white,
                                              size: 26,
                                            ),
                                          ),
                                        ),
                                      if (selectionIndex != null)
                                        Container(
                                          color: Colors.black38,
                                          child: Center(
                                            child: Text(
                                              "$selectionIndex",
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 28,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: widget.selectionMode
          ? BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                        "${pickerSelections.length}/${widget.selectionLimit} selected"),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text("ยกเลิก"),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed:
                            pickerSelections.isEmpty ? null : _completePickerSelection,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue),
                        child: const Text("ยืนยัน",
                            style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ],
              ),
            )
          : BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text("${selectedItems.length} selected"),
                  ),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: selectedItems.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  mediaList.removeWhere(
                                      (m) => selectedItems.contains(m));
                                  selectedItems.clear();
                                });
                              },
                        style:
                            ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text("Delete",
                            style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: selectedItems.isEmpty
                            ? null
                            : () {
                                final photos = selectedItems
                                    .map(
                                      (item) => _videoSnapshots[item.asset.id] != null
                                          ? AlbumPhoto(
                                              mediaItem: item,
                                              imageBytes:
                                                  _videoSnapshots[item.asset.id],
                                            )
                                          : AlbumPhoto(mediaItem: item),
                                    )
                                    .toList();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AlbumBook(initialPhotos: photos),
                                  ),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue),
                        child: const Text("Next",
                            style: TextStyle(color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class SelectedMediaPage extends StatefulWidget {
  final List<MediaItem> items;
  const SelectedMediaPage({super.key, required this.items});

  @override
  State<SelectedMediaPage> createState() => _SelectedMediaPageState();
}

class _SelectedMediaPageState extends State<SelectedMediaPage> {
  final Map<AssetEntity, VideoPlayerController> controllers = {};

  @override
  void initState() {
    super.initState();
    for (var item in widget.items) {
      if (item.type == MediaType.video) {
        item.asset.file.then((file) {
          if (file == null) return;
          final controller = VideoPlayerController.file(file)
            ..initialize().then((_) => setState(() {}));
          controllers[item.asset] = controller;
        });
      }
    }
  }

  @override
  void dispose() {
    for (var c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Selected Media")),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final item = widget.items[index];

          if (item.type == MediaType.image) {
            return FutureBuilder(
              future: item.asset.file,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Image.file(snapshot.data!, fit: BoxFit.cover);
              },
            );
          }

          final controller = controllers[item.asset];
          if (controller == null || !controller.value.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          return GestureDetector(
            onTap: () {
              controller.value.isPlaying
                  ? controller.pause()
                  : controller.play();
              setState(() {});
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
                const Icon(Icons.play_circle_fill, color: Colors.white, size: 50),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PickerSelection {
  _PickerSelection({required this.mediaItem, this.imageBytes});

  final MediaItem mediaItem;
  final Uint8List? imageBytes;
}
