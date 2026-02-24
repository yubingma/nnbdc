import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class ToastUtil {
  static void info(String info, {Duration? autoCloseDuration = const Duration(seconds: 3)}) {
    toastification.show(
      title: Text(
        info,
        maxLines: 10,
        softWrap: true,
      ),
      autoCloseDuration: autoCloseDuration,
      type: ToastificationType.info,
      style: ToastificationStyle.fillColored,
      showProgressBar: false,
    );
  }

  static void error(String info, {Duration? autoCloseDuration = const Duration(seconds: 3)}) {
    toastification.show(
      title: Text(
        info,
        maxLines: 10,
        softWrap: true,
      ),
      autoCloseDuration: autoCloseDuration,
      type: ToastificationType.error,
      style: ToastificationStyle.fillColored,
      showProgressBar: false,
    );
  }

  static void success(String info, {Duration? autoCloseDuration = const Duration(seconds: 3)}) {
    toastification.show(
      title: Text(
        info,
        maxLines: 10,
        softWrap: true,
      ),
      autoCloseDuration: autoCloseDuration,
      type: ToastificationType.success,
      style: ToastificationStyle.fillColored,
      showProgressBar: false,
    );
  }
}
