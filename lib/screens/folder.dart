import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:page_flip/page_flip.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/album_photo.dart';
import '../models/media_item.dart';
import '../routes/app_routes.dart';
import 'detail_video_page.dart';

const double _slotWidth = 140;
const double _slotAspectRatio = 0.95;
const double _gridSpacing = 12;
const double _pagePaddingValue = 18;
const double _pageGap = 18;
const int _rowsPerPageColumn = 3;
const int _leftPagePhotoSlots = 5;
const int _rightPagePhotoSlots = 6;
const int _photosPerMonth = _leftPagePhotoSlots + _rightPagePhotoSlots;

double get _slotHeight => _slotWidth / _slotAspectRatio;
double get _columnInnerWidth => (_slotWidth * 2) + _gridSpacing;
double get _columnOuterWidth => _columnInnerWidth + (_pagePaddingValue * 2);
double get _columnInnerHeight =>
    (_slotHeight * _rowsPerPageColumn) + _gridSpacing * (_rowsPerPageColumn - 1);
double get _columnOuterHeight => _columnInnerHeight + (_pagePaddingValue * 2);
double get _spreadBaseWidth => _columnOuterWidth * 2 + _pageGap;
double get _spreadBaseHeight => _columnOuterHeight;

const EdgeInsets _pagePadding = EdgeInsets.all(_pagePaddingValue);
const String _layoutStorageKey = 'album_layout_v1';

void main() {
  runApp(const AlbumApp());
}

class AlbumApp extends StatelessWidget {
  const AlbumApp({super.key, this.initialPhotos = const <AlbumPhoto>[]});

  final List<AlbumPhoto> initialPhotos;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monthly Photo Album',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.grey, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFF8D6E63),
      ),
      home: AlbumBook(initialPhotos: initialPhotos),
    );
  }
}

class AlbumBook extends StatefulWidget {
  const AlbumBook({super.key, this.initialPhotos = const <AlbumPhoto>[]});

  final List<AlbumPhoto> initialPhotos;

  @override
  State<AlbumBook> createState() => _AlbumBookState();
}

class _AlbumBookState extends State<AlbumBook> {
  final GlobalKey<PageFlipWidgetState> _pageFlipKey = GlobalKey<PageFlipWidgetState>();
  final PageFlipController _pageFlipController = PageFlipController();
  late final List<AlbumMonth> _months;
  late final List<ValueNotifier<int>> _monthSignals;
  int _currentPageIndex = 0;
  SharedPreferences? _prefs;
  bool _isPhotoDragging = false;

  @override
  void initState() {
    super.initState();
    _months = _generateAlbumMonths(List<AlbumPhoto>.from(widget.initialPhotos));
    _monthSignals =
        List<ValueNotifier<int>>.generate(_months.length, (_) => ValueNotifier<int>(0));
    _initPersistence();
  }

  void _handlePhotoDragState(bool isDragging) {
    if (_isPhotoDragging == isDragging) return;
    setState(() {
      _isPhotoDragging = isDragging;
    });
  }

  Future<void> _initPersistence() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (widget.initialPhotos.isEmpty) {
      await _loadSavedLayout();
    }
  }

  Future<void> _loadSavedLayout() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final raw = prefs.getString(_layoutStorageKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final leftUpdates =
          List<List<AlbumPhoto>?>.filled(_months.length, null, growable: false);
      final rightUpdates =
          List<List<AlbumPhoto>?>.filled(_months.length, null, growable: false);
      for (int i = 0; i < _months.length && i < decoded.length; i++) {
        final entry = decoded[i];
        if (entry is! Map) continue;
        final mapEntry = Map<String, dynamic>.from(entry);
        final leftRaw = mapEntry['left'];
        final rightRaw = mapEntry['right'];
        leftUpdates[i] =
            await _deserializePhotoList(leftRaw, _months[i].leftPhotos.length);
        rightUpdates[i] =
            await _deserializePhotoList(rightRaw, _months[i].rightPhotos.length);
      }
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < _months.length; i++) {
          final left = leftUpdates[i];
          final right = rightUpdates[i];
          if (left != null) {
            _months[i].leftPhotos.setAll(0, left);
          }
          if (right != null) {
            _months[i].rightPhotos.setAll(0, right);
          }
        }
        for (final signal in _monthSignals) {
          signal.value = signal.value + 1;
        }
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Failed to load saved layout: $error');
      }
    }
  }

  Future<List<AlbumPhoto>?> _deserializePhotoList(dynamic data, int expectedLength) async {
    if (data is! List || data.length != expectedLength) return null;
    final futures = <Future<AlbumPhoto>>[];
    for (final entry in data) {
      if (entry is Map) {
        futures.add(AlbumPhoto.fromJson(Map<String, dynamic>.from(entry)));
      } else {
        futures.add(Future<AlbumPhoto>.value(const AlbumPhoto()));
      }
    }
    return Future.wait(futures);
  }

  Future<void> _saveLayout() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      final payload = _months
          .map(
            (month) => {
              'left': month.leftPhotos.map((photo) => photo.toJson()).toList(),
              'right': month.rightPhotos.map((photo) => photo.toJson()).toList(),
            },
          )
          .toList();
      await prefs.setString(_layoutStorageKey, jsonEncode(payload));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Failed to save layout: $error');
      }
    }
  }

  @override
  void dispose() {
    for (final notifier in _monthSignals) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF8D6E63),
      appBar: AppBar(
        centerTitle: true,
        title: const Icon(Icons.photo_album_outlined, size: 28, color: Colors.black54),
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Icon(Icons.swap_horiz, size: 28, color: Colors.black45),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double widthRatio = constraints.maxWidth > 0
                    ? math.min(1.0, constraints.maxWidth / _spreadBaseWidth)
                    : 0.0;
                final double heightRatio = constraints.maxHeight > 0
                    ? math.min(1.0, constraints.maxHeight / _spreadBaseHeight)
                    : 0.0;
                final double scale = math.min(widthRatio, heightRatio);
                final double targetWidth = _spreadBaseWidth * (scale > 0 ? scale : 1.0);
                final double targetHeight = _spreadBaseHeight * (scale > 0 ? scale : 1.0);

                return Center(
                  child: SizedBox(
                    width: targetWidth,
                    height: targetHeight,
                    child: RawGestureDetector(
                      gestures: _isPhotoDragging
                          ? <Type, GestureRecognizerFactory>{
                              _DragBlockerGestureRecognizer:
                                  GestureRecognizerFactoryWithHandlers<
                                      _DragBlockerGestureRecognizer>(
                                () => _DragBlockerGestureRecognizer(),
                                (_DragBlockerGestureRecognizer instance) {},
                              ),
                            }
                          : const <Type, GestureRecognizerFactory>{},
                      behavior: HitTestBehavior.deferToChild,
                      child: PageFlipWidget(
                        key: _pageFlipKey,
                        controller: _pageFlipController,
                        initialIndex: _currentPageIndex,
                        backgroundColor: Colors.white,
                        onPageFlipped: (index) {
                          _currentPageIndex = index;
                        },
                        children: List.generate(
                          _months.length,
                          (index) {
                            final month = _months[index];
                            return AlbumSpread(
                              month: month,
                              monthIndex: index,
                              onPhotoDropped: (photoData, targetIsLeft, targetIndex) {
                                _handlePhotoDrop(
                                  monthIndex: index,
                                  data: photoData,
                                  targetIsLeft: targetIsLeft,
                                  targetIndex: targetIndex,
                                );
                              },
                              onPhotoTapped: (monthIndex, isLeft, targetIndex) {
                                _handlePhotoTap(
                                  monthIndex: monthIndex,
                                  targetIsLeft: isLeft,
                                  targetIndex: targetIndex,
                                );
                              },
                              onEditMonth: () => _handleReplaceMonth(index),
                              onDragStateChanged: _handlePhotoDragState,
                              updateSignal: _monthSignals[index],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _handlePhotoDrop({
    required int monthIndex,
    required PhotoDragData data,
    required bool targetIsLeft,
    required int targetIndex,
  }) {
    final month = _months[monthIndex];
    final sourceList = data.isLeft ? month.leftPhotos : month.rightPhotos;
    final targetList = targetIsLeft ? month.leftPhotos : month.rightPhotos;

    if (sourceList == targetList) {
      if (data.photoIndex == targetIndex) return;
      final temp = sourceList[data.photoIndex];
      sourceList[data.photoIndex] = sourceList[targetIndex];
      sourceList[targetIndex] = temp;
    } else {
      final temp = sourceList[data.photoIndex];
      sourceList[data.photoIndex] = targetList[targetIndex];
      targetList[targetIndex] = temp;
    }
    _monthSignals[monthIndex].value = _monthSignals[monthIndex].value + 1;
    unawaited(_saveLayout());
  }

  Future<void> _handlePhotoTap({
    required int monthIndex,
    required bool targetIsLeft,
    required int targetIndex,
  }) async {
    await _handleReplaceMonth(monthIndex);
  }

  Future<List<AlbumPhoto>?> _pickPhotos({
    required int limit,
    List<String> preselectedAssetIds = const <String>[],
    Map<String, Uint8List> preselectedScreenshots = const <String, Uint8List>{},
  }) async {
    final navigator = Navigator.of(context);
    final result = await navigator.pushNamed(
      AppRoutes.homePicker,
      arguments: HomePickerArguments(
        selectionLimit: limit,
        preselectedAssetIds: preselectedAssetIds,
        preselectedScreenshots: preselectedScreenshots,
      ),
    );
    if (!mounted) return null;
    if (result is List<AlbumPhoto>) {
      return _processVideoSelections(result);
    }
    if (result is AlbumPhoto) {
      return _processVideoSelections(<AlbumPhoto>[result]);
    }
    return null;
  }

  Future<List<AlbumPhoto>> _processVideoSelections(List<AlbumPhoto> photos) async {
    final processed = <AlbumPhoto>[];
    for (final photo in photos) {
      final mediaItem = photo.mediaItem;
      if (mediaItem != null && mediaItem.type == MediaType.video && photo.imageBytes == null) {
        final bytes = await Navigator.of(context).push<Uint8List?>(
          _buildVideoDetailRoute(mediaItem),
        );
        if (bytes != null) {
          processed.add(AlbumPhoto(mediaItem: mediaItem, imageBytes: bytes));
          continue;
        }
      }
      processed.add(photo);
    }
    return processed;
  }

  Future<void> _handleReplaceMonth(int monthIndex) async {
    _currentPageIndex = monthIndex;
    final month = _months[monthIndex];
    final preselected = <String>[];
    final preselectedShots = <String, Uint8List>{};
    for (final photo in month.leftPhotos.followedBy(month.rightPhotos)) {
      if (photo.mediaItem != null) {
        preselected.add(photo.mediaItem!.asset.id);
        if (photo.imageBytes != null && photo.imageBytes!.isNotEmpty) {
          preselectedShots[photo.mediaItem!.asset.id] = photo.imageBytes!;
        }
      } else if (photo.assetId != null) {
        preselected.add(photo.assetId!);
        if (photo.imageBytes != null && photo.imageBytes!.isNotEmpty) {
          preselectedShots[photo.assetId!] = photo.imageBytes!;
        }
      }
    }
    final selections = await _pickPhotos(
      limit: _photosPerMonth,
      preselectedAssetIds: preselected,
      preselectedScreenshots: preselectedShots,
    );
    if (selections == null || selections.isEmpty) return;

    int cursor = 0;
    void assign(List<AlbumPhoto> targets) {
      for (int i = 0; i < targets.length; i++) {
        if (cursor < selections.length) {
          targets[i] = selections[cursor++];
        } else {
          targets[i] = const AlbumPhoto();
        }
      }
    }

    assign(month.leftPhotos);
    assign(month.rightPhotos);
    setState(() {
      _monthSignals[monthIndex].value = _monthSignals[monthIndex].value + 1;
    });
    unawaited(_saveLayout());
    _jumpToCurrentPage();
  }

  void _jumpToCurrentPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageFlipController.goToPage(_currentPageIndex);
    });
  }

  PageRoute<Uint8List?> _buildVideoDetailRoute(MediaItem mediaItem) {
    return PageRouteBuilder<Uint8List?>(
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => DetailVideoPage(item: mediaItem),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }
}

class AlbumSpread extends StatelessWidget {
  const AlbumSpread({
    super.key,
    required this.month,
    required this.monthIndex,
    required this.onPhotoDropped,
    required this.onPhotoTapped,
    required this.onEditMonth,
    required this.onDragStateChanged,
    required this.updateSignal,
  });

  final AlbumMonth month;
  final int monthIndex;
  final void Function(PhotoDragData data, bool targetIsLeft, int targetIndex) onPhotoDropped;
  final void Function(int monthIndex, bool isLeft, int targetIndex) onPhotoTapped;
  final VoidCallback onEditMonth;
  final ValueChanged<bool> onDragStateChanged;
  final ValueListenable<int> updateSignal;

  BoxDecoration _pageDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: updateSignal,
      builder: (context, value, child) {
        return Row(
          children: [
            Expanded(
              child: Container(
                decoration: _pageDecoration(),
                padding: _pagePadding,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _leftPagePhotoSlots + 1,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: _gridSpacing,
                    mainAxisSpacing: _gridSpacing,
                    childAspectRatio: _slotAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return MonthLabelBox(
                        month: month,
                        onEditMonth: onEditMonth,
                      );
                    }
                    final photoIndex = index - 1;
                    return _ReorderablePhotoSlot(
                      photo: month.leftPhotos[photoIndex],
                      dragData: PhotoDragData(
                        monthIndex: monthIndex,
                        isLeft: true,
                        photoIndex: photoIndex,
                      ),
                      targetIndex: photoIndex,
                      targetIsLeft: true,
                      onAccept: onPhotoDropped,
                      onDragStateChanged: onDragStateChanged,
                      onTap: () => onPhotoTapped(monthIndex, true, photoIndex),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: _pageGap),
            Expanded(
              child: Container(
                decoration: _pageDecoration(),
                padding: _pagePadding,
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _rightPagePhotoSlots,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: _gridSpacing,
                    mainAxisSpacing: _gridSpacing,
                    childAspectRatio: _slotAspectRatio,
                  ),
                  itemBuilder: (context, index) {
                    return _ReorderablePhotoSlot(
                      photo: month.rightPhotos[index],
                      dragData: PhotoDragData(
                        monthIndex: monthIndex,
                        isLeft: false,
                        photoIndex: index,
                      ),
                      targetIndex: index,
                      targetIsLeft: false,
                      onAccept: onPhotoDropped,
                      onDragStateChanged: onDragStateChanged,
                      onTap: () => onPhotoTapped(monthIndex, false, index),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class MonthLabelBox extends StatelessWidget {
  const MonthLabelBox({super.key, required this.month, required this.onEditMonth});

  final AlbumMonth month;
  final VoidCallback onEditMonth;

  @override
  Widget build(BuildContext context) {
    final colors = monthGradients[(month.order - 1) % monthGradients.length];
    return GestureDetector(
      onTap: onEditMonth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: Text(
            month.name,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class PhotoSlot extends StatelessWidget {
  const PhotoSlot({super.key, required this.photo});

  final AlbumPhoto photo;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16);
    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: Colors.black12, width: 1.4),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _buildImageContent()),
            if (photo.mediaItem?.type == MediaType.video)
              const Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.play_circle_fill, color: Colors.white, size: 22),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (photo.imageBytes != null && photo.imageBytes!.isNotEmpty) {
      return Image.memory(
        photo.imageBytes!,
        fit: BoxFit.cover,
      );
    }
    if (photo.mediaItem != null) {
      return FutureBuilder<Uint8List?>(
        future: photo.mediaItem!.asset.thumbnailDataWithSize(const ThumbnailSize(400, 400)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return Image.memory(snapshot.data!, fit: BoxFit.cover);
        },
      );
    }

    if (photo.imageUrl != null && photo.imageUrl!.isNotEmpty) {
      return Image.network(
        photo.imageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return const Center(
            child: Icon(Icons.broken_image_outlined, color: Colors.black45),
          );
        },
      );
    }

    return const Center(
      child: Text(
        'EMPTY',
        style: TextStyle(
          color: Colors.black45,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class AlbumMonth {
  AlbumMonth({
    required this.name,
    required this.order,
    required List<AlbumPhoto> leftPhotos,
    required List<AlbumPhoto> rightPhotos,
  })  : leftPhotos = List<AlbumPhoto>.from(leftPhotos),
        rightPhotos = List<AlbumPhoto>.from(rightPhotos);

  final String name;
  final int order;
  final List<AlbumPhoto> leftPhotos;
  final List<AlbumPhoto> rightPhotos;
}

class PhotoDragData {
  const PhotoDragData({
    required this.monthIndex,
    required this.isLeft,
    required this.photoIndex,
  });

  final int monthIndex;
  final bool isLeft;
  final int photoIndex;
}

class _ReorderablePhotoSlot extends StatelessWidget {
  const _ReorderablePhotoSlot({
    required this.photo,
    required this.dragData,
    required this.targetIndex,
    required this.targetIsLeft,
    required this.onAccept,
    required this.onDragStateChanged,
    this.onTap,
  });

  final AlbumPhoto photo;
  final PhotoDragData dragData;
  final int targetIndex;
  final bool targetIsLeft;
  final void Function(PhotoDragData data, bool targetIsLeft, int targetIndex) onAccept;
  final ValueChanged<bool> onDragStateChanged;
  final VoidCallback? onTap;

  Widget _buildPhoto() => PhotoSlot(photo: photo);

  @override
  Widget build(BuildContext context) {
    return DragTarget<PhotoDragData>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        return data.monthIndex == dragData.monthIndex &&
            (data.isLeft != targetIsLeft || data.photoIndex != targetIndex);
      },
      onAcceptWithDetails: (details) {
        onAccept(details.data, targetIsLeft, targetIndex);
      },
      builder: (context, candidate, rejected) {
        final highlighted = candidate.isNotEmpty;
        final displayPhoto = _buildPhoto();
        final slot = AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: highlighted ? Border.all(color: Colors.black45, width: 2) : null,
          ),
          padding: highlighted ? const EdgeInsets.all(2) : EdgeInsets.zero,
          child: Listener(
            onPointerDown: (_) => onDragStateChanged(true),
            onPointerUp: (_) => onDragStateChanged(false),
            onPointerCancel: (_) => onDragStateChanged(false),
            child: LongPressDraggable<PhotoDragData>(
              data: dragData,
              feedback: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 120,
                  height: 140,
                  child: _buildPhoto(),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.2,
                child: _buildPhoto(),
              ),
              child: GestureDetector(
                onTap: onTap,
                child: displayPhoto,
              ),
              onDragStarted: () => onDragStateChanged(true),
              onDragEnd: (_) => onDragStateChanged(false),
              onDraggableCanceled: (velocity, offset) => onDragStateChanged(false),
              onDragCompleted: () => onDragStateChanged(false),
            ),
          ),
        );
        return slot;
      },
    );
  }
}

class _DragBlockerGestureRecognizer extends HorizontalDragGestureRecognizer {
  @override
  void addPointer(PointerDownEvent event) {
    super.addPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
    super.rejectGesture(pointer);
  }
}

List<AlbumMonth> _generateAlbumMonths(List<AlbumPhoto> selectedPhotos) {
  final Queue<AlbumPhoto> queue = Queue<AlbumPhoto>.from(selectedPhotos);
  return List<AlbumMonth>.generate(
    _monthNames.length,
    (index) {
      final left = _buildPhotoSet(queue, 5);
      final right = _buildPhotoSet(queue, 6);
      return AlbumMonth(
        name: _monthNames[index],
        order: index + 1,
        leftPhotos: left,
        rightPhotos: right,
      );
    },
  );
}

const List<List<Color>> monthGradients = [
  [Color(0xFFF5F5F5), Color(0xFFEEEEEE)],
  [Color(0xFFE0E0E0), Color(0xFFBDBDBD)],
  [Color(0xFFD7CCC8), Color(0xFFB0BEC5)],
  [Color(0xFFECEFF1), Color(0xFFCFD8DC)],
  [Color(0xFFE8EAF6), Color(0xFFC5CAE9)],
  [Color(0xFFF0F0F0), Color(0xFFD6D6D6)],
];

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

List<AlbumPhoto> _buildPhotoSet(Queue<AlbumPhoto> queue, int count) {
  return List<AlbumPhoto>.generate(
    count,
    (offset) {
      if (queue.isNotEmpty) {
        return queue.removeFirst();
      }
      return const AlbumPhoto();
    },
  );
}
