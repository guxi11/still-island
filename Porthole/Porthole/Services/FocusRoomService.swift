//
//  FocusRoomService.swift
//  Porthole
//
//  MultipeerConnectivity 专注房间服务
//  支持创建、加入、发现房间，同步专注状态
//

import Foundation
import MultipeerConnectivity
import Combine

/// 连接状态
enum FocusRoomConnectionState {
    case disconnected       // 未连接
    case advertising        // 正在广播（房主）
    case browsing           // 正在搜索
    case connecting         // 连接中
    case connected          // 已连接
}

@MainActor
final class FocusRoomService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = FocusRoomService()
    
    // MARK: - Published Properties
    
    @Published private(set) var currentRoom: FocusRoom?
    @Published private(set) var nearbyRooms: [DiscoveredRoom] = []
    @Published private(set) var connectionState: FocusRoomConnectionState = .disconnected
    @Published private(set) var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let serviceType = "porthole-focus"
    private var localPeerID: MCPeerID!
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private var myPeer: FocusPeer!
    private var statusSyncTimer: Timer?
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        setupLocalPeer()
        setupDisplayTimeTrackerObserver()
    }
    
    private func setupLocalPeer() {
        // 使用设备名作为 Peer ID
        let deviceName = UIDevice.current.name
        localPeerID = MCPeerID(displayName: deviceName)
        myPeer = FocusPeer(id: deviceName, displayName: deviceName)
        
        print("[FocusRoomService] Local peer: \(deviceName)")
    }
    
    private func setupDisplayTimeTrackerObserver() {
        // 监听 DisplayTimeTracker 的专注状态变化
        DisplayTimeTracker.shared.$isTracking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTracking in
                self?.handleFocusStateChanged(isFocusing: isTracking)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// 创建房间并开始广播
    func createRoom(name: String) {
        print("[FocusRoomService] Creating room: \(name)")
        
        // 清理旧连接
        leaveRoom()
        
        // 创建会话
        session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // 创建房间数据
        currentRoom = FocusRoom(
            name: name,
            hostPeerId: localPeerID.displayName,
            peers: [myPeer],
            isHost: true
        )
        
        // 开始广播
        let discoveryInfo: [String: String] = [
            "roomName": name,
            "hostName": myPeer.displayName
        ]
        advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        
        connectionState = .advertising
        startStatusSyncTimer()
        
        print("[FocusRoomService] Room created, advertising...")
    }
    
    /// 开始搜索附近房间
    func startBrowsing() {
        print("[FocusRoomService] Start browsing for rooms")
        
        // 如果已经在房间中，不搜索
        guard currentRoom == nil else {
            print("[FocusRoomService] Already in a room, skip browsing")
            return
        }
        
        stopBrowsing()
        nearbyRooms.removeAll()
        
        browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        
        connectionState = .browsing
    }
    
    /// 停止搜索
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        
        if connectionState == .browsing {
            connectionState = .disconnected
        }
    }
    
    /// 加入房间
    func joinRoom(_ room: DiscoveredRoom) {
        print("[FocusRoomService] Joining room: \(room.roomName)")
        
        // 创建会话
        session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // 创建房间数据（作为参与者）
        currentRoom = FocusRoom(
            name: room.roomName,
            hostPeerId: room.id,
            peers: [myPeer],
            isHost: false
        )
        
        connectionState = .connecting
        
        // 邀请房主连接
        if let browser = browser {
            // 需要从 browser 获取 peerID
            // 但这里无法直接获取，需要在 foundPeer 时保存
        }
        
        // 停止搜索
        stopBrowsing()
    }
    
    /// 离开房间
    func leaveRoom() {
        print("[FocusRoomService] Leaving room")
        
        stopStatusSyncTimer()
        
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        
        session?.disconnect()
        session?.delegate = nil
        session = nil
        
        currentRoom = nil
        nearbyRooms.removeAll()
        connectionState = .disconnected
    }
    
    /// 更新自己的专注状态
    func updateFocusState(isFocusing: Bool) {
        myPeer.isFocusing = isFocusing
        myPeer.focusStartTime = isFocusing ? Date() : nil
        
        // 更新房间中的自己
        currentRoom?.updatePeer(myPeer)
        
        // 广播状态
        broadcastStatus()
    }
    
    // MARK: - Private Methods
    
    private func handleFocusStateChanged(isFocusing: Bool) {
        guard currentRoom != nil else { return }
        
        myPeer.isFocusing = isFocusing
        if isFocusing {
            myPeer.focusStartTime = Date()
        } else {
            // 累加专注时长
            if let start = myPeer.focusStartTime {
                myPeer.totalFocusToday += Date().timeIntervalSince(start)
            }
            myPeer.focusStartTime = nil
        }
        
        currentRoom?.updatePeer(myPeer)
        broadcastStatus()
    }
    
    private func broadcastStatus() {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        let message = FocusStatusMessage(type: .statusUpdate, peer: myPeer)
        
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("[FocusRoomService] Broadcasted status to \(session.connectedPeers.count) peers")
        } catch {
            print("[FocusRoomService] Failed to broadcast: \(error)")
        }
    }
    
    private func startStatusSyncTimer() {
        stopStatusSyncTimer()
        
        // 每 5 秒同步一次状态
        statusSyncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.broadcastStatus()
            }
        }
        RunLoop.main.add(statusSyncTimer!, forMode: .common)
    }
    
    private func stopStatusSyncTimer() {
        statusSyncTimer?.invalidate()
        statusSyncTimer = nil
    }
    
    private func handleReceivedMessage(_ data: Data, from peerID: MCPeerID) {
        do {
            let message = try JSONDecoder().decode(FocusStatusMessage.self, from: data)
            
            Task { @MainActor in
                switch message.type {
                case .statusUpdate:
                    self.currentRoom?.updatePeer(message.peer)
                    print("[FocusRoomService] Updated peer status: \(message.peer.displayName), focusing: \(message.peer.isFocusing)")
                    
                case .syncRequest:
                    // 回复自己的状态
                    self.broadcastStatus()
                    
                case .syncResponse:
                    self.currentRoom?.updatePeer(message.peer)
                }
            }
        } catch {
            print("[FocusRoomService] Failed to decode message: \(error)")
        }
    }
}

// MARK: - MCSessionDelegate

extension FocusRoomService: MCSessionDelegate {
    
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            print("[FocusRoomService] Peer \(peerID.displayName) state: \(state.rawValue)")
            
            switch state {
            case .connected:
                self.connectionState = .connected
                // 添加新参与者
                let newPeer = FocusPeer(id: peerID.displayName, displayName: peerID.displayName)
                self.currentRoom?.updatePeer(newPeer)
                
                // 发送同步请求
                let message = FocusStatusMessage(type: .syncRequest, peer: self.myPeer)
                if let data = try? JSONEncoder().encode(message) {
                    try? session.send(data, toPeers: [peerID], with: .reliable)
                }
                
            case .notConnected:
                self.currentRoom?.removePeer(withId: peerID.displayName)
                if session.connectedPeers.isEmpty && self.currentRoom?.isHost == false {
                    // 作为参与者断开连接，退出房间
                    self.leaveRoom()
                }
                
            case .connecting:
                self.connectionState = .connecting
                
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.handleReceivedMessage(data, from: peerID)
        }
    }
    
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // 不使用流
    }
    
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // 不使用资源传输
    }
    
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // 不使用资源传输
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension FocusRoomService: MCNearbyServiceAdvertiserDelegate {
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            print("[FocusRoomService] Received invitation from: \(peerID.displayName)")
            // 自动接受邀请
            invitationHandler(true, self.session)
        }
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            print("[FocusRoomService] Failed to advertise: \(error)")
            self.errorMessage = "无法创建房间: \(error.localizedDescription)"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension FocusRoomService: MCNearbyServiceBrowserDelegate {
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            let roomName = info?["roomName"] ?? "未命名房间"
            let hostName = info?["hostName"] ?? peerID.displayName
            
            print("[FocusRoomService] Found room: \(roomName) by \(hostName)")
            
            let room = DiscoveredRoom(
                id: peerID.displayName,
                roomName: roomName,
                hostName: hostName,
                peerCount: 1
            )
            
            if !self.nearbyRooms.contains(room) {
                self.nearbyRooms.append(room)
            }
            
            // 如果正在尝试加入这个房间，发送邀请
            if self.currentRoom?.hostPeerId == peerID.displayName && self.connectionState == .connecting {
                browser.invitePeer(peerID, to: self.session!, withContext: nil, timeout: 30)
            }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("[FocusRoomService] Lost peer: \(peerID.displayName)")
            self.nearbyRooms.removeAll { $0.id == peerID.displayName }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            print("[FocusRoomService] Failed to browse: \(error)")
            self.errorMessage = "无法搜索房间: \(error.localizedDescription)"
        }
    }
}
