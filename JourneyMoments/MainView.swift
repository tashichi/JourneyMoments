import SwiftUI
import AVFoundation

struct MainView: View {
    @StateObject private var projectManager = ProjectManager()
    @StateObject private var videoManager = VideoManager()
    @State private var currentScreen: AppScreen = .projects
    @State private var currentProject: Project?
    @State private var showingCameraPermissionAlert = false

    enum AppScreen {
        case projects
        case camera
        case player
    }

    var body: some View {
        Group {
            switch currentScreen {
            case .projects:
                ProjectListView()
            case .camera:
                CameraView()
            case .player:
                PlayerView()
            }
        }
        .onAppear {
            setupVideoManagerCallbacks()
        }
    }

    // MARK: - View Components
    
    @ViewBuilder
    private func ProjectListView() -> some View {
        VStack(spacing: 20) {
            Text("JourneyMoments")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            Text("プロジェクト一覧")
                .font(.title2)
                .foregroundColor(.secondary)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(projectManager.projects) { project in
                        ProjectRow(project: project) {
                            openProject(project)
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Button(action: createNewProject) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("新しいプロジェクト")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding(.bottom, 30)
        }
        .alert("カメラへのアクセスが必要です", isPresented: $showingCameraPermissionAlert) {
            Button("設定を開く") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("キャンセル", role: .cancel) {
                currentScreen = .projects
            }
        }
    }
    
    @ViewBuilder
    private func CameraView() -> some View {
        VStack {
            // ナビゲーションバー
            HStack {
                Button("戻る") {
                    videoManager.safeStopSession()
                    currentScreen = .projects
                }
                .padding(.leading)
                
                Spacer()
                
                Text(currentProject?.name ?? "カメラ")
                    .font(.headline)
                
                Spacer()
                
                Button("再生") {
                    if currentProject?.segments.isEmpty == false {
                        videoManager.safeStopSession()
                        currentScreen = .player
                    }
                }
                .padding(.trailing)
                .disabled(currentProject?.segments.isEmpty ?? true)
            }
            .padding(.vertical)
            
            // カメラプレビュー領域
            CameraPreviewView(session: videoManager.captureSession)
                .aspectRatio(16/9, contentMode: .fit)
                .cornerRadius(12)
                .padding(.horizontal)
                .overlay(
                    // 録画中のインジケーター
                    Group {
                        if videoManager.isRecording {
                            VStack {
                                HStack {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 12, height: 12)
                                    Text("録画中...")
                                        .foregroundColor(.red)
                                        .font(.headline)
                                    Spacer()
                                }
                                Spacer()
                            }
                            .padding()
                        }
                    }
                )
            
            Spacer()
            
            // セグメント情報
            if let project = currentProject {
                Text("セグメント数: \(project.segments.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
            }
            
            // 撮影ボタン
            Button(action: recordVideo) {
                Circle()
                    .fill(videoManager.isRecording ? Color.gray : Color.red)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                    )
                    .scaleEffect(videoManager.isRecording ? 0.9 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: videoManager.isRecording)
            }
            .disabled(videoManager.isRecording)
            .padding(.bottom, 50)
        }
        .onAppear {
            videoManager.startSession()
        }
        .onDisappear {
            videoManager.safeStopSession()
        }
    }
    
    @ViewBuilder
    private func PlayerView() -> some View {
        VStack {
            // ナビゲーションバー
            HStack {
                Button("戻る") {
                    currentScreen = .camera
                }
                .padding(.leading)
                
                Spacer()
                
                Text(currentProject?.name ?? "再生")
                    .font(.headline)
                
                Spacer()
                
                Button("編集") {
                    // 編集機能（後で実装）
                }
                .padding(.trailing)
            }
            .padding(.vertical)
            
            // 継ぎ目テスト用の再生モード切り替え
            VStack(spacing: 10) {
                Text("継ぎ目問題テスト")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                HStack(spacing: 20) {
                    Button(action: {
                        videoManager.stopPlayback()
                        videoManager.stopCompositionPlayback()
                    }) {
                        Text("従来再生")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(videoManager.isCompositionMode ? Color.gray.opacity(0.3) : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    
                    Button(action: {
                        videoManager.stopPlayback()
                        videoManager.stopCompositionPlayback()
                    }) {
                        Text("NEW: シームレス")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(videoManager.isCompositionMode ? Color.green : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
            
            // 動画プレイヤー領域
            Rectangle()
                .fill(Color.black)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    VStack {
                        if videoManager.isCompositionMode {
                            Text("🎵 シームレス再生モード")
                                .foregroundColor(.green)
                                .font(.title2)
                                .fontWeight(.bold)
                        } else {
                            Text("▶️ 従来再生モード")
                                .foregroundColor(.white)
                                .font(.title2)
                        }
                        
                        Text("\(currentProject?.segments.count ?? 0) セグメント")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                        
                        if videoManager.isPlaying {
                            if videoManager.isCompositionMode {
                                Text("統合再生中...")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else {
                                Text("セグメント再生中...")
                                    .foregroundColor(.yellow)
                                    .font(.caption)
                            }
                        }
                        
                        if !videoManager.isCompositionMode {
                            Text("セグメント \(videoManager.currentSegmentIndex + 1)/\(currentProject?.segments.count ?? 0)")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                )
                .padding(.horizontal)
            
            // 再生コントロール
            VStack(spacing: 15) {
                // メイン再生ボタン
                HStack(spacing: 30) {
                    Button(action: previousSegment) {
                        Image(systemName: "backward.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentProject?.segments.isEmpty ?? true || videoManager.isCompositionMode)
                    
                    Button(action: togglePlayback) {
                        Image(systemName: videoManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentProject?.segments.isEmpty ?? true)
                    
                    Button(action: nextSegment) {
                        Image(systemName: "forward.fill")
                            .font(.title)
                            .foregroundColor(.blue)
                    }
                    .disabled(currentProject?.segments.isEmpty ?? true || videoManager.isCompositionMode)
                }
                
                // 継ぎ目テスト専用ボタン
                HStack(spacing: 20) {
                    Button(action: playWithTraditionalMethod) {
                        VStack {
                            Text("従来方式で再生")
                                .font(.caption)
                            Text("(継ぎ目あり)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(currentProject?.segments.isEmpty ?? true)
                    
                    Button(action: playWithCompositionMethod) {
                        VStack {
                            Text("NEW: 統合再生")
                                .font(.caption)
                            Text("(継ぎ目なし)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(currentProject?.segments.isEmpty ?? true)
                }
            }
            .padding(.vertical, 20)
            
            Spacer()
        }
        .onAppear {
            videoManager.startSession()
        }
    }
    
    // MARK: - 継ぎ目テスト用関数
    
    private func playWithTraditionalMethod() {
        print("🔴 従来方式で再生開始")
        
        guard let project = currentProject, !project.segments.isEmpty else {
            print("❌ 再生するプロジェクトまたはセグメントがありません")
            return
        }
        
        // 既存の再生を停止
        videoManager.stopPlayback()
        videoManager.stopCompositionPlayback()
        
        // 従来のシームレス再生を開始
        videoManager.startSeamlessPlayback(segments: project.segments)
        
        print("📊 従来方式 - セグメント数: \(project.segments.count)")
        print("⚠️ 継ぎ目問題: セグメント間で黒い画面が発生する可能性があります")
    }
    
    private func playWithCompositionMethod() {
        print("🎵 NEW: AVComposition統合再生開始")
        
        guard let project = currentProject, !project.segments.isEmpty else {
            print("❌ 再生するプロジェクトまたはセグメントがありません")
            return
        }
        
        // 既存の再生を停止
        videoManager.stopPlayback()
        videoManager.stopCompositionPlayback()
        
        // 新しいAVComposition再生を開始
        videoManager.startCompositionPlayback(segments: project.segments)
        
        print("📊 AVComposition方式 - セグメント数: \(project.segments.count)")
        print("✨ 期待効果: セグメント間の継ぎ目が完全に除去されます")
    }
    
    // MARK: - Helper Functions
    
    private func setupVideoManagerCallbacks() {
        videoManager.onRecordingComplete = { videoURL in
            self.handleRecordingComplete(videoURL: videoURL)
        }
    }
    
    private func createNewProject() {
        let newProject = projectManager.createNewProject(name: "新しいプロジェクト")
        openProject(newProject)
    }
    
    private func openProject(_ project: Project) {
        currentProject = project
        currentScreen = .camera
    }
    
    private func recordVideo() {
        print("🔴 撮影ボタンがタップされました")
        
        guard let currentProject = currentProject else {
            print("❌ プロジェクトが選択されていません")
            return
        }
        
        print("📹 録画開始処理 - プロジェクト: \(currentProject.name)")
        videoManager.startRecording()
    }
    
    private func handleRecordingComplete(videoURL: URL) {
        print("✅ 録画完了処理開始: \(videoURL)")
        
        guard let currentProject = currentProject else {
            print("❌ プロジェクトが見つかりません")
            return
        }
        
        let newSegment = VideoSegment(
            id: Date().timeIntervalSince1970,
            uri: videoURL.absoluteString,
            timestamp: Date(),
            facing: "back",
            order: currentProject.segments.count
        )
        
        var updatedProject = currentProject
        updatedProject.segments.append(newSegment)
        updatedProject.lastModified = Date()
        
        projectManager.updateProject(updatedProject)
        self.currentProject = updatedProject
        
        print("🎬 セグメントが追加されました。総数: \(updatedProject.segments.count)")
    }
    
    private func togglePlayback() {
        if videoManager.isPlaying {
            if videoManager.isCompositionMode {
                videoManager.stopCompositionPlayback()
            } else {
                videoManager.stopPlayback()
            }
        } else {
            // デフォルトは従来方式
            playWithTraditionalMethod()
        }
    }
    
    private func nextSegment() {
        if let project = currentProject, !project.segments.isEmpty {
            let nextIndex = min(videoManager.currentSegmentIndex + 1, project.segments.count - 1)
            videoManager.currentSegmentIndex = nextIndex
            print("次のセグメント: \(nextIndex + 1)/\(project.segments.count)")
        }
    }
    
    private func previousSegment() {
        let prevIndex = max(videoManager.currentSegmentIndex - 1, 0)
        videoManager.currentSegmentIndex = prevIndex
        if let project = currentProject {
            print("前のセグメント: \(prevIndex + 1)/\(project.segments.count)")
        }
    }
}

// MARK: - Supporting Views

struct ProjectRow: View {
    let project: Project
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(project.segments.count) セグメント")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatDate(project.lastModified))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    MainView()
}
