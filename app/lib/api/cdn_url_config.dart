/// CDN URL配置类
class CdnUrlConfig {
  final String? fileUrls;
  final String? dirUrls;

  CdnUrlConfig({this.fileUrls, this.dirUrls});

  factory CdnUrlConfig.fromJson(Map<String, dynamic> json) {
    return CdnUrlConfig(
      fileUrls: json['fileUrls'] as String?,
      dirUrls: json['dirUrls'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fileUrls': fileUrls,
      'dirUrls': dirUrls,
    };
  }
}

