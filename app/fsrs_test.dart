import 'dart:math';

import 'package:flutter/material.dart';

enum FsrsRating { again, hard, good, easy }
extension FsrsRatingExt on FsrsRating {
  int get value {
    switch (this) {
      case FsrsRating.again: return 1;
      case FsrsRating.hard: return 2;
      case FsrsRating.good: return 3;
      case FsrsRating.easy: return 4;
    }
  }
}

class FSRS {
  static const List<double> defaultWeights = [
    0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01, 1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61
  ];
  final double requestRetention = 0.9;
  final List<double> w = defaultWeights;

  int calculateNext(double s, double d, FsrsRating rating, int elapsedDays) {
    double r = pow(0.9, elapsedDays / s).toDouble(); // Retrievability
    double nextD = d - w[6] * (rating.value - 3);
    nextD = _meanReversion(w[4], nextD);
    nextD = nextD.clamp(1.0, 10.0);
    double nextS;
    if (rating == FsrsRating.again) {
      nextS = w[7] * pow(nextD, -w[8]) * (pow(s + 1, w[9]) - 1) * exp(w[10] * (1 - r));
    } else {
      double hardPenalty = (rating == FsrsRating.hard) ? w[15] : 1.0;
      double easyBonus = (rating == FsrsRating.easy) ? w[16] : 1.0;
      nextS = s * (1 + exp(w[11]) * (11 - nextD) * pow(s, -w[12]) * (exp((1 - r) * w[13]) - 1) * hardPenalty * easyBonus);
    }
    nextS = max(nextS, 0.1);
    double interval = nextS * (log(requestRetention) / log(0.9));
    return max(1, interval.round());
  }

  double _meanReversion(double init, double current) {
    return 0.05 * init + 0.95 * current;
  }
}
void main() {
  var fsrs = FSRS();
  debugPrint("Testing various values...");
  List<List<double>> cases = [
    [2.4, 3.0, 1.0], // S, D, elapsed
    [2.4, 3.0, 2.0],
    [5.8, 3.0, 6.0],
    [5.8, 3.0, 0.0],
    [10.0, 5.0, 0.0]
  ];
  
  for(var c in cases) {
    debugPrint("\nElapsed: ${c[2]}, S=${c[0]}, D=${c[1]}");
    for (var rating in FsrsRating.values) {
      debugPrint("${rating.name}: ${fsrs.calculateNext(c[0], c[1], rating, c[2].toInt())}");
    }
  }
}
