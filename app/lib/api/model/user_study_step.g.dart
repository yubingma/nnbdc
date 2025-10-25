// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_study_step.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserStudyStep _$UserStudyStepFromJson(Map<String, dynamic> json) =>
    UserStudyStep(
      stepId: (json['stepId'] as num).toInt(),
      name: json['name'] as String,
      description: json['description'] as String,
      isCompleted: json['isCompleted'] as bool? ?? false,
    );

Map<String, dynamic> _$UserStudyStepToJson(UserStudyStep instance) =>
    <String, dynamic>{
      'stepId': instance.stepId,
      'name': instance.name,
      'description': instance.description,
      'isCompleted': instance.isCompleted,
    };
