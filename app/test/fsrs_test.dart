import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/fsrs.dart';

void main() {
  group('FSRS Algorithm Init', () {
    late FSRS fsrs;

    setUp(() {
      fsrs = FSRS(); // Using default configuration
    });

    test('init with FsrsRating.again', () {
      var item = fsrs.init(FsrsRating.again);
      // w[0] = 0.4
      expect(item.stability, 0.4);
      // difficulty = w[4] - (1-1)*w[5] = 4.93
      expect(item.difficulty, 4.93);
      expect(item.elapsedDays, 0);
      expect(item.scheduledDays, greaterThanOrEqualTo(0));
      expect(item.reps, 1);
      expect(item.lapses, 1);
      expect(item.state, FsrsState.learning);
    });

    test('init with FsrsRating.hard', () {
      var item = fsrs.init(FsrsRating.hard);
      // w[1] = 0.6
      expect(item.stability, 0.6);
      expect(item.lapses, 0);
      expect(item.state, FsrsState.learning);
    });

    test('init with FsrsRating.good', () {
      var item = fsrs.init(FsrsRating.good);
      // w[2] = 2.4
      expect(item.stability, 2.4);
      expect(item.lapses, 0);
      expect(item.state, FsrsState.learning);
    });

    test('init with FsrsRating.easy', () {
      var item = fsrs.init(FsrsRating.easy);
      // w[3] = 5.8
      expect(item.stability, 5.8);
      expect(item.lapses, 0);
      expect(item.state, FsrsState.learning);
    });

    test('init clamps difficulty', () {
      // Modify weights mapping to check clamp
      var customFsrs = FSRS(w: [
        0.4, 0.6, 2.4, 5.8, 
        0.5, // w[4] = 0.5 (initial difficulty base)
        5.0, // w[5] = 5.0 (difficulty multiplier)
        0.86, 0.01, 1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61
      ]);
      
      // rating "easy" = value 4
      // diff = w[4] - (4-1)*w[5] = 0.5 - 3 * 5.0 = -14.5 -> clamped to 1.0!
      var item = customFsrs.init(FsrsRating.easy);
      expect(item.difficulty, 1.0);
    });
  });

  group('FSRS Algorithm Next', () {
    late FSRS fsrs;
    late FSRSItem initialItem;

    setUp(() {
      fsrs = FSRS();
      initialItem = fsrs.init(FsrsRating.good);
    });

    test('next with FsrsRating.good increases stability', () {
      var nextItem = fsrs.next(initialItem, FsrsRating.good, 1);
      
      expect(nextItem.stability, greaterThan(initialItem.stability));
      expect(nextItem.reps, initialItem.reps + 1);
      expect(nextItem.lapses, initialItem.lapses);
      expect(nextItem.state, FsrsState.review);
      expect(nextItem.elapsedDays, 1);
      expect(nextItem.scheduledDays, greaterThan(initialItem.scheduledDays));
    });

    test('next with FsrsRating.again decreases stability drastically', () {
      var nextItem = fsrs.next(initialItem, FsrsRating.again, 1);
      
      expect(nextItem.stability, lessThan(initialItem.stability));
      expect(nextItem.reps, initialItem.reps + 1);
      expect(nextItem.lapses, initialItem.lapses + 1);
      expect(nextItem.state, FsrsState.relearning);
    });

    test('next with FsrsRating.hard vs good vs easy', () {
      var hardItem = fsrs.next(initialItem, FsrsRating.hard, 1);
      var goodItem = fsrs.next(initialItem, FsrsRating.good, 1);
      var easyItem = fsrs.next(initialItem, FsrsRating.easy, 1);

      expect(hardItem.stability, lessThan(goodItem.stability));
      expect(goodItem.stability, lessThan(easyItem.stability));
      
      expect(hardItem.difficulty, greaterThan(goodItem.difficulty));
      expect(goodItem.difficulty, greaterThan(easyItem.difficulty));
    });

    test('difficulty remains within [1.0, 10.0]', () {
      var item = fsrs.init(FsrsRating.again);
      // Repeatedly get again to maximize difficulty
      for (var i = 0; i < 10; i++) {
        item = fsrs.next(item, FsrsRating.again, 0);
      }
      expect(item.difficulty, lessThanOrEqualTo(10.0));

      item = fsrs.init(FsrsRating.easy);
      // Repeatedly get easy to minimize difficulty
      for (var i = 0; i < 10; i++) {
        item = fsrs.next(item, FsrsRating.easy, 5);
      }
      expect(item.difficulty, greaterThanOrEqualTo(1.0));
    });

    test('stability minimum clamp is 0.1', () {
      var item = initialItem;
      // Get it repeatedly wrong to tank stability
      for (var i = 0; i < 10; i++) {
        item = fsrs.next(item, FsrsRating.again, 0);
      }
      expect(item.stability, greaterThanOrEqualTo(0.1));
    });
  });

  group('FSRS Config', () {
    test('calculate interval depends on retention', () {
      var fsrsNormal = FSRS(requestRetention: 0.9);
      var fsrsStrict = FSRS(requestRetention: 0.95);
      
      var item1 = fsrsNormal.init(FsrsRating.good);
      var item2 = fsrsStrict.init(FsrsRating.good);

      // strict retention -> shorter reviews
      expect(item2.scheduledDays, lessThan(item1.scheduledDays));
    });
  });
}
