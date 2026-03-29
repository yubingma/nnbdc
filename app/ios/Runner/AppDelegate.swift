import UIKit
import Flutter
import Speech
import AVFoundation
import AVFAudio
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    // MARK: - Properties
    
    // ASR 相关属性
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var eventSink: FlutterEventSink?
    private var meterEventSink: FlutterEventSink?
    private var isAsrStopped = true
    private var isRecording = false
    private var currentLocale = "zh-CN" // 默认中文，用于识别单词释义
    private var isAudioEngineInitialized = false // 跟踪 audioEngine 是否已初始化
    private var skippedBufferCount = 0 // 跟踪跳过的缓冲区数量
    private var contextualPhrases: [String] = [] // 上下文短语，用于 bias
    
    // Stream handlers
    private var asrStreamHandler: SimpleStreamHandler?
    private var meterStreamHandler: SimpleStreamHandler?
    private var ttsStreamHandler: SimpleStreamHandler?
    
    // TTS 相关属性
    private var ttsEventSink: FlutterEventSink?
    private var synthesizer = AVSpeechSynthesizer()
    private var currentUtteranceId: String?
    
    // ASR 实时性优化
    private var lastPartialResult: String = ""
    private var partialResultTimer: Timer?
    private var lastMeterSentAt: TimeInterval = 0
    private var pausedLogCounter = 0
    
    // MARK: - Application Lifecycle
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Set up Umeng
        if let umURLProtocolClass = NSClassFromString("UMURLProtocol") as? AnyClass {
            URLProtocol.registerClass(umURLProtocolClass)
        }
        let apmConfig = UMAPMConfig.default()
        apmConfig.networkEnable = true
        UMCrashConfigure.setAPMConfig(apmConfig)

        // DO NOT ACCESS window?.rootViewController BEFORE super.application()
        // OR WITHOUT CREATING IT, especially if SceneDelegate is not yet taking over correctly.
        // It's safer to let the engine initialize first.
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
        
        GeneratedPluginRegistrant.register(with: self)

        // Ensure window exists or create it
        if window == nil {
            window = UIWindow(frame: UIScreen.main.bounds)
        }
        
        let controller: FlutterViewController
        if let rootVc = window?.rootViewController as? FlutterViewController {
            controller = rootVc
        } else {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            if let vc = storyboard.instantiateInitialViewController() as? FlutterViewController {
                controller = vc
            } else {
                controller = FlutterViewController()
            }
            window?.rootViewController = controller
        }
        window?.makeKeyAndVisible()
        
        // 设置 ASR MethodChannel
        let methodChannel = FlutterMethodChannel(
            name: "nnbdc/asr_commands",
            binaryMessenger: controller.binaryMessenger
        )
        methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleMethodCall(call: call, result: result)
        }
        
        // 设置 ASR EventChannel
        let eventChannel = FlutterEventChannel(
            name: "nnbdc/asr_events",
            binaryMessenger: controller.binaryMessenger
        )
        self.asrStreamHandler = SimpleStreamHandler(onListen: { [weak self] events in
            self?.eventSink = events
        }, onCancel: { [weak self] in
            self?.eventSink = nil
        })
        eventChannel.setStreamHandler(self.asrStreamHandler)

        // 设置 ASR Meter EventChannel（音量/波形强度）
        let meterChannel = FlutterEventChannel(
            name: "nnbdc/asr_meter",
            binaryMessenger: controller.binaryMessenger
        )
        self.meterStreamHandler = SimpleStreamHandler(onListen: { [weak self] events in
            self?.meterEventSink = events
        }, onCancel: { [weak self] in
            self?.meterEventSink = nil
        })
        meterChannel.setStreamHandler(self.meterStreamHandler)
        
        // 设置 TTS MethodChannel
        let ttsMethodChannel = FlutterMethodChannel(
            name: "nnbdc/tts_commands",
            binaryMessenger: controller.binaryMessenger
        )
        ttsMethodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleTtsMethodCall(call: call, result: result)
        }
        
        // 设置 TTS EventChannel
        let ttsEventChannel = FlutterEventChannel(
            name: "nnbdc/tts_events",
            binaryMessenger: controller.binaryMessenger
        )
        self.ttsStreamHandler = SimpleStreamHandler(onListen: { [weak self] events in
            self?.ttsEventSink = events
            let event: [String: Any] = ["type": "initStatus", "data": 0]
            events(event)
        }, onCancel: { [weak self] in
            self?.ttsEventSink = nil
        })
        ttsEventChannel.setStreamHandler(self.ttsStreamHandler)
        
        // 设置应用评分 MethodChannel
        let reviewChannel = FlutterMethodChannel(
            name: "com.nnbdc.review",
            binaryMessenger: controller.binaryMessenger
        )
        reviewChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            self?.handleReviewMethodCall(call: call, result: result)
        }
        // 初始化语音识别器
        setupSpeechRecognizer()
        
        // 初始化 TTS
        setupTts()
        
        // Register AI inference channel
        if let registrar = self.registrar(forPlugin: "AiInferenceChannel") {
            AiInferenceChannel.register(with: registrar)
        }
        
        // Register OCR channel
        OcrChannel.register(with: controller.binaryMessenger)
        
        return result
    }

    
    // MARK: - ASR Setup
    
    private func setupSpeechRecognizer() {
        print("IOS: Setting up speech recognizer for locale: \(currentLocale)")
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: currentLocale)) else {
            print("ERROR: IOS: Speech recognizer not available for \(currentLocale)")
            return
        }
        
        // 检查识别器是否可用
        guard recognizer.isAvailable else {
            print("ERROR: IOS: Speech recognizer not available for \(currentLocale)")
            return
        }
        
        speechRecognizer = recognizer
        if currentLocale.lowercased().contains("zh") {
            speechRecognizer?.defaultTaskHint = .dictation // 中文短语更依赖语言模型
        } else {
            speechRecognizer?.defaultTaskHint = .dictation
        }
    }
    
    // MARK: - Method Call Handler
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSimulator":
            #if targetEnvironment(simulator)
            result(true)
            #else
            result(false)
            #endif
            
        case "checkPermissions":
            checkPermissions(result: result)
            
        case "requestPermissions":
            requestPermissions(result: result)
            
        case "setLanguage":
            if let args = call.arguments as? [String: Any],
               let locale = args["locale"] as? String {
                setLanguage(locale: locale, result: result)
            } else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing locale parameter",
                    details: nil
                ))
            }
            
        case "startMicrophone":
            startMicrophone(result: result)
            
        case "startAsr":
            startAsr(result: result)
        case "setContextualStrings":
            if let args = call.arguments as? [String: Any],
               let phrases = args["phrases"] as? [String] {
                setContextualStrings(phrases: phrases)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing phrases", details: nil))
            }
            
        case "stopAsr":
            stopAsr(result: result)
            
        case "stopMicrophone":
            stopMicrophone(result: result)
            
        case "reset":
            reset(result: result)
            
        case "preloadModels":
            // iOS natively handles models, no-op needed
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func setContextualStrings(phrases: [String]) {
        contextualPhrases = phrases
    }
    
    // MARK: - ASR Methods
    
    private func setLanguage(locale: String, result: @escaping FlutterResult) {
        currentLocale = locale
        
        // 重新初始化语音识别器
        setupSpeechRecognizer()
        
        // 如果正在识别，需要完全停止并重新开始
        if !isAsrStopped && isRecording {
            // 完全停止ASR
            stopSpeechRecognition()
            teardownAudioEngine()
            
            // 延迟重新启动，确保完全停止
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.startSpeechRecognition()
            }
        }
        
        result(nil)
    }
    
    private func checkPermissions(result: @escaping FlutterResult) {
        let speechAuthStatus = SFSpeechRecognizer.authorizationStatus()
        let microphoneAuthStatus = AVAudioSession.sharedInstance().recordPermission
        
        let speechGranted = speechAuthStatus == .authorized
        let microphoneGranted = microphoneAuthStatus == .granted
        
        result(speechGranted && microphoneGranted)
    }
    
    private func requestPermissions(result: @escaping FlutterResult) {
        // 先请求语音识别权限
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    // 语音识别权限获取成功，请求麦克风权限
                    AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                        DispatchQueue.main.async {
                            result(allowed)
                        }
                    }
                case .denied, .restricted, .notDetermined:
                    result(false)
                @unknown default:
                    result(false)
                }
            }
        }
    }
    
    private func startMicrophone(result: @escaping FlutterResult) {
        guard !isRecording else {
            result(nil)
            return
        }
        
        
        // 检查权限状态
        let speechAuthStatus = SFSpeechRecognizer.authorizationStatus()
        let microphoneAuthStatus = AVAudioSession.sharedInstance().recordPermission
        
        guard speechAuthStatus == .authorized && microphoneAuthStatus == .granted else {
            result(FlutterError(
                code: "PERMISSION_DENIED",
                message: "需要麦克风和语音识别权限",
                details: nil
            ))
            return
        }
        
        setupAudioSession()
        // 核心优化：在 startMicrophone 时即初始化并启动音频引擎（Pre-warm），
        // 避免在后续 startAsr 时临时启动引擎产生的音频切换回声或杂音（尤其解决第一个单词的问题）
        initializeAudioEngine()
        isRecording = true
        result(nil)
    }
    
    private func startAsr(result: @escaping FlutterResult) {
        guard isRecording else {
            result(FlutterError(
                code: "NOT_RECORDING",
                message: "Microphone not started",
                details: nil
            ))
            return
        }
        
        isAsrStopped = false
        
        startSpeechRecognition()
        result(nil)
    }
    
    private func stopAsr(result: @escaping FlutterResult) {
        print("IOS: stopAsr (Hot Stop) requested")
        // 只停止识别流水线，保留音频引擎运行
        isAsrStopped = true
        stopSpeechRecognition()
        result(nil)
    }
    
    private func stopMicrophone(result: @escaping FlutterResult) {
        print("IOS: stopMicrophone (Cold Stop) requested")
        isAsrStopped = true
        stopSpeechRecognition()
        teardownAudioEngine()
        isRecording = false
        result(nil)
    }
    
    private func reset(result: @escaping FlutterResult) {
        
        // 暂停 ASR 状态
        isAsrStopped = true
        
        // 清理识别任务
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        
        // 清理识别请求
        if recognitionRequest != nil {
            recognitionRequest?.endAudio()
            recognitionRequest = nil
        }
        
        // 清理部分结果状态
        lastPartialResult = ""
        partialResultTimer?.invalidate()
        partialResultTimer = nil
        
        result(nil)
    }
    
    // MARK: - Audio Session Management
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // 模式改为 .default 以匹配 audioplayers，减少切换模式产生的咔哒声
            // 选项增加 .allowBluetoothA2DP 以支持更高质量的蓝牙音频
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("IOS: setupAudioSession error: \(error)")
        }
    }
    
    private func initializeAudioEngine() {
        guard !isAudioEngineInitialized else {
            return
        }
        
        
        // 确保音频会话已正确配置
        setupAudioSession()
        
        // 验证音频会话配置
        let audioSession = AVAudioSession.sharedInstance()
        guard audioSession.sampleRate > 0 && audioSession.inputNumberOfChannels > 0 else {
            return
        }
        
        
        // 配置音频引擎
        let inputNode = audioEngine.inputNode
        
        // 准备音频引擎
        audioEngine.prepare()
        
        // 启动音频引擎
        do {
            try audioEngine.start()
        } catch {
            return
        }
        
        // 获取硬件格式
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        
        // 使用已知有效的格式
        let format: AVAudioFormat
        if hardwareFormat.sampleRate > 0 && hardwareFormat.channelCount > 0 {
            format = hardwareFormat
        } else {
            // 使用音频会话的格式
            let sessionFormat = AVAudioFormat(
                standardFormatWithSampleRate: audioSession.sampleRate,
                channels: AVAudioChannelCount(audioSession.inputNumberOfChannels)
            )
            if let sessionFormat = sessionFormat {
                format = sessionFormat
            } else {
                // 最后备选：使用标准格式
                guard let standardFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1) else {
                    return
                }
                format = standardFormat
            }
        }
        
        // 确保格式兼容性 - 使用单声道，标准采样率
        let finalFormat: AVAudioFormat
        if format.channelCount > 1 {
            // 如果是立体声，转换为单声道
            guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1) else {
                return
            }
            finalFormat = monoFormat
        } else {
            finalFormat = format
        }
        
        // 安装 tap
        do {
            inputNode.installTap(onBus: 0, bufferSize: 512, format: finalFormat) { [weak self] (buffer, when) in
                guard let self = self else { 
                    print("IOS: Tap callback: self is nil")
                    return 
                }
                
                if self.isAsrStopped {
                    self.pausedLogCounter += 1
                    if self.pausedLogCounter % 200 == 0 {
                        print("IOS: Tap callback: ASR is paused, skipping buffer #\(self.pausedLogCounter)")
                    }
                    return
                }
                
                if self.recognitionRequest == nil {
                    // Only log occasionally to reduce noise
                    self.skippedBufferCount += 1
                    if self.skippedBufferCount % 50 == 0 {
                        print("IOS: Tap callback: recognitionRequest is nil, skipped \(self.skippedBufferCount) buffers")
                    }
                    return
                }
                
                self.recognitionRequest?.append(buffer)

                // 计算音量级别并经 meterEventSink 发送（限流至 ~30fps）
                if let sink = self.meterEventSink {
                    let now = Date().timeIntervalSince1970
                    if now - self.lastMeterSentAt >= (1.0 / 30.0) {
                        let level = self.calculateLevel(from: buffer)
                        DispatchQueue.main.async {
                            sink(level)
                        }
                        self.lastMeterSentAt = now
                    }
                }
            }
            print("IOS: Audio tap installed successfully")
        } catch {
            print("IOS: Failed to install tap: \(error)")
            return
        }
        
        isAudioEngineInitialized = true
        print("IOS: Audio engine initialization completed")
    }
    
    private func resetAudioEngineAndTap() {
        let inputNode = audioEngine.inputNode
        // Remove any existing tap
        inputNode.removeTap(onBus: 0)
        print("IOS: Removed existing audio tap")
        // Stop the audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            print("IOS: Stopped audio engine")
        }
        // Reset the audio engine
        audioEngine.reset()
        print("IOS: Reset audio engine")
        // Reinstall the tap with the correct format
        installTap()
    }
    
    private func installTap() {
        let audioSession = AVAudioSession.sharedInstance()
        let inputNode = audioEngine.inputNode
        // 获取硬件格式
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        // 使用已知有效的格式
        let format: AVAudioFormat
        if hardwareFormat.sampleRate > 0 && hardwareFormat.channelCount > 0 {
            format = hardwareFormat
            print("IOS: Using hardware format for tap")
        } else {
            let sessionFormat = AVAudioFormat(
                standardFormatWithSampleRate: audioSession.sampleRate,
                channels: AVAudioChannelCount(audioSession.inputNumberOfChannels)
            )
            if let sessionFormat = sessionFormat {
                format = sessionFormat
                print("IOS: Using session format for tap - Sample rate: \(format.sampleRate), Channels: \(format.channelCount)")
            } else {
                guard let standardFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1) else {
                    print("IOS: Failed to create any valid format for tap")
                    return
                }
                format = standardFormat
                print("IOS: Using fallback format for tap - Sample rate: \(format.sampleRate), Channels: \(format.channelCount)")
            }
        }
        // 确保格式兼容性 - 使用单声道，标准采样率
        let finalFormat: AVAudioFormat
        if format.channelCount > 1 {
            guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1) else {
                print("IOS: Failed to create mono format for tap")
                return
            }
            finalFormat = monoFormat
            print("IOS: Converting to mono format for tap - Sample rate: \(finalFormat.sampleRate), Channels: \(finalFormat.channelCount)")
        } else {
            finalFormat = format
            print("IOS: Using original format for tap - Sample rate: \(finalFormat.sampleRate), Channels: \(finalFormat.channelCount)")
        }
        // 安装 tap
        do {
            var bufferCount = 0
            inputNode.installTap(onBus: 0, bufferSize: 512, format: finalFormat) { [weak self] (buffer, when) in
                guard let self = self else { return }
                
                // 核心修复：始终推送分贝数据，确保波形图在任何状态下都活跃
                if let sink = self.meterEventSink {
                    let now = Date().timeIntervalSince1970
                    if now - self.lastMeterSentAt >= (1.0 / 30.0) {
                        let level = self.calculateLevel(from: buffer)
                        DispatchQueue.main.async {
                            sink(level)
                        }
                        self.lastMeterSentAt = now
                    }
                }

                // 如果处于暂停状态或请求为空，不喂数据给识别器
                if self.isAsrStopped || self.recognitionRequest == nil {
                    return
                }
                
                self.recognitionRequest?.append(buffer)
            }
            print("IOS: Audio tap installed successfully")
        } catch {
            print("IOS: Failed to install tap: \(error)")
        }
    }
    
    private func startSpeechRecognition() {
        print("IOS: startSpeechRecognition called, engine.isRunning: \(audioEngine.isRunning)")
        
        // 1. 先确保停止旧任务，并暂时阻断数据喂入
        stopSpeechRecognition()
        isAsrStopped = true
        
        // 2. 优化引擎启停：如果已在运行，跳过物理重置以消除咔哒声
        if !audioEngine.isRunning {
            print("IOS: Audio engine not running, performing full reset")
            resetAudioEngineAndTap()
            do {
                try audioEngine.start()
                print("IOS: Audio engine started successfully")
            } catch {
                print("IOS: Audio engine couldn't start: \(error)")
                return
            }
        } else {
            print("IOS: Audio engine already running, skipping physical reset")
        }
        
        // 确保使用当前设置的语言创建识别器
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: currentLocale)) else {
            print("Failed to create speech recognizer for \(currentLocale)")
            return
        }
        guard speechRecognizer.isAvailable else {
            print("Speech recognizer not available for \(currentLocale)")
            return
        }
        print("IOS: Speech recognizer created successfully for \(currentLocale)")
        self.speechRecognizer = speechRecognizer
        
        // 根据语言设置任务提示
        if currentLocale.lowercased().contains("zh") {
            speechRecognizer.defaultTaskHint = .dictation
            print("IOS: Speech recognizer configured for Chinese (dictation mode)")
        } else {
            speechRecognizer.defaultTaskHint = .dictation
            print("IOS: Speech recognizer configured for English (dictation mode)")
        }
        
        // 先创建新的识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create recognition request")
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        if !contextualPhrases.isEmpty {
            recognitionRequest.contextualStrings = contextualPhrases
        }
        if currentLocale.lowercased().contains("zh") {
            recognitionRequest.taskHint = .dictation
            print("IOS: Recognition request configured for Chinese (dictation mode)")
        } else {
            recognitionRequest.taskHint = .dictation
            print("IOS: Recognition request configured for English (dictation mode)")
        }
        if #available(iOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        print("IOS: Recognition request created successfully")
        
        // 检查音频引擎状态
        let audioSession = AVAudioSession.sharedInstance()
        print("IOS: Audio session state - Sample rate: \(audioSession.sampleRate), Input channels: \(audioSession.inputNumberOfChannels), isRunning: \(audioEngine.isRunning)")
        
        // 创建新的识别任务
        print("IOS: Creating new recognition task...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("IOS: Creating recognition task after delay (0.1s)...")
            self.isAsrStopped = false // <- FIX: Ensure input processing resumes
            self.recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                var isFinal = false
                var shouldRestart = false
                
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        // "No speech detected" 不是错误，只是正常状态
                        print("IOS: No speech detected (normal state)")
                        // 不设置 shouldRestart，让识别任务继续运行
                    } else {
                        // 其他错误才需要重启
                        print("IOS: Speech recognition error: \(error)")
                        shouldRestart = true
                    }
                }
                
                if let result = result {
                    let bestString = result.bestTranscription.formattedString
                    let selectedString = self.selectTranscription(using: result)
                    isFinal = result.isFinal
                    print("IOS: Speech recognition result: best='\(bestString)' selected='\(selectedString)' (isFinal: \(isFinal))")
                    print("Current locale: \(self.currentLocale)")
                    
                    // 打印 N-best 候选
                    var idx = 0
                    for t in result.transcriptions {
                        print("IOS: NBest[\(idx)]: '\(t.formattedString)' score=NA")
                        idx += 1
                    }
                    
                    // 处理部分结果和最终结果
                    if !selectedString.isEmpty && !self.isAsrStopped {
                        // 如果是新的部分结果，立即发送候选结果
                        if !isFinal {
                            self.lastPartialResult = selectedString
                            DispatchQueue.main.async {
                                // 创建候选结果数组
                                let candidates = result.transcriptions.map { $0.formattedString }
                                print("IOS: Sending partial result with candidates to Flutter: '\(selectedString)' candidates: \(candidates)")
                                
                                // 发送JSON格式的候选结果
                                let resultData: [String: Any] = [
                                    "best": selectedString,
                                    "candidates": candidates
                                ]
                                
                                do {
                                    let jsonData = try JSONSerialization.data(withJSONObject: resultData)
                                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                                        self.eventSink?(jsonString)
                                    } else {
                                        // 如果JSON序列化失败，创建备用JSON格式
                                        let fallbackData: [String: Any] = [
                                            "best": selectedString,
                                            "candidates": [selectedString]
                                        ]
                                        if let fallbackJson = try? JSONSerialization.data(withJSONObject: fallbackData),
                                           let fallbackString = String(data: fallbackJson, encoding: .utf8) {
                                            print("IOS: JSON serialization failed for partial result, sending fallback JSON")
                                            self.eventSink?(fallbackString)
                                        } else {
                                            // 最后回退到单个结果
                                            self.eventSink?(selectedString)
                                        }
                                    }
                                } catch {
                                    // 创建备用JSON格式
                                    let fallbackData: [String: Any] = [
                                        "best": selectedString,
                                        "candidates": [selectedString]
                                    ]
                                    if let fallbackJson = try? JSONSerialization.data(withJSONObject: fallbackData),
                                       let fallbackString = String(data: fallbackJson, encoding: .utf8) {
                                        print("IOS: Failed to serialize partial candidates, sending fallback JSON: \(error)")
                                        self.eventSink?(fallbackString)
                                    } else {
                                        // 最后回退到单个结果
                                        self.eventSink?(selectedString)
                                    }
                                }
                            }
                        }
                        // 如果是最终结果，发送多个候选结果
                        else if isFinal {
                            DispatchQueue.main.async {
                                // 创建候选结果数组
                                let candidates = result.transcriptions.map { $0.formattedString }
                                print("IOS: Sending final result with candidates to Flutter: '\(selectedString)' candidates: \(candidates)")
                                
                                // 发送JSON格式的候选结果
                                let resultData: [String: Any] = [
                                    "best": selectedString,
                                    "candidates": candidates
                                ]
                                
                                do {
                                    let jsonData = try JSONSerialization.data(withJSONObject: resultData)
                                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                                        self.eventSink?(jsonString)
                                    } else {
                                        // 如果JSON序列化失败，创建备用JSON格式
                                        let fallbackData: [String: Any] = [
                                            "best": selectedString,
                                            "candidates": [selectedString]
                                        ]
                                        if let fallbackJson = try? JSONSerialization.data(withJSONObject: fallbackData),
                                           let fallbackString = String(data: fallbackJson, encoding: .utf8) {
                                            print("IOS: JSON serialization failed for final result, sending fallback JSON")
                                            self.eventSink?(fallbackString)
                                        } else {
                                            // 最后回退到单个结果
                                            self.eventSink?(selectedString)
                                        }
                                    }
                                } catch {
                                    // 创建备用JSON格式
                                    let fallbackData: [String: Any] = [
                                        "best": selectedString,
                                        "candidates": [selectedString]
                                    ]
                                    if let fallbackJson = try? JSONSerialization.data(withJSONObject: fallbackData),
                                       let fallbackString = String(data: fallbackJson, encoding: .utf8) {
                                        print("IOS: Failed to serialize final candidates, sending fallback JSON: \(error)")
                                        self.eventSink?(fallbackString)
                                    } else {
                                        // 最后回退到单个结果
                                        self.eventSink?(selectedString)
                                    }
                                }
                            }
                            // 重置部分结果
                            self.lastPartialResult = ""
                        }
                    }
                    
                    // 只有在最终结果时才重启任务
                    if isFinal {
                        shouldRestart = true
                    }
                } else {
                    print("IOS: No speech recognition result")
                }
                
                if shouldRestart || isFinal {
                    print("IOS: Speech recognition task ending - shouldRestart: \(shouldRestart), isFinal: \(isFinal)")
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.lastMeterSentAt = 0
                    if !self.isAsrStopped && shouldRestart {
                        print("IOS: ASR not paused and should restart, creating new recognition task")
                        DispatchQueue.main.async {
                            self.startSpeechRecognition()
                        }
                    } else {
                        print("IOS: ASR is paused or no restart needed, not creating new task")
                    }
                }
            }
            print("IOS: Speech recognition task started successfully")
            self.isAsrStopped = false
            print("IOS: Recognition task established, ready for audio")
        }
    }
    
    // MARK: - Audio Meter Helper
    private func calculateLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?.pointee else { return 0.0 }
        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 { return 0.0 }
        var sum: Float = 0.0
        // 计算均方值
        for i in 0..<frameLength {
            let s = channelData[i]
            sum += s * s
        }
        let meanSquare = sum / Float(frameLength)
        let rms = sqrtf(meanSquare)
        // 转换为分贝并归一到 0..1
        let minDb: Float = -60.0
        var db = 20.0 * log10f(max(rms, 1e-6))
        if db < minDb { db = minDb }
        if db > 0 { db = 0 }
        let normalized = 1.0 - abs(db) / abs(minDb)
        return normalized
    }

    // 基于 contextualPhrases 对候选进行轻量级重排
    private func selectTranscription(using result: SFSpeechRecognitionResult) -> String {
        // 直接返回最可能的识别结果，不进行额外的人为偏置，以响应用户“听它听到什么输出什么”的需求
        return result.bestTranscription.formattedString
    }
    

    private func stopSpeechRecognition() {
        // 只清理识别任务和请求，不停止音频引擎
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil

        // 清理电平推送状态
        lastMeterSentAt = 0
    }
    
    private func teardownAudioEngine() {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        isAudioEngineInitialized = false
        pausedLogCounter = 0
        print("IOS: Audio engine torn down")
    }


}

// 由于使用了独立的 SimpleStreamHandler，不再需要在此处作为 FlutterStreamHandler

// MARK: - TTS Methods

extension AppDelegate {
    private func setupTts() {
        synthesizer.delegate = self
    }
    
    private func handleTtsMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "speak":
            if let args = call.arguments as? [String: Any],
               let text = args["text"] as? String,
               let utteranceId = args["utteranceId"] as? String {
                let language = args["language"] as? String ?? "zh-CN"
                speak(text: text, utteranceId: utteranceId, language: language)
                result(nil)
            } else {
                result(FlutterError(
                    code: "INVALID_ARGUMENTS",
                    message: "Missing text or utteranceId parameter",
                    details: nil
                ))
            }
        case "stop":
            stopTts()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func speak(text: String, utteranceId: String, language: String) {
        print("IOS: TTS speak: text='\(text)', utteranceId='\(utteranceId)', language='\(language)'")
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.postUtteranceDelay = 0.0
        utterance.preUtteranceDelay = 0.0
        
        print("IOS: TTS utterance created: voice=\(utterance.voice?.language ?? "unknown")")
        currentUtteranceId = utteranceId
        print("IOS: TTS starting synthesis for utteranceId: \(utteranceId)")
        synthesizer.speak(utterance)
    }
    
    private func stopTts() {
        print("IOS: TTS stop requested")
        synthesizer.stopSpeaking(at: .immediate)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AppDelegate: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("IOS: TTS didFinish: utteranceId=\(currentUtteranceId ?? "nil")")
        if let utteranceId = currentUtteranceId {
            let event: [String: Any] = ["type": "ttsCompleted", "data": utteranceId]
            print("IOS: TTS sending completion event: \(event)")
            print("IOS: TTS ttsEventSink is nil: \(ttsEventSink == nil)")
            ttsEventSink?(event)
            currentUtteranceId = nil
        } else {
            print("IOS: TTS didFinish but no utteranceId found")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("IOS: TTS didCancel: utteranceId=\(currentUtteranceId ?? "nil")")
        if let utteranceId = currentUtteranceId {
            let event: [String: Any] = ["type": "ttsCompleted", "data": utteranceId]
            print("IOS: TTS sending cancellation event: \(event)")
            print("IOS: TTS ttsEventSink is nil: \(ttsEventSink == nil)")
            ttsEventSink?(event)
            currentUtteranceId = nil
        } else {
            print("IOS: TTS didCancel but no utteranceId found")
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("IOS: TTS didStart: utteranceId=\(currentUtteranceId ?? "nil")")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        print("IOS: TTS willSpeakRange: \(characterRange), utteranceId=\(currentUtteranceId ?? "nil")")
    }
}

// MARK: - App Review Methods

extension AppDelegate {
    private func handleReviewMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "requestReview":
            requestAppReview(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func requestAppReview(result: @escaping FlutterResult) {
        print("IOS: Requesting app review")
        
        // iOS 14+ 使用 SKStoreReviewController.requestReview(in:)
        if #available(iOS 14.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                DispatchQueue.main.async {
                    SKStoreReviewController.requestReview(in: windowScene)
                    print("IOS: App review requested successfully (iOS 14+)")
                }
            } else {
                print("IOS: Could not find window scene for review request")
            }
        } else {
            // iOS 10.3 - 13.x 使用旧版 API
            DispatchQueue.main.async {
                SKStoreReviewController.requestReview()
                print("IOS: App review requested successfully (iOS 10.3-13)")
            }
        }
        
        result(nil)
    }
}

class SimpleStreamHandler: NSObject, FlutterStreamHandler {
    let onListenHandler: (@escaping FlutterEventSink) -> Void
    let onCancelHandler: () -> Void
    
    init(onListen: @escaping (@escaping FlutterEventSink) -> Void, onCancel: @escaping () -> Void) {
        self.onListenHandler = onListen
        self.onCancelHandler = onCancel
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenHandler(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancelHandler()
        return nil
    }
}
