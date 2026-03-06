//
//  MultipeerService.swift
//  Porthole
//
//  Core Multipeer Connectivity service for shared camera functionality.
//  Handles peer discovery, connection management, and data transmission.
//

import Foundation
import MultipeerConnectivity
import Combine
import AVFoundation
import UIKit

// MARK: - MultipeerService Delegate

@MainActor
protocol MultipeerServiceDelegate: AnyObject {
    func multipeerService(_ service: MultipeerService, didChangeState state: RoomState)
    func multipeerService(_ service: MultipeerService, didUpdateParticipants participants: [RoomParticipant])
    func multipeerService(_ service: MultipeerService, didReceiveVideoFrame frame: CMSampleBuffer, from peerId: String)
    func multipeerService(_ service: MultipeerService, peerDidStartSharing peerId: String)
    func multipeerService(_ service: MultipeerService, peerDidStopSharing peerId: String)
}

// MARK: - MultipeerService

/// Manages Multipeer Connectivity sessions for shared camera functionality
@MainActor
final class MultipeerService: NSObject, ObservableObject {
    
    // MARK: - Constants
    
    private static let serviceType = "porthole-share"  // Max 15 chars, lowercase alphanumeric + hyphen
    
    // MARK: - Published Properties
    
    @Published private(set) var state: RoomState = .idle
    @Published private(set) var participants: [RoomParticipant] = []
    @Published private(set) var isAdvertising = false
    @Published private(set) var isBrowsing = false
    @Published var selectedRemotePeerId: String?
    
    // MARK: - Public Properties
    
    weak var delegate: MultipeerServiceDelegate?
    
    var localPeerId: String {
        peerID.displayName
    }
    
    var connectedPeers: [String] {
        participants.filter { $0.isConnected && $0.id != localPeerId }.map { $0.id }
    }
    
    // MARK: - Private Properties
    
    private let peerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private let sessionQueue = DispatchQueue(label: "com.porthole.multipeer.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "com.porthole.multipeer.frame", qos: .userInitiated)
    
    // Frame rate control
    private var lastFrameSendTime: CFTimeInterval = 0
    private let minFrameInterval: CFTimeInterval = 1.0 / 15.0  // Max 15 fps for network
    
    // Video frame processing
    private var frameEncoder: VideoFrameEncoder?
    private var frameDecoder: VideoFrameDecoder?
    
    // Discovered peers waiting for invitation
    private var discoveredPeers: [MCPeerID: [String: String]?] = [:]
    
    // Room info
    private var currentRoomName: String?
    private var isRoomHost = false
    
    // MARK: - Initialization
    
    override init() {
        // Use device name for peer ID (required for non-anonymous connections)
        self.peerID = MCPeerID(displayName: UIDevice.current.name)
        
        super.init()
        
        self.frameEncoder = VideoFrameEncoder()
        self.frameDecoder = VideoFrameDecoder()
        
        print("[MultipeerService] Initialized with peer ID: \(peerID.displayName)")
    }
    
    deinit {
        print("[MultipeerService] Deinit")
    }
    
    // MARK: - Room Management
    
    /// Create and host a new room
    func createRoom(name: String) {
        guard state == .idle || !state.isActive else {
            print("[MultipeerService] Cannot create room: already in a room")
            return
        }
        
        print("[MultipeerService] Creating room: \(name)")
        
        state = .creating
        currentRoomName = name
        isRoomHost = true
        
        // Create session
        setupSession()
        
        // Start advertising
        startAdvertising(roomName: name)
        
        // Add self as host participant
        let hostParticipant = RoomParticipant(peerID: peerID, isHost: true)
        participants = [hostParticipant]
        
        // Transition to connected state
        state = .connected(roomName: name)
        delegate?.multipeerService(self, didChangeState: state)
        delegate?.multipeerService(self, didUpdateParticipants: participants)
    }
    
    /// Browse and join an existing room
    func joinRoom() {
        guard state == .idle || !state.isActive else {
            print("[MultipeerService] Cannot join room: already in a room")
            return
        }
        
        print("[MultipeerService] Browsing for rooms...")
        
        state = .joining
        isRoomHost = false
        
        // Create session
        setupSession()
        
        // Start browsing
        startBrowsing()
        
        delegate?.multipeerService(self, didChangeState: state)
    }
    
    /// Leave current room
    func leaveRoom() {
        print("[MultipeerService] Leaving room")
        
        stopAdvertising()
        stopBrowsing()
        
        session?.disconnect()
        session = nil
        
        participants = []
        discoveredPeers.removeAll()
        currentRoomName = nil
        isRoomHost = false
        selectedRemotePeerId = nil
        
        state = .idle
        delegate?.multipeerService(self, didChangeState: state)
        delegate?.multipeerService(self, didUpdateParticipants: participants)
    }
    
    // MARK: - Session Setup
    
    private func setupSession() {
        session?.disconnect()
        
        let newSession = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required  // Always encrypt for privacy
        )
        newSession.delegate = self
        session = newSession
        
        print("[MultipeerService] Session created")
    }
    
    // MARK: - Advertising
    
    private func startAdvertising(roomName: String) {
        guard !isAdvertising else { return }
        
        let discoveryInfo: [String: String] = [
            "roomName": roomName,
            "hostName": peerID.displayName
        ]
        
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: discoveryInfo,
            serviceType: Self.serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        isAdvertising = true
        print("[MultipeerService] Started advertising room: \(roomName)")
    }
    
    private func stopAdvertising() {
        guard isAdvertising else { return }
        
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
        
        print("[MultipeerService] Stopped advertising")
    }
    
    // MARK: - Browsing
    
    private func startBrowsing() {
        guard !isBrowsing else { return }
        
        browser = MCNearbyServiceBrowser(
            peer: peerID,
            serviceType: Self.serviceType
        )
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        isBrowsing = true
        print("[MultipeerService] Started browsing for peers")
    }
    
    private func stopBrowsing() {
        guard isBrowsing else { return }
        
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
        discoveredPeers.removeAll()
        
        print("[MultipeerService] Stopped browsing")
    }
    
    // MARK: - Video Frame Transmission
    
    /// Send a video frame to all connected peers
    func sendVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let session = session,
              !session.connectedPeers.isEmpty else { return }
        
        // Frame rate limiting
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastFrameSendTime >= minFrameInterval else { return }
        lastFrameSendTime = currentTime
        
        frameQueue.async { [weak self] in
            guard let self = self,
                  let encoder = self.frameEncoder else { return }
            
            // Encode frame to compressed data
            guard let frameData = encoder.encode(sampleBuffer) else { return }
            
            // Create message with header
            let header = PeerMessageHeader(
                type: .videoFrame,
                timestamp: UInt64(currentTime * 1000),
                dataLength: UInt32(frameData.count)
            )
            
            var messageData = header.toData()
            messageData.append(frameData)
            
            // Send to all peers (unreliable for lower latency)
            do {
                try session.send(messageData, toPeers: session.connectedPeers, with: .unreliable)
            } catch {
                print("[MultipeerService] Failed to send frame: \(error)")
            }
        }
    }
    
    /// Notify peers about camera sharing status
    func sendCameraStatus(isSharing: Bool) {
        guard let session = session,
              !session.connectedPeers.isEmpty else { return }
        
        let status = CameraStatusMessage(peerId: peerID.displayName, isSharing: isSharing)
        
        sessionQueue.async {
            do {
                let data = try JSONEncoder().encode(status)
                let header = PeerMessageHeader(
                    type: .cameraStatus,
                    timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                    dataLength: UInt32(data.count)
                )
                
                var messageData = header.toData()
                messageData.append(data)
                
                try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                print("[MultipeerService] Failed to send camera status: \(error)")
            }
        }
    }
    
    // MARK: - Participant Management
    
    private func updateParticipant(peerID: MCPeerID, isConnected: Bool) {
        Task { @MainActor in
            if isConnected {
                // Add or update participant
                if let index = participants.firstIndex(where: { $0.id == peerID.displayName }) {
                    participants[index].isConnected = true
                } else {
                    let participant = RoomParticipant(peerID: peerID, isHost: false)
                    participants.append(participant)
                }
                
                // Auto-select first remote peer if none selected
                if selectedRemotePeerId == nil && peerID.displayName != self.peerID.displayName {
                    selectedRemotePeerId = peerID.displayName
                }
            } else {
                // Mark as disconnected or remove
                if let index = participants.firstIndex(where: { $0.id == peerID.displayName }) {
                    participants.remove(at: index)
                }
                
                // Clear selection if this peer was selected
                if selectedRemotePeerId == peerID.displayName {
                    selectedRemotePeerId = connectedPeers.first
                }
            }
            
            delegate?.multipeerService(self, didUpdateParticipants: participants)
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {
    
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let stateString: String
        switch state {
        case .notConnected: stateString = "not connected"
        case .connecting: stateString = "connecting"
        case .connected: stateString = "connected"
        @unknown default: stateString = "unknown"
        }
        
        print("[MultipeerService] Peer \(peerID.displayName) state: \(stateString)")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            switch state {
            case .connected:
                self.updateParticipant(peerID: peerID, isConnected: true)
                
                // If we were joining, we're now connected
                if case .joining = self.state {
                    // Get room name from discovery info if available
                    let roomName = self.currentRoomName ?? "共享房间"
                    self.state = .connected(roomName: roomName)
                    self.delegate?.multipeerService(self, didChangeState: self.state)
                }
                
            case .notConnected:
                self.updateParticipant(peerID: peerID, isConnected: false)
                
                // If all peers disconnected and we're not host, leave room
                if !self.isRoomHost && self.participants.filter({ $0.id != self.localPeerId }).isEmpty {
                    self.state = .disconnected(reason: "所有参与者已离开")
                    self.delegate?.multipeerService(self, didChangeState: self.state)
                }
                
            case .connecting:
                break
                
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Parse message header
        guard let header = PeerMessageHeader(data: data) else {
            print("[MultipeerService] Invalid message header from \(peerID.displayName)")
            return
        }
        
        let payloadStart = PeerMessageHeader.size
        let payloadData = data.subdata(in: payloadStart..<data.count)
        
        switch header.type {
        case .videoFrame:
            // Decode and deliver video frame
            Task { @MainActor [weak self] in
                guard let self = self,
                      let decoder = self.frameDecoder,
                      let sampleBuffer = decoder.decode(payloadData) else { return }
                
                self.delegate?.multipeerService(self, didReceiveVideoFrame: sampleBuffer, from: peerID.displayName)
            }
            
        case .cameraStatus:
            // Handle camera status update
            if let status = try? JSONDecoder().decode(CameraStatusMessage.self, from: payloadData) {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    if let index = self.participants.firstIndex(where: { $0.id == status.peerId }) {
                        self.participants[index].isSharingCamera = status.isSharing
                        self.delegate?.multipeerService(self, didUpdateParticipants: self.participants)
                        
                        if status.isSharing {
                            self.delegate?.multipeerService(self, peerDidStartSharing: status.peerId)
                        } else {
                            self.delegate?.multipeerService(self, peerDidStopSharing: status.peerId)
                        }
                    }
                }
            }
            
        case .ping:
            // Respond with pong
            let pongHeader = PeerMessageHeader(type: .pong, timestamp: header.timestamp, dataLength: 0)
            try? session.send(pongHeader.toData(), toPeers: [peerID], with: .unreliable)
            
        case .pong, .participantUpdate:
            break
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used - we use datagram messages instead
    }
    
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used
    }
    
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("[MultipeerService] Received invitation from \(peerID.displayName)")
        
        Task { @MainActor [weak self] in
            guard let self = self else {
                invitationHandler(false, nil)
                return
            }
            
            // Auto-accept invitations when hosting
            if self.isRoomHost {
                print("[MultipeerService] Auto-accepting invitation from \(peerID.displayName)")
                invitationHandler(true, self.session)
            } else {
                invitationHandler(false, nil)
            }
        }
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("[MultipeerService] Failed to start advertising: \(error)")
        
        Task { @MainActor [weak self] in
            self?.state = .disconnected(reason: "无法创建房间: \(error.localizedDescription)")
            self?.delegate?.multipeerService(self!, didChangeState: self!.state)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("[MultipeerService] Found peer: \(peerID.displayName), info: \(info ?? [:])")
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Store discovered peer
            self.discoveredPeers[peerID] = info
            
            // Auto-join the first discovered room
            if case .joining = self.state {
                // Get room name from discovery info
                if let roomName = info?["roomName"] {
                    self.currentRoomName = roomName
                }
                
                print("[MultipeerService] Inviting peer: \(peerID.displayName)")
                browser.invitePeer(peerID, to: self.session!, withContext: nil, timeout: 30)
            }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("[MultipeerService] Lost peer: \(peerID.displayName)")
        
        Task { @MainActor [weak self] in
            self?.discoveredPeers.removeValue(forKey: peerID)
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("[MultipeerService] Failed to start browsing: \(error)")
        
        Task { @MainActor [weak self] in
            self?.state = .disconnected(reason: "无法搜索房间: \(error.localizedDescription)")
            self?.delegate?.multipeerService(self!, didChangeState: self!.state)
        }
    }
}
