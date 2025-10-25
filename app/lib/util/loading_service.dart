import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

class LoadingService {
  static final LoadingService _instance = LoadingService._internal();

  factory LoadingService() {
    return _instance;
  }

  LoadingService._internal();

  bool _isShowing = false;
  bool _isDismissible = true;
  String _status = '';
  double _progress = 0.0;
  bool _isProgress = false;
  Timer? _timer;
  OverlayEntry? _overlayEntry;
  final Duration _defaultDuration = const Duration(milliseconds: 20000);

  // 配置选项
  Color progressColor = Colors.yellow;
  Color backgroundColor = Colors.blue;
  Color indicatorColor = Colors.yellow;
  Color textColor = Colors.yellow;
  Color maskColor = Colors.transparent;
  bool userInteractions = false;
  bool dismissOnTap = false;
  double indicatorSize = 45.0;
  double radius = 10.0;

  void init() {
    // 初始化默认设置
    progressColor = Colors.yellow;
    backgroundColor = Colors.blue;
    indicatorColor = Colors.yellow;
    textColor = Colors.yellow;
    maskColor = Colors.transparent;
    userInteractions = false;
    dismissOnTap = false;
    indicatorSize = 45.0;
    radius = 10.0;
  }

  Future<void> show({String status = 'loading...', bool dismissOnTap = false, Color? maskColor}) async {
    if (_isShowing) {
      await dismiss();
    }

    _status = status;
    _isProgress = false;
    _isDismissible = dismissOnTap;
    _isShowing = true;

    _createOverlay();
  }

  Future<void> showProgress(double progress, {String? status}) async {
    if (_isShowing && !_isProgress) {
      await dismiss();
    }

    _progress = progress.clamp(0.0, 1.0);
    _status = status ?? '';
    _isProgress = true;
    _isShowing = true;

    if (_overlayEntry == null) {
      _createOverlay();
    } else {
      _updateOverlay();
    }
  }

  Future<void> dismiss() async {
    if (!_isShowing) {
      return;
    }

    _timer?.cancel();
    _timer = null;

    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }

    _isShowing = false;
    _isProgress = false;
  }

  void _createOverlay() {
    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onTap: _isDismissible ? () => dismiss() : null,
            behavior: HitTestBehavior.translucent,
            child: Container(
              color: maskColor,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              child: Center(
                child: _buildLoadingWidget(),
              ),
            ),
          ),
        );
      },
    );

    // 添加到Overlay
    if (Get.overlayContext != null) {
      Overlay.of(Get.overlayContext!).insert(_overlayEntry!);
    }

    // 设置自动消失
    _timer?.cancel();
    _timer = Timer(_defaultDuration, () {
      dismiss();
    });
  }

  void _updateOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  Widget _buildLoadingWidget() {
    if (_isProgress) {
      return _buildProgressWidget();
    } else {
      return _buildCircularWidget();
    }
  }

  Widget _buildCircularWidget() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(indicatorColor),
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Text(
                _status,
                style: TextStyle(color: textColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressWidget() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularPercentIndicator(
            radius: indicatorSize,
            lineWidth: 8.0,
            percent: _progress,
            center: Text(
              "${(_progress * 100).toStringAsFixed(0)}%",
              style: TextStyle(color: textColor),
            ),
            progressColor: progressColor,
            backgroundColor: Colors.grey,
            animation: true,
            animateFromLastPercent: true,
            circularStrokeCap: CircularStrokeCap.round,
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: Text(
                _status,
                style: TextStyle(color: textColor),
              ),
            ),
        ],
      ),
    );
  }
}
