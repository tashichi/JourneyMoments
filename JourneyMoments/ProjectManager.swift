import Foundation
import Combine

class ProjectManager: ObservableObject {
    @Published var projects: [Project] = []
    @Published var currentProject: Project?
    
    private let userDefaults = UserDefaults.standard
    private let projectsKey = "saved_projects"
    
    init() {
        loadProjects()
    }
    
    // MARK: - プロジェクト管理
    
    /// 新しいプロジェクト作成
    func createNewProject(name: String? = nil) -> Project {
        let projectName = name ?? "プロジェクト \(projects.count + 1)"
        let newProject = Project(name: projectName)
        
        projects.append(newProject)
        currentProject = newProject
        saveProjects()
        
        print("新しいプロジェクト作成: \(projectName)")
        return newProject
    }
    
    /// プロジェクト選択
    func selectProject(_ project: Project) {
        currentProject = project
        print("プロジェクト選択: \(project.name)")
    }
    
    /// プロジェクト名変更
    func renameProject(_ project: Project, newName: String) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        
        projects[index].name = newName
        projects[index].lastModified = Date()
        
        // 現在のプロジェクトも更新
        if currentProject?.id == project.id {
            currentProject?.name = newName
            currentProject?.lastModified = Date()
        }
        
        saveProjects()
        print("プロジェクト名変更: \(newName)")
    }
    
    /// プロジェクトにセグメント追加
    func addSegmentToProject(_ segment: VideoSegment, to project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        
        projects[index].segments.append(segment)
        projects[index].lastModified = Date()
        
        // 現在のプロジェクトも更新
        if currentProject?.id == project.id {
            currentProject?.segments.append(segment)
            currentProject?.lastModified = Date()
        }
        
        saveProjects()
        print("セグメント追加: \(segment.id)")
    }
    
    /// プロジェクト更新（録画機能で使用）
    func updateProject(_ updatedProject: Project) {
        print("🔄 プロジェクト更新処理開始: \(updatedProject.name)")
        
        // 既存のプロジェクトを探して更新
        if let index = projects.firstIndex(where: { $0.id == updatedProject.id }) {
            projects[index] = updatedProject
            saveProjects()
            print("✅ プロジェクトが更新されました: \(updatedProject.name)")
            print("📊 セグメント数: \(updatedProject.segments.count)")
        } else {
            print("❌ 更新対象のプロジェクトが見つかりません: ID \(updatedProject.id)")
        }
    }
    
    /// セグメント削除
    func removeSegment(_ segment: VideoSegment, from project: Project) {
        guard let projectIndex = projects.firstIndex(where: { $0.id == project.id }) else { return }
        
        projects[projectIndex].segments.removeAll { $0.id == segment.id }
        projects[projectIndex].lastModified = Date()
        
        // 現在のプロジェクトも更新
        if currentProject?.id == project.id {
            currentProject?.segments.removeAll { $0.id == segment.id }
            currentProject?.lastModified = Date()
        }
        
        // ファイル削除
        deleteVideoFile(at: segment.url)
        
        saveProjects()
        print("セグメント削除: \(segment.id)")
    }
    
    /// プロジェクト削除
    func deleteProject(_ project: Project) {
        // プロジェクトの全動画ファイルを削除
        for segment in project.segments {
            deleteVideoFile(at: segment.url)
        }
        
        // プロジェクトをリストから削除
        projects.removeAll { $0.id == project.id }
        
        // 現在のプロジェクトが削除された場合
        if currentProject?.id == project.id {
            currentProject = projects.first
        }
        
        saveProjects()
        print("プロジェクト削除: \(project.name)")
    }
    
    // MARK: - データ永続化
    
    /// プロジェクト一覧保存
    private func saveProjects() {
        do {
            let data = try JSONEncoder().encode(projects)
            userDefaults.set(data, forKey: projectsKey)
            print("プロジェクト保存成功: \(projects.count)件")
        } catch {
            print("プロジェクト保存エラー: \(error)")
        }
    }
    
    /// プロジェクト一覧読み込み
    private func loadProjects() {
        guard let data = userDefaults.data(forKey: projectsKey) else {
            print("保存されたプロジェクトなし")
            return
        }
        
        do {
            let loadedProjects = try JSONDecoder().decode([Project].self, from: data)
            projects = loadedProjects
            currentProject = projects.first
            print("プロジェクト読み込み成功: \(projects.count)件")
        } catch {
            print("プロジェクト読み込みエラー: \(error)")
            projects = []
        }
    }
    
    /// 現在のプロジェクト状態保存
    func saveCurrentProject() {
        guard let current = currentProject else { return }
        
        if let index = projects.firstIndex(where: { $0.id == current.id }) {
            projects[index] = current
            saveProjects()
        }
    }
    
    // MARK: - ファイル管理
    
    /// 動画ファイル削除
    private func deleteVideoFile(at url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                print("動画ファイル削除成功: \(url.lastPathComponent)")
            }
        } catch {
            print("動画ファイル削除エラー: \(error)")
        }
    }
    
    /// アプリディレクトリの動画ファイル移動
    func moveVideoToAppDirectory(_ tempURL: URL) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask)[0]
        let appVideoDir = documentsPath.appendingPathComponent("JourneyMoments")
        
        // ディレクトリ作成
        do {
            try FileManager.default.createDirectory(at: appVideoDir,
                                                  withIntermediateDirectories: true)
        } catch {
            print("ディレクトリ作成エラー: \(error)")
            return nil
        }
        
        // 新しいファイル名生成
        let fileName = "video_\(Date().timeIntervalSince1970).mov"
        let destinationURL = appVideoDir.appendingPathComponent(fileName)
        
        // ファイル移動
        do {
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            print("動画ファイル移動成功: \(fileName)")
            return destinationURL
        } catch {
            print("動画ファイル移動エラー: \(error)")
            return nil
        }
    }
    
    // MARK: - 統計・ユーティリティ
    
    /// 総セグメント数取得
    func getTotalSegments() -> Int {
        return projects.reduce(0) { $0 + $1.segments.count }
    }
    
    /// 総録画時間取得（秒）
    func getTotalDuration() -> Double {
        return projects.reduce(0) { projectSum, project in
            projectSum + project.segments.reduce(0) { $0 + $1.duration }
        }
    }
    
    /// プロジェクト作成日順ソート
    func sortProjectsByDate() {
        projects.sort { $0.createdAt > $1.createdAt }
    }
    
    /// プロジェクト名順ソート
    func sortProjectsByName() {
        projects.sort { $0.name < $1.name }
    }
    
    /// 最近変更されたプロジェクト順ソート
    func sortProjectsByLastModified() {
        projects.sort { $0.lastModified > $1.lastModified }
    }
    
    // MARK: - 検索・フィルタ
    
    /// プロジェクト検索
    func searchProjects(query: String) -> [Project] {
        if query.isEmpty {
            return projects
        }
        
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
        }
    }
    
    /// セグメント数でフィルタ
    func filterProjects(minSegments: Int) -> [Project] {
        return projects.filter { $0.segments.count >= minSegments }
    }
    
    /// 期間でフィルタ
    func filterProjects(from startDate: Date, to endDate: Date) -> [Project] {
        return projects.filter { project in
            project.createdAt >= startDate && project.createdAt <= endDate
        }
    }
    
    // MARK: - データ整合性チェック
    
    /// 存在しない動画ファイルのセグメントを削除
    func cleanupMissingVideoFiles() {
        var hasChanges = false
        
        for projectIndex in projects.indices {
            let originalCount = projects[projectIndex].segments.count
            
            projects[projectIndex].segments = projects[projectIndex].segments.filter { segment in
                FileManager.default.fileExists(atPath: segment.url.path)
            }
            
            if projects[projectIndex].segments.count != originalCount {
                projects[projectIndex].lastModified = Date()
                hasChanges = true
            }
        }
        
        if hasChanges {
            saveProjects()
            print("存在しない動画ファイルのクリーンアップ完了")
        }
    }
    
    /// データ整合性チェック実行
    func performDataIntegrityCheck() {
        cleanupMissingVideoFiles()
    }
}


