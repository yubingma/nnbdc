import 'package:json_annotation/json_annotation.dart';

part 'user_study_step.g.dart';

/// 用户学习步骤
@JsonSerializable()
class UserStudyStep {
  final int stepId;
  final String name;
  final String description;
  final bool isCompleted;

  UserStudyStep({
    required this.stepId,
    required this.name,
    required this.description,
    this.isCompleted = false,
  });

  factory UserStudyStep.fromJson(Map<String, dynamic> json) => _$UserStudyStepFromJson(json);
  Map<String, dynamic> toJson() => _$UserStudyStepToJson(this);
} 