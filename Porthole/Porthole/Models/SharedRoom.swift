//
//  SharedRoom.swift
//  Porthole
//
//  Models for Multipeer shared camera room.
//

import Foundation
import MultipeerConnectivity

// MARK: - Room Participant

/// Represents a participant in a shared camera room
struct RoomParticipant: Identifiable, Hashable {
    let id: String  // MCPeerID.displayName
    let displayName: String
    let deviceName: String
    var isConnected: Bool
    var isHost: Bool
    var isSharingCamera: Bool
    
    init(peerID: MCPeerID, isHost: Bool = false) {
        self.id = peerID.displayName
        self.displayName = peerID.displayName
        self.deviceName = peerID.displayName
        self.isConnected = true
        self.isHost = isHost
        self.isSharingCamera = false
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: RoomParticipant, rhs: RoomParticipant) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Room State

/// Represents the state of a shared camera room
enum RoomState: Equatable {
    case idle                      // Not in any room
    case creating                  // Creating a room
    case joining                   // Joining a room
    case connected(roomName: String)  // Connected to a room
    case disconnected(reason: String) // Disconnected with reason
    
    var isActive: Bool {
        switch self {
        case .connected: return true
        default: return false
        }
    }
}

// MARK: - Display Mode

/// How to display multiple camera feeds in PiP
enum SharedDisplayMode: String, CaseIterable, Identifiable {
    case local = "local"           // Only show local camera
    case remote = "remote"         // Only show remote camera (selected peer)
    case sideBySide = "sideBySide" // Show both side by side
    case pictureInPicture = "pip"  // Local large, remote small corner
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .local: return "本地"
        case .remote: return "远程"
        case .sideBySide: return "并排"
        case .pictureInPicture: return "画中画"
        }
    }
    
    var iconName: String {
        switch self {
        case .local: return "camera.fill"
        case .remote: return "person.wave.2.fill"
        case .sideBySide: return "rectangle.split.2x1.fill"
        case .pictureInPicture: return "pip.fill"
        }
    }
}

// MARK: - Message Types

/// Types of messages exchanged between peers
enum PeerMessageType: UInt8 {
    case videoFrame = 1
    case cameraStatus = 2
    case participantUpdate = 3
    case ping = 4
    case pong = 5
}

/// Header for peer messages (for efficient parsing)
struct PeerMessageHeader {
    let type: PeerMessageType
    let timestamp: UInt64
    let dataLength: UInt32
    
    static let size = 13  // 1 + 8 + 4 bytes
    
    init(type: PeerMessageType, timestamp: UInt64, dataLength: UInt32) {
        self.type = type
        self.timestamp = timestamp
        self.dataLength = dataLength
    }
    
    init?(data: Data) {
        guard data.count >= Self.size else { return nil }
        
        guard let type = PeerMessageType(rawValue: data[0]) else { return nil }
        self.type = type
        
        self.timestamp = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 1, as: UInt64.self)
        }
        
        self.dataLength = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 9, as: UInt32.self)
        }
    }
    
    func toData() -> Data {
        var data = Data(capacity: Self.size)
        data.append(type.rawValue)
        withUnsafeBytes(of: timestamp) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: dataLength) { data.append(contentsOf: $0) }
        return data
    }
}

// MARK: - Video Frame Packet

/// Compact video frame data for network transmission
struct VideoFramePacket {
    let width: UInt16
    let height: UInt16
    let pixelData: Data
    
    static let headerSize = 4  // 2 + 2 bytes
    
    init(width: Int, height: Int, pixelData: Data) {
        self.width = UInt16(width)
        self.height = UInt16(height)
        self.pixelData = pixelData
    }
    
    init?(data: Data) {
        guard data.count >= Self.headerSize else { return nil }
        
        self.width = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 0, as: UInt16.self)
        }
        self.height = data.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 2, as: UInt16.self)
        }
        
        guard data.count >= Self.headerSize + Int(width) * Int(height) * 4 else {
            return nil
        }
        
        self.pixelData = data.subdata(in: Self.headerSize..<data.count)
    }
    
    func toData() -> Data {
        var data = Data(capacity: Self.headerSize + pixelData.count)
        withUnsafeBytes(of: width) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: height) { data.append(contentsOf: $0) }
        data.append(pixelData)
        return data
    }
}

// MARK: - Camera Status Message

/// Camera sharing status update message
struct CameraStatusMessage: Codable {
    let peerId: String
    let isSharing: Bool
    let timestamp: TimeInterval
    
    init(peerId: String, isSharing: Bool) {
        self.peerId = peerId
        self.isSharing = isSharing
        self.timestamp = Date().timeIntervalSince1970
    }
}
