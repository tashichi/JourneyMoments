// VideoManager.swift - AVComposition実装版
// 継ぎ目問題解決：複数セグメントを一つのコンポジションに統合

import AVFoundation
import UIKit
import SwiftUI

class VideoManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var currentSegmentIndex = 0
    @Published var isCompositionMode = false // 新機能テスト用フラグ
    
    var captureSession: AVCaptureSession
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private let tempDirectory = FileManager.default.temporaryDirectory
    private var recordingTimer: Timer?
    
    var onRecordingComplete: ((URL) -> Void)?
    
    // 従来の再生関連
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var currentSegments: [VideoSegment] = []
    private var playbackTimer: Timer?
    
    // 新機能：AVComposition再生
    private var compositionPlayer: AVPlayer?
    private var composition: AVMutableComposition?
    
    // セッション状態管理
    private var isConfiguringSession = false
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    override init() {
        self.captureSession = AVCaptureSession()
        super.init()
        setupCamera()
    }
    
    deinit {
        recordingTimer?.invalidate()
        playbackTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        
        sessionQueue.async {
            if self.captureSession.isRunning && !self.isConfiguringSession {
                self.captureSession.stopRunning()
            }
        }
    }
    
    // MARK: - Camera Setup (既存コード維持)
    
    private func setupCamera() {
        print("🎬 カメラセットアップ開始")
        
        if isSimulator {
            print("📱 シミュレーター環境を検出")
            setupSimulatorCamera()
            return
        }
        
        sessionQueue.async {
            self.isConfiguringSession = true
            self.captureSession.beginConfiguration()
            
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
                print("✅ 録画品質: High")
            }
            
            self.setupVideoInput()
            self.setupAudioInput()
            self.setupMovieFileOutput()
            
            self.captureSession.commitConfiguration()
            self.isConfiguringSession = false
            print("✅ カメラセットアップ完了")
        }
    }
    
    private func setupSimulatorCamera() {
        sessionQueue.async {
            self.isConfiguringSession = true
            self.captureSession.beginConfiguration()
            
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
            
            self.captureSession.commitConfiguration()
            self.isConfiguringSession = false
            print("✅ シミュレーター用カメラセットアップ完了")
        }
    }
    
    private func setupVideoInput() {
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("❌ カメラデバイスが見つかりません")
            return
        }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoDeviceInput!) {
                captureSession.addInput(videoDeviceInput!)
                print("✅ ビデオ入力設定完了")
            }
        } catch {
            print("❌ ビデオ入力設定エラー: \(error.localizedDescription)")
        }
    }
    
    private func setupAudioInput() {
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            print("❌ オーディオデバイスが見つかりません")
            return
        }
        
        do {
            audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
            if captureSession.canAddInput(audioDeviceInput!) {
                captureSession.addInput(audioDeviceInput!)
                print("✅ オーディオ入力設定完了")
            }
        } catch {
            print("❌ オーディオ入力設定エラー: \(error.localizedDescription)")
        }
    }
    
    private func setupMovieFileOutput() {
        movieFileOutput = AVCaptureMovieFileOutput()
        
        if captureSession.canAddOutput(movieFileOutput!) {
            captureSession.addOutput(movieFileOutput!)
            
            if let connection = movieFileOutput?.connection(with: .video) {
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            
            print("✅ 動画ファイル出力設定完了")
        }
    }
    
    // MARK: - Session Management
    
    func startSession() {
        sessionQueue.async {
            if !self.captureSession.isRunning && !self.isConfiguringSession {
                self.captureSession.startRunning()
                print("🎬 カメラセッション開始")
            } else if self.isConfiguringSession {
                print("⚠️ セッション設定中のため開始をスキップ")
            } else {
                print("⚠️ セッションは既に動作中")
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning && !self.isConfiguringSession {
                self.captureSession.stopRunning()
                print("⏹ カメラセッション停止")
            } else if self.isConfiguringSession {
                print("⚠️ セッション設定中のため停止をスキップ")
            } else {
                print("⚠️ セッションは既に停止中")
            }
        }
    }
    
    func safeStopSession() {
        sessionQueue.async {
            while self.isConfiguringSession {
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                print("✅ セッション安全停止完了")
            }
        }
    }
    
    // MARK: - Permission Handling
    
    func checkCameraPermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
    
    // MARK: - Recording Functions
    
    func startRecording() {
        print("🔴 録画開始処理")
        
        guard !isRecording else {
            print("⚠️ 既に録画中です")
            return
        }
        
        if isSimulator {
            simulateRecording()
            return
        }
        
        sessionQueue.async {
            guard let movieFileOutput = self.movieFileOutput else {
                print("❌ 録画出力が設定されていません")
                return
            }
            
            let videoConnections = movieFileOutput.connections.filter { $0.isEnabled && $0.isActive }
            guard !videoConnections.isEmpty else {
                print("❌ アクティブな接続がありません")
                DispatchQueue.main.async {
                    self.simulateRecording()
                }
                return
            }
            
            let fileName = "temp_video_\(Date().timeIntervalSince1970).mov"
            let tempFileURL = self.tempDirectory.appendingPathComponent(fileName)
            
            print("📹 録画開始: \(tempFileURL.lastPathComponent)")
            
            DispatchQueue.main.async {
                self.isRecording = true
            }
            
            movieFileOutput.startRecording(to: tempFileURL, recordingDelegate: self)
            
            DispatchQueue.main.async {
                self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                    self.stopRecording()
                }
            }
        }
    }
    
    private func simulateRecording() {
        print("📱 シミュレーター録画をシミュレート")
        
        DispatchQueue.main.async {
            self.isRecording = true
        }
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            self.simulateRecordingComplete()
        }
    }
    
    private func simulateRecordingComplete() {
        print("✅ シミュレーター録画完了")
        
        let fileName = "simulator_video_\(Date().timeIntervalSince1970).mov"
        let tempFileURL = tempDirectory.appendingPathComponent(fileName)
        
        FileManager.default.createFile(atPath: tempFileURL.path, contents: Data(), attributes: nil)
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.onRecordingComplete?(tempFileURL)
        }
    }
    
    private func stopRecording() {
        print("⏹ 録画停止処理")
        
        guard isRecording else { return }
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        if !isSimulator {
            sessionQueue.async {
                self.movieFileOutput?.stopRecording()
            }
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    // MARK: - 新機能: AVComposition シームレス再生
    
    func startCompositionPlayback(segments: [VideoSegment]) {
        print("🎵 AVComposition シームレス再生開始 - セグメント数: \(segments.count)")
        
        guard !segments.isEmpty else {
            print("❌ 再生するセグメントがありません")
            return
        }
        
        currentSegments = segments
        
        DispatchQueue.main.async {
            self.isCompositionMode = true
            self.isPlaying = true
            self.currentSegmentIndex = 0
        }
        
        if isSimulator {
            // シミュレーター用の簡単な実装
            simulateCompositionPlayback()
        } else {
            // 実機用のAVComposition実装
            createAndPlayComposition(segments: segments)
        }
    }
    
    private func createAndPlayComposition(segments: [VideoSegment]) {
        print("🔨 AVComposition作成開始")
        
        composition = AVMutableComposition()
        guard let composition = composition else { return }
        
        // ビデオとオーディオトラック作成
        let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        
        var currentTime = CMTime.zero
        
        for (index, segment) in segments.enumerated() {
            let url: URL
            if segment.uri.hasPrefix("file://") {
                url = URL(string: segment.uri) ?? URL(fileURLWithPath: segment.uri.replacingOccurrences(of: "file://", with: ""))
            } else {
                url = URL(fileURLWithPath: segment.uri)
            }
            
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("❌ セグメント\(index + 1)のファイルが見つかりません: \(url.path)")
                continue
            }
            
            let asset = AVAsset(url: url)
            
            // ビデオトラック追加
            if let assetVideoTrack = asset.tracks(withMediaType: .video).first {
                do {
                    try videoTrack?.insertTimeRange(
                        CMTimeRange(start: .zero, duration: asset.duration),
                        of: assetVideoTrack,
                        at: currentTime
                    )
                    print("✅ セグメント\(index + 1) ビデオトラック追加完了")
                } catch {
                    print("❌ セグメント\(index + 1) ビデオトラック追加エラー: \(error)")
                }
            }
            
            // オーディオトラック追加
            if let assetAudioTrack = asset.tracks(withMediaType: .audio).first {
                do {
                    try audioTrack?.insertTimeRange(
                        CMTimeRange(start: .zero, duration: asset.duration),
                        of: assetAudioTrack,
                        at: currentTime
                    )
                    print("✅ セグメント\(index + 1) オーディオトラック追加完了")
                } catch {
                    print("❌ セグメント\(index + 1) オーディオトラック追加エラー: \(error)")
                }
            }
            
            currentTime = CMTimeAdd(currentTime, asset.duration)
        }
        
        // プレイヤー作成と再生
        let playerItem = AVPlayerItem(asset: composition)
        compositionPlayer = AVPlayer(playerItem: playerItem)
        
        // プレイヤーレイヤー設定
        if playerLayer == nil {
            playerLayer = AVPlayerLayer(player: compositionPlayer)
            playerLayer?.videoGravity = .resizeAspectFill
        } else {
            playerLayer?.player = compositionPlayer
        }
        
        // 再生完了監視
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            print("✅ AVComposition再生完了")
            self.stopCompositionPlayback()
        }
        
        // 音声設定
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ オーディオセッション設定エラー: \(error.localizedDescription)")
        }
        
        // 再生開始
        compositionPlayer?.play()
        print("🎵 AVComposition再生開始！")
    }
    
    private func simulateCompositionPlayback() {
        print("📱 Composition再生をシミュレート")
        
        // シミュレーター用：全セグメントを一度に処理
        let totalDuration = Double(currentSegments.count) * 1.2
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: totalDuration, repeats: false) { [weak self] timer in
            DispatchQueue.main.async {
                self?.stopCompositionPlayback()
            }
        }
    }
    
    func stopCompositionPlayback() {
        print("⏹ AVComposition再生停止")
        
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        compositionPlayer?.pause()
        compositionPlayer = nil
        composition = nil
        
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isCompositionMode = false
            self.currentSegmentIndex = 0
        }
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    // MARK: - 従来のPlayback Functions (比較用に維持)
    
    func startSeamlessPlayback(segments: [VideoSegment]) {
        print("▶️ 従来のシームレス再生開始 - セグメント数: \(segments.count)")
        
        guard !segments.isEmpty else {
            print("❌ 再生するセグメントがありません")
            return
        }
        
        stopPlayback()
        
        currentSegments = segments
        
        DispatchQueue.main.async {
            self.isCompositionMode = false
            self.currentSegmentIndex = 0
            self.isPlaying = true
        }
        
        if isSimulator {
            simulatePlayback()
        } else {
            playCurrentSegment()
        }
    }
    
    private func simulatePlayback() {
        print("📱 シミュレーター再生をシミュレート")
        
        playbackTimer?.invalidate()
        
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            DispatchQueue.main.async {
                if self.currentSegmentIndex < self.currentSegments.count - 1 {
                    self.currentSegmentIndex += 1
                    print("🎬 シミュレーター: セグメント \(self.currentSegmentIndex + 1)/\(self.currentSegments.count)")
                } else {
                    timer.invalidate()
                    self.playbackTimer = nil
                    self.stopPlayback()
                }
            }
        }
    }
    
    private func playCurrentSegment() {
        guard currentSegmentIndex < currentSegments.count else {
            stopPlayback()
            return
        }
        
        let segment = currentSegments[currentSegmentIndex]
        
        let url: URL
        if segment.uri.hasPrefix("file://") {
            url = URL(string: segment.uri) ?? URL(fileURLWithPath: segment.uri.replacingOccurrences(of: "file://", with: ""))
        } else {
            url = URL(fileURLWithPath: segment.uri)
        }
        
        if !FileManager.default.fileExists(atPath: url.path) {
            print("❌ ファイルが存在しません: \(url.path)")
            nextSegment()
            return
        }
        
        print("▶️ セグメント再生: \(currentSegmentIndex + 1)/\(currentSegments.count)")
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        if playerLayer == nil {
            playerLayer = AVPlayerLayer(player: player)
            playerLayer?.videoGravity = .resizeAspectFill
        } else {
            playerLayer?.player = player
        }
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            self.nextSegment()
        }
        
        player?.play()
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ オーディオセッション設定エラー: \(error.localizedDescription)")
        }
    }
    
    private func nextSegment() {
        DispatchQueue.main.async {
            if self.currentSegmentIndex < self.currentSegments.count - 1 {
                self.currentSegmentIndex += 1
                DispatchQueue.global(qos: .userInitiated).async {
                    self.playCurrentSegment()
                }
            } else {
                print("✅ 全セグメント再生完了")
                self.stopPlayback()
            }
        }
    }
    
    func stopPlayback() {
        print("⏹ 従来の再生停止")
        
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        player?.pause()
        player = nil
        
        DispatchQueue.main.async {
            self.isPlaying = false
            self.isCompositionMode = false
            self.currentSegmentIndex = 0
        }
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
    }
    
    // MARK: - Helper Functions
    
    func getPlayerLayer() -> AVPlayerLayer? {
        return playerLayer
    }
    
    func jumpToSegment(_ index: Int) {
        guard index >= 0 && index < currentSegments.count else { return }
        
        DispatchQueue.main.async {
            self.currentSegmentIndex = index
        }
        
        if isPlaying && !isSimulator && !isCompositionMode {
            playCurrentSegment()
        }
    }
    
    func setupCameraSession() -> AVCaptureSession? {
        return captureSession
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer?.videoGravity = .resizeAspectFill
        }
        return previewLayer!
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoManager: AVCaptureFileOutputRecordingDelegate {
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("✅ 録画が開始されました: \(fileURL.lastPathComponent)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        if let error = error {
            print("❌ 録画エラー: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isRecording = false
            }
            return
        }
        
        print("✅ 録画完了: \(outputFileURL.lastPathComponent)")
        print("📁 ファイルサイズ: \(getFileSize(url: outputFileURL))")
        
        DispatchQueue.main.async {
            self.onRecordingComplete?(outputFileURL)
        }
    }
    
    private func getFileSize(url: URL) -> String {
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = fileAttributes[FileAttributeKey.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
            }
        } catch {
            print("ファイルサイズ取得エラー: \(error)")
        }
        return "不明"
    }
}
