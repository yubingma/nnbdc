import os

def replace_in_file(filepath, target, replacement):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    if target in content:
        content = content.replace(target, replacement)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"Successfully replaced in {filepath}")
    else:
        print(f"Target not found in {filepath}: {target[:50]}...")

# 1. Modify asr.dart
asr_path = "/Volumes/ssd/ppdc/app/lib/util/asr.dart"
replace_in_file(
    asr_path,
    "  Future<void> startAsr(AsrLanguage language) async {",
    "  Future<void> startAsr(AsrLanguage language) async {\n    debugPrint('💡 [ASR] startAsr() 触发启动。目标语言: ${language.locale}，当前状态: $state。堆栈:\\n${StackTrace.current}');"
)

replace_in_file(
    asr_path,
    "  Future<void> stopMicrophone() async {",
    "  Future<void> stopMicrophone() async {\n    debugPrint('💡 [ASR] stopMicrophone() 触发关停。当前状态: $state。调用来源及堆栈:\\n${StackTrace.current}');"
)
