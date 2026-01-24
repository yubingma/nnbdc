# Android 端 ASR (语音识别) 方案文档

本文档记录了项目中 Android 端语音识别（ASR）的架构、资源来源、关键配置及升级指南，以便未来维护和升级。

## 1. 架构方案：Sherpa-ONNX

由于 `sherpa-ncnn` 在 Android 某些机型上的兼容性限制（特别是 JNI 签名和模型加载问题），本项目目前采用了 **Sherpa-ONNX** 方案。

*   **官方仓库**: [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
*   **API 类型**: 通用 Java API（配合底层的 C++ JNI 库）。
*   **运行时**: ONNX Runtime (Quantized)。

## 2. 资源来源

### 2.1 底层库 (.so 文件)
*   **版本**: v1.10.30+
*   **路径**: `app/android/app/src/main/jniLibs/` (包含 arm64-v8a 和 armeabi-v7a)
*   **主要依赖**: `libonnxruntime.so`, `libsherpa-onnx-jni.so`

### 2.2 识别模型 (Streaming Zipformer)
模型存放在 `app/android/app/src/main/assets/` 目录下，并会在首次运行时复制到 App 缓存目录进行加载。

| 语言 | 模型名称 | 模型来源 (GitHub/HuggingFace) |
| :--- | :--- | :--- |
| **中文** | `sherpa-onnx-streaming-zipformer-zh-13M-2023-02-16` | [k2-fsa @ HuggingFace](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-zh-13M-2023-02-16) |
| **英文** | `sherpa-onnx-streaming-zipformer-en-20M-2023-02-17` | [k2-fsa @ HuggingFace](https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-en-20M-2023-02-17) |

## 3. 核心源码结构

1.  **Kotlin 业务逻辑 (`Sherpa.kt`)**:
    *   管理录音生命周期 (`AudioRecord`).
    *   动态加载/切换中英文模型。
    *   实现音频原始数据 (`ShortArray`) 到识别模型输入 (`FloatArray`) 的转换。
    *   **软件增益 (Software Gain)**: 目前设置为 8.0x (可根据需要微调)，解决麦克风电平过低问题。
2.  **Java API 封装 (com.k2fsa.sherpa.onnx)**:
    *   直接引入了官方的 Java 接口文件，绕开了 Android 特定 AssetsManager 的 JNI 兼容性问题。

## 4. 关键配置参数

| 参数名 | 当前值 | 说明 |
| :--- | :--- | :--- |
| **采样率** | 16000 Hz | 模型的硬性要求。 |
| **线程数** | 2 | 并行处理线程，平衡性能与耗电。 |
| **解码模式** | `modified_beam_search` | 对于英文识别准确率最高，但 CPU 消耗略大。 |
| **端点检测** | Rule 1: 10s / Rule 2: 5s | 对于背单词场景，设置了极宽松的静音自动重置时间。 |
| **热词权重** | 3.5 | (已部分回退) 可增加特定单词的命中率。 |

## 5. 升级指南

如果您需要升级识别方案，请遵循以下步骤：

1.  **升级底层库**:
    从 [sherpa-onnx releases](https://github.com/k2-fsa/sherpa-onnx/releases) 下载最新的 Android 预编译二进制文件，替换 `jniLibs` 中的文件。
2.  **更换模型**:
    *   下载新的模型文件夹放入 `assets/`。
    *   修改 `Sherpa.kt` 中对应的 `modelDir` 和 `modelConfig` (如 encoder/decoder 文件名)。
3.  **重新编译**:
    如果 Java 接口没有变动，直接构建即可。如果变动，请同步更新 `src/main/java/com/k2fsa/sherpa/onnx/` 下的文件。

## 6. 特别注意：JNI 与文件加载
Sherpa-ONNX 在 Android 上直接从 Assets 读取模型时有时会出现内存对齐报错。目前的方案是 **“Assets -> Cache File -> Load Path”**：
1.  检查缓存目录是否有模型。
2.  如果没有，从 Assets 复制到缓存。
3.  传递缓存文件的 **绝对路径** 给 C++ 引擎。
这样做虽然首次启动慢几秒，但稳定性最高，解决了 99% 的黑盒模型加载失败问题。
