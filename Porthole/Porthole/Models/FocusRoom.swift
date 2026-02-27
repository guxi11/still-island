//
//  FocusRoom.swift
//  Porthole
//
//  专注房间数据模型
//

import Foundation

/// 专注房间
struct FocusRoom {
    /// 房间名称
    var name: String
    
    /// 房主 Peer ID
    var hostPeerId: String
    
    /// 所有参与者（包括自己）
    var peers: [FocusPeer]
    
    /// 是否是房主
    var isHost: Bool
    
    /// 正在专注的人数
    var focusingCount: Int {
        peers.filter { $0.isFocusing }.count
    }
    
    /// 获取指定 ID 的参与者
    func peer(withId id: String) -> FocusPeer? {
        peers.first { $0.id == id }
    }
    
    /// 更新参与者状态
    mutating func updatePeer(_ peer: FocusPeer) {
        if let index = peers.firstIndex(where: { $0.id == peer.id }) {
            peers[index] = peer
        } else {
            peers.append(peer)
        }
    }
    
    /// 移除参与者
    mutating func removePeer(withId id: String) {
        peers.removeAll { $0.id == id }
    }
}

/// 发现的附近房间
struct DiscoveredRoom: Identifiable, Equatable {
    let id: String          // MCPeerID.displayName
    let roomName: String
    let hostName: String
    var peerCount: Int
    
    static func == (lhs: DiscoveredRoom, rhs: DiscoveredRoom) -> Bool {
        lhs.id == rhs.id
    }
}
