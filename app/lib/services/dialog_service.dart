import 'package:flutter/material.dart';

class DialogService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static BuildContext? get context => navigatorKey.currentContext;

  static Future<T?> showDialog<T>(Widget widget, {bool barrierDismissible = true}) {
    if (context == null) return Future.value(null);
    return showGeneralDialog<T>(
      context: context!,
      barrierDismissible: barrierDismissible,
      barrierLabel: '',
      pageBuilder: (context, animation, secondaryAnimation) => widget,
    );
  }

  static void pop<T>([T? result]) {
    if (context != null && Navigator.canPop(context!)) {
      Navigator.pop(context!, result);
    }
  }

  static void showSnackBar(String message) {
    if (context != null) {
      ScaffoldMessenger.of(context!).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}
