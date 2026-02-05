//
//  FocusPeer.swift
//  Porthole
//
//  专注房间参与者数据模型
//

import Foundation

/// 专注房间参与者
struct FocusPeer: Identifiable, Codable, Equatable {
    /// 唯一标识符（MCPeerID.displayName）
    let id: String
    
    /// 用户昵称
    var displayName: String
    
    /// 是否正在专注中
    var isFocusing: Bool
    
    /// 专注开始时间
    var focusStartTime: Date?
    
    /// 今日累计专注时长（秒）
    var totalFocusToday: TimeInterval
    
    /// 当前专注时长（动态计算）
    var currentFocusDuration: TimeInterval {
        guard isFocusing, let start = focusStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }
    
    /// 今日总专注时长（包括当前进行中的）
    var totalFocusDurationToday: TimeInterval {
        totalFocusToday + currentFocusDuration
    }
    
    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
        self.isFocusing = false
        self.focusStartTime = nil
        self.totalFocusToday = 0
    }
}

/// 用于网络传输的状态消息
struct FocusStatusMessage: Codable {
    enum MessageType: String, Codable {
        case statusUpdate   // 状态更新
        case syncRequest    // 请求同步
        case syncResponse   // 同步响应
    }
    
    let type: MessageType
    let peer: FocusPeer
    let timestamp: Date
    
    init(type: MessageType, peer: FocusPeer) {
        self.type = type
        self.peer = peer
        self.timestamp = Date()
    }
}
