import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class ToastUtil {
  static void info(String info) {
    toastification.show(
      title: Text(
        info,
        softWrap: true,
      ),
      autoCloseDuration: const Duration(seconds: 3),
      type: ToastificationType.info,
      style: ToastificationStyle.fillColored,
      showProgressBar: false,
    );
  }

  static void error(String info) {
    toastification.show(
      title: Text(
        info,
        maxLines: 5,
        softWrap: true,
      ),
      autoCloseDuration: const Duration(seconds: 3),
      type: ToastificationType.error,
      style: ToastificationStyle.fillColored,
      showProgressBar: false,
    );
  }

  static void success(String info) {
    toastification.show(
      title: Text(
        info,
        softWrap: true,
      ),
      autoCloseDuration: const Duration(seconds: 3),
      type: ToastificationType.success,
      style: ToastificationStyle.fillColored,
      showProgressBar: false,
    );
  }
}
