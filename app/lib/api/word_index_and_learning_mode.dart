import 'package:json_annotation/json_annotation.dart';

part 'word_index_and_learning_mode.g.dart';

/// 单词索引和学习模式
@JsonSerializable()
class WordIndexAndLearningMode {
  final int wordIndex;
  final int learningMode;

  WordIndexAndLearningMode({
    required this.wordIndex,
    required this.learningMode,
  });

  factory WordIndexAndLearningMode.fromJson(Map<String, dynamic> json) => _$WordIndexAndLearningModeFromJson(json);
  Map<String, dynamic> toJson() => _$WordIndexAndLearningModeToJson(this);
} 