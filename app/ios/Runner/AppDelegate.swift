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
        
        // Initialize TTS
        setupTts()
        
        // Register AI inference channel
        if let registrar = self.registrar(forPlugin: "AiInferenceChannel") {
            AiInferenceChannel.register(with: registrar)
        }
        
        // Register OCR channel
        OcrChannel.register(with: controller.binaryMessenger)
        
        // 监听音频引擎配置变化（如蓝牙耳机插拔导致采样率变化）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )
        
        return result
    }

    @objc private func handleAudioEngineConfigurationChange(_ notification: Notification) {
        print("IOS: Audio engine configuration changed notification received")
        // 如果正在录音/识别，需要重新配置引擎并安装 Tap
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            print("IOS: Re-initializing audio engine due to configuration change...")
            self.resetAudioEngineAndTap()
        }
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
    
    private func executeWhenActive(_ block: @escaping () -> Void) {
        if UIApplication.shared.applicationState == .active {
            block()
        } else {
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                if let token = token {
                    NotificationCenter.default.removeObserver(token)
                }
                block()
            }
        }
    }

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
            executeWhenActive {
                self.requestPermissions(result: result)
            }
            
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
            executeWhenActive {
                self.startMicrophone(result: result)
            }
            
        case "startAsr":
            executeWhenActive {
                self.startAsr(result: result)
            }
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
        print("~~~~~ASR HOTWORDS: \(phrases.joined(separator: ", "))")
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
        print("IOS: [ASR] stopAsr (Hot Stop) requested")
        // 只停止识别流水线，保留音频引擎运行
        print("IOS: [ASR] Data stream channel CLOSED (isAsrStopped = true)")
        isAsrStopped = true
        stopSpeechRecognition()
        result(nil)
    }
    
    private func stopMicrophone(result: @escaping FlutterResult) {
        print("IOS: [ASR] stopMicrophone (Cold Stop) requested")
        print("IOS: [ASR] Data stream channel CLOSED (isAsrStopped = true)")
        isAsrStopped = true
        stopSpeechRecognition()
        teardownAudioEngine()
        isRecording = false
        
        // 核心修复：先停用音频会话，再切换分类，最后重新激活。
        // 直接从 playAndRecord 切换到 playback 并 setActive(true) 会触发
        // AVAudioSessionErrorCodeInsufficientPriority (OSStatus 561017449 / '!pri')。
        // 正确的 iOS 音频会话切换顺序：deactivate → setCategory → activate。
        // 若当前分类已经是 .playback，跳过整个 deactivate/reactivate 循环，
        // 根除不必要的会话切换导致的爆音。
        let audioSession = AVAudioSession.sharedInstance()
        if audioSession.category != .playback {
            do {
                // 1. 停用当前会话，释放音频硬件给系统
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("IOS: [ASR] Audio session deactivated")
                // 2. 切换分类到 playback
                try audioSession.setCategory(
                    .playback,
                    mode: .default,
                    options: [.mixWithOthers]
                )
                print("IOS: [ASR] Audio session category set to .playback")
                // 3. 重新激活
                try audioSession.setActive(true)
                print("IOS: [ASR] Native AVAudioSession category successfully reverted to .playback")
            } catch {
                let nsError = error as NSError
                print("IOS: [ASR] Native AVAudioSession category revert failed: \(error) (domain: \(nsError.domain), code: \(nsError.code))")
            }
        } else {
            print("IOS: [ASR] Audio session already .playback, skipping deactivate/reactivate cycle to prevent pop")
        }
        
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
            let targetCategory = AVAudioSession.Category.playAndRecord
            let targetMode = AVAudioSession.Mode.default
            let targetOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .mixWithOthers, .allowBluetooth, .allowBluetoothA2DP]
            
            if audioSession.category == targetCategory &&
               audioSession.mode == targetMode &&
               audioSession.categoryOptions == targetOptions {
                print("IOS: [ASR] setupAudioSession: AVAudioSession is already correctly configured, skipping setCategory.")
            } else {
                print("IOS: [ASR] setupAudioSession: Reconfiguring AVAudioSession from \(audioSession.category) (mode: \(audioSession.mode)) to playAndRecord (mode: default)")
                try audioSession.setCategory(
                    targetCategory,
                    mode: targetMode,
                    options: targetOptions
                )
            }
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
            print("IOS: [ASR] Audio session not ready (rate: \(audioSession.sampleRate), channels: \(audioSession.inputNumberOfChannels))")
            return
        }
        
        print("IOS: [ASR] Initializing audio engine. Session rate: \(audioSession.sampleRate), channels: \(audioSession.inputNumberOfChannels)")
        
        // 核心修复：先停止并重置引擎，确保状态干净
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        
        let inputNode = audioEngine.inputNode
        
        // 移除任何现有的 Tap，防止重复安装
        inputNode.removeTap(onBus: 0)
        
        // 启动音频引擎
        do {
            audioEngine.prepare()
            try audioEngine.start()
            print("IOS: [ASR] Audio engine started successfully")
        } catch {
            print("IOS: [ASR] Failed to start audio engine: \(error)")
            return
        }
        
        // 安装 Tap
        installTap()
        
        isAudioEngineInitialized = true
        print("IOS: [ASR] Audio engine initialization completed")
    }
    
    private func resetAudioEngineAndTap() {
        print("IOS: [ASR] resetAudioEngineAndTap called")
        let inputNode = audioEngine.inputNode
        
        // 1. 停止引擎
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // 2. 移除 Tap
        inputNode.removeTap(onBus: 0)
        
        // 3. 重置引擎状态
        audioEngine.reset()
        
        // 4. 重新配置并启动
        setupAudioSession()
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            print("IOS: [ASR] Audio engine restarted successfully")
        } catch {
            print("IOS: [ASR] Failed to restart audio engine: \(error)")
            return
        }
        
        // 5. 重新安装 Tap
        installTap()
    }
    
    private var tapBufferCount = 0

    private func installTap() {
        let inputNode = audioEngine.inputNode
        let session = AVAudioSession.sharedInstance()
        
        // 彻底解决 "format mismatch" 崩溃的关键：
        // 1. 必须先 removeTap
        inputNode.removeTap(onBus: 0)
        
        // 2. 获取格式并处理 sampleRate 0 的异常情况
        var recordingFormat = inputNode.outputFormat(forBus: 0)
        print("IOS: [ASR] Tap check - Session rate: \(session.sampleRate), Node output rate: \(recordingFormat.sampleRate)")
        
        if recordingFormat.sampleRate == 0 {
            recordingFormat = inputNode.inputFormat(forBus: 0)
            print("IOS: [ASR] Node output format 0, checking inputFormat: \(recordingFormat.sampleRate)")
        }
        
        let finalFormat: AVAudioFormat
        if recordingFormat.sampleRate > 0 {
            finalFormat = recordingFormat
        } else {
            print("IOS: [ASR] WARNING: Node format invalid (0), using session fallback")
            // 尝试使用 session 的采样率构造一个标准的单声道 PCM 格式
            finalFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, 
                                      sampleRate: session.sampleRate, 
                                      channels: 1, 
                                      interleaved: false)!
        }
        
        print("IOS: [ASR] Installing tap with format: \(finalFormat)")
        self.tapBufferCount = 0
        
        // 3. 使用 native/fallback format 安装 Tap。
        // SFSpeechAudioBufferRecognitionRequest 会自动处理缓冲区格式转换。
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: finalFormat) { [weak self] (buffer, when) in
            guard let self = self else { return }
            
            self.tapBufferCount += 1
            if self.tapBufferCount % 100 == 0 {
                let level = self.calculateLevel(from: buffer)
                print("IOS: [ASR] Tap Heartbeat - buffers: \(self.tapBufferCount), level: \(level), stopped: \(self.isAsrStopped), hasRequest: \(self.recognitionRequest != nil)")
            }

            // 始终计算音量，用于 UI 反馈
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

            // 如果 ASR 已停止或识请求为空，不喂数据
            if self.isAsrStopped || self.recognitionRequest == nil {
                return
            }
            
            self.recognitionRequest?.append(buffer)
        }
        print("IOS: [ASR] Audio tap installed successfully on bus 0")
    }
    
    private func startSpeechRecognition() {
        print("IOS: [ASR] startSpeechRecognition called, engine.isRunning: \(audioEngine.isRunning)")
        
        // 1. 先确保停止旧任务，并暂时阻断数据喂入
        stopSpeechRecognition()
        print("IOS: [ASR] Data stream channel CLOSED (isAsrStopped = true)")
        isAsrStopped = true
        
        // 2. 核心机制修复：为了绝对保证识别请求的时钟锚点新鲜，每次启动识别都重新安装 Tap
        // 即使引擎已经在运行（热启动），重新安装 Tap 也能强制重置数据流状态。
        if !audioEngine.isRunning {
            print("IOS: [ASR] Audio engine NOT running, performing full physical reset and tap installation.")
            resetAudioEngineAndTap()
        } else {
            print("IOS: [ASR] Audio engine ALREADY running (pre-warmed), reuse active Tap and skip re-installation to avoid pop sounds.")
        }
        
        // 确保使用当前设置的语言创建识别器
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: currentLocale)) else {
            print("IOS: [ASR] Failed to create speech recognizer for \(currentLocale)")
            return
        }
        guard speechRecognizer.isAvailable else {
            print("IOS: [ASR] Speech recognizer not available for \(currentLocale)")
            return
        }
        print("IOS: [ASR] Speech recognizer created successfully for \(currentLocale)")
        self.speechRecognizer = speechRecognizer
        
        // 根据语言设置任务提示
        speechRecognizer.defaultTaskHint = .dictation
        
        // 先创建新的识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("IOS: [ASR] Unable to create recognition request")
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        if !contextualPhrases.isEmpty {
            recognitionRequest.contextualStrings = contextualPhrases
        }
        recognitionRequest.taskHint = .dictation
        
        if #available(iOS 13.0, *) {
            if speechRecognizer.supportsOnDeviceRecognition {
                recognitionRequest.requiresOnDeviceRecognition = true
                print("IOS: [ASR] supportsOnDeviceRecognition = true, enabled offline ASR.")
            } else {
                recognitionRequest.requiresOnDeviceRecognition = false
                print("IOS: [ASR] supportsOnDeviceRecognition = false, falling back to online ASR.")
            }
        }

        print("IOS: [ASR] Creating SFSpeechAudioBufferRecognitionRequest & recognitionTask synchronously...")
        
        self.recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            var isFinal = false
            var shouldRestart = false
            
            if let error = error {
                let nsError = error as NSError
                // 1110: No speech detected, 1107: Speech recognition interrupted
                if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 1110 || nsError.code == 1107) {
                    print("IOS: [ASR] Task callback - No speech or interrupted (code: \(nsError.code))")
                } else if nsError.code == 301 {
                    print("IOS: [ASR] Task callback - Recognition request was canceled (code: 301)")
                } else {
                    print("IOS: [ASR] Task callback - Error: \(error)")
                    shouldRestart = true
                }
            }
            
            if let result = result {
                let selectedString = self.selectTranscription(using: result)
                isFinal = result.isFinal
                print("~~~~~ASR RESULT: '\(selectedString)' (isFinal: \(isFinal))")
                
                // 处理部分结果和最终结果
                if !selectedString.isEmpty && !self.isAsrStopped {
                    // 如果是新的部分结果，立即发送候选结果
                    if !isFinal {
                        self.lastPartialResult = selectedString
                        DispatchQueue.main.async {
                            let candidates = result.transcriptions.map { $0.formattedString }
                            print("IOS: [ASR] Sending partial result with candidates to Flutter: '\(selectedString)'")
                            
                            let resultData: [String: Any] = [
                                "best": selectedString,
                                "candidates": candidates
                            ]
                            
                            if let jsonData = try? JSONSerialization.data(withJSONObject: resultData),
                               let jsonString = String(data: jsonData, encoding: .utf8) {
                                self.eventSink?(jsonString)
                            } else {
                                self.eventSink?(selectedString)
                            }
                        }
                    }
                    // 如果是最终结果，发送多个候选结果
                    else if isFinal {
                        DispatchQueue.main.async {
                            let candidates = result.transcriptions.map { $0.formattedString }
                            print("IOS: [ASR] Sending final result with candidates to Flutter: '\(selectedString)'")
                            
                            let resultData: [String: Any] = [
                                "best": selectedString,
                                "candidates": candidates
                            ]
                            
                            if let jsonData = try? JSONSerialization.data(withJSONObject: resultData),
                               let jsonString = String(data: jsonData, encoding: .utf8) {
                                self.eventSink?(jsonString)
                            } else {
                                self.eventSink?(selectedString)
                            }
                        }
                        self.lastPartialResult = ""
                    }
                }
                
                // 只有在最终结果时才重启任务
                if isFinal {
                    shouldRestart = true
                }
            } else {
                print("IOS: [ASR] No speech recognition result")
            }
            
            if shouldRestart || isFinal {
                print("IOS: [ASR] Speech recognition task ending - shouldRestart: \(shouldRestart), isFinal: \(isFinal)")
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.lastMeterSentAt = 0
                if !self.isAsrStopped && shouldRestart {
                    print("IOS: [ASR] ASR not paused and should restart, creating new recognition task")
                    DispatchQueue.main.async {
                        self.startSpeechRecognition()
                    }
                }
            }
        }
        
        // 彻底移除 asyncAfter 延迟，同步开启与建立任务
        print("IOS: [ASR] Speech recognition task started successfully! Opening data stream...")
        self.isAsrStopped = false 
        print("IOS: [ASR] Data stream channel OPENED (isAsrStopped = false). Tap buffers will now feed into the recognition request.")
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
        // 转换为分贝并归一到 0..1。调整 minDb 过滤门槛（从 -60.0 调整到 -40.0），过滤微弱的环境噪音，解决 iPhone 等设备上波形图过于灵敏的问题
        let minDb: Float = -40.0
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
        print("IOS: [ASR] stopSpeechRecognition called")
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
        case "checkLanguageSupport":
            if let args = call.arguments as? [String: Any],
               let language = args["language"] as? String {
                let voice = AVSpeechSynthesisVoice(language: language)
                result(voice != nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing language", details: nil))
            }
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
