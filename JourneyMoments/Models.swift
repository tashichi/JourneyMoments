import Foundation

// MARK: - Project Model

struct Project: Identifiable, Codable {
    let id: Double
    var name: String
    var segments: [VideoSegment]
    let createdAt: Date
    var lastModified: Date
    
    init(name: String) {
        self.id = Date().timeIntervalSince1970
        self.name = name
        self.segments = []
        self.createdAt = Date()
        self.lastModified = Date()
    }
}

// MARK: - VideoSegment Model

struct VideoSegment: Identifiable, Codable {
    let id: Double
    let uri: String
    let timestamp: Date
    let facing: String
    let order: Int
    let duration: Double
    
    init(id: Double, uri: String, timestamp: Date, facing: String, order: Int, duration: Double = 1.0) {
        self.id = id
        self.uri = uri
        self.timestamp = timestamp
        self.facing = facing
        self.order = order
        self.duration = duration
    }
    
    // URLプロパティのcomputed property
    var url: URL {
        return URL(string: uri) ?? URL(fileURLWithPath: "")
    }
}

// MARK: - Project Extensions

extension Project {
    /// プロジェクトの総時間
    var totalDuration: Double {
        return segments.reduce(0) { $0 + $1.duration }
    }
    
    /// 最新セグメントの日時
    var lastSegmentDate: Date? {
        return segments.max(by: { $0.timestamp < $1.timestamp })?.timestamp
    }
    
    /// プロジェクトが空かどうか
    var isEmpty: Bool {
        return segments.isEmpty
    }
}

// MARK: - VideoSegment Extensions

extension VideoSegment {
    /// セグメントの表示用名前
    var displayName: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return "セグメント \(order + 1) - \(formatter.string(from: timestamp))"
    }
    
    /// ファイルサイズ取得（存在する場合）
    var fileSize: String {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            print("ファイルサイズ取得エラー: \(error)")
        }
        return "不明"
    }
    
    /// ファイルが存在するかチェック
    var fileExists: Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
}//
//  Models.swift
//  JourneyMoments
//
//  Created by 谷澤健二 on 2025/08/08.
//

