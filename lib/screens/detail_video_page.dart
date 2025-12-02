import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/media_item.dart';

class DetailVideoPage extends StatefulWidget {
  const DetailVideoPage({super.key, required this.item});

  final MediaItem item;

  @override
  State<DetailVideoPage> createState() => _DetailVideoPageState();
}

class _DetailVideoPageState extends State<DetailVideoPage> {
  VideoPlayerController? _controller;
  String? _videoPath;
  bool _isGeneratingImage = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareVideo();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepareVideo() async {
    try {
      final file = await widget.item.asset.file;
      if (!mounted) return;
      if (file == null) {
        setState(() {
          _error = 'ไม่สามารถเปิดไฟล์วิดีโอได้';
          _isLoading = false;
        });
        return;
      }
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _videoPath = file.path;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'เกิดข้อผิดพลาดในการโหลดวีดีโอ';
        _isLoading = false;
      });
    }
  }

  Future<Uint8List?> _captureFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _videoPath == null) {
      return null;
    }

    setState(() {
      _isGeneratingImage = true;
    });
    try {
      final currentPosition = controller.value.position.inMilliseconds;
      final framePosition = currentPosition > 0 ? currentPosition : 0;
      final data = await VideoThumbnail.thumbnailData(
        video: _videoPath!,
        imageFormat: ImageFormat.PNG,
        timeMs: framePosition,
        quality: 90,
      );
      if (!mounted) return null;
      return data;
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingImage = false;
        });
      }
    }
  }

  Future<void> _confirmCaptureFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _videoPath == null) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการแคปภาพ'),
        content: const Text('ต้องการแคปภาพจากเฟรมนี้และนำไปใส่ในอัลบั้มหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final bytes = await _captureFrame();
    if (bytes != null && mounted) {
      Navigator.of(context).pop(bytes);
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final controllerValue = controller.value;
    if (controllerValue.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  void _seekBy(Duration offset) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final value = controller.value;
    var target = value.position + offset;
    if (target < Duration.zero) {
      target = Duration.zero;
    }
    if (value.duration != Duration.zero && target > value.duration) {
      target = value.duration;
    }
    controller.seekTo(target);
  }

  Widget _buildControlButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = primary
        ? colorScheme.primary
        : colorScheme.surfaceContainerHighest;
    final iconColor = primary ? Colors.white : colorScheme.onSurfaceVariant;

    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        splashRadius: 40,
        icon: Icon(
          icon,
          color: iconColor,
          size: 32,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกเฟรมจากวีดีโอ'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _buildVideoPreview(controller),
              ),
            ),
            if (controller != null && controller.value.isInitialized) ...[
              const SizedBox(height: 16),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final duration = value.duration;
                  final position = value.position;
                  final totalMillis = duration.inMilliseconds;
                  final sliderMax =
                      totalMillis > 0 ? totalMillis.toDouble() : 1.0;
                  final sliderValue = position.inMilliseconds
                      .clamp(0, totalMillis > 0 ? totalMillis : 1)
                      .toDouble();
                  final canScrub = totalMillis > 0;
                  return Column(
                    children: [
                      Slider(
                        value: sliderValue,
                        max: sliderMax,
                        onChanged: canScrub
                            ? (newValue) {
                                controller.seekTo(
                                  Duration(milliseconds: newValue.round()),
                                );
                              }
                            : null,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildControlButton(
                            context,
                            icon: Icons.fast_rewind,
                            onPressed: () =>
                                _seekBy(const Duration(seconds: -5)),
                          ),
                          const SizedBox(width: 20),
                          _buildControlButton(
                            context,
                            icon: value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            onPressed: _togglePlayback,
                            primary: true,
                          ),
                          const SizedBox(width: 20),
                          _buildControlButton(
                            context,
                            icon: Icons.fast_forward,
                            onPressed: () =>
                                _seekBy(const Duration(seconds: 5)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  _isGeneratingImage || controller == null ? null : _confirmCaptureFrame,
              icon: _isGeneratingImage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera),
              label: Text(
                _isGeneratingImage ? 'กำลังแคปภาพ...' : 'แคปภาพจากวีดีโอ',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreview(VideoPlayerController? controller) {
    if (_isLoading) {
      return const CircularProgressIndicator();
    }
    if (_error != null) {
      return Text(
        _error!,
        style: const TextStyle(color: Colors.redAccent),
        textAlign: TextAlign.center,
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Text('ไม่สามารถแสดงวีดีโอได้');
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }
}
