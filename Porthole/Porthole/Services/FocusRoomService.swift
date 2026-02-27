//
//  FocusRoomService.swift
//  Porthole
//
//  MultipeerConnectivity 专注房间服务
//  支持创建、加入、发现房间，同步专注状态，实时语音对讲
//

import Foundation
import MultipeerConnectivity
import AVFoundation
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
    @Published private(set) var isTalking: Bool = false
    @Published private(set) var activeSpeakers: Set<String> = []  // 正在说话的人
    
    // MARK: - Private Properties
    
    private let serviceType = "porthole-focus"
    private var localPeerID: MCPeerID!
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    private var myPeer: FocusPeer!
    private var statusSyncTimer: Timer?
    
    private var cancellables = Set<AnyCancellable>()
    
    // 保存发现的 peerID 用于加入房间
    private var discoveredPeers: [String: MCPeerID] = [:]
    
    // MARK: - Audio Properties
    
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var outputStreams: [String: OutputStream] = [:]
    private var inputStreams: [String: InputStream] = [:]
    private var isAudioConfigured = false
    
    // 使用 16kHz 单声道 Int16 格式，更紧凑且兼容性好
    private var recordingFormat: AVAudioFormat?
    private var playbackFormat: AVAudioFormat {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    }
    
    // 音频转换器
    private var audioConverter: AVAudioConverter?
    
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
        
        // 如果当前正在专注（PiP 已启动），更新自己的专注状态
        let isCurrentlyFocusing = DisplayTimeTracker.shared.isTracking
        myPeer.isFocusing = isCurrentlyFocusing
        if isCurrentlyFocusing {
            myPeer.focusStartTime = Date()
        }
        
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
        configureAudioSession()
        
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
        discoveredPeers.removeAll()
        
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
        
        guard let hostPeerID = discoveredPeers[room.id] else {
            print("[FocusRoomService] Host peer not found, start browsing again")
            startBrowsing()
            return
        }
        
        // 创建会话
        session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // 如果当前正在专注（PiP 已启动），更新自己的专注状态
        let isCurrentlyFocusing = DisplayTimeTracker.shared.isTracking
        myPeer.isFocusing = isCurrentlyFocusing
        if isCurrentlyFocusing {
            myPeer.focusStartTime = Date()
        }
        
        // 创建房间数据（作为参与者）
        currentRoom = FocusRoom(
            name: room.roomName,
            hostPeerId: room.id,
            peers: [myPeer],
            isHost: false
        )
        
        connectionState = .connecting
        
        // 发送邀请请求
        browser?.invitePeer(hostPeerID, to: session!, withContext: nil, timeout: 30)
        
        // 停止搜索
        stopBrowsing()
        
        configureAudioSession()
        startStatusSyncTimer()
    }
    
    /// 离开房间
    func leaveRoom() {
        print("[FocusRoomService] Leaving room")
        
        stopTalking()
        stopStatusSyncTimer()
        stopAudioEngine()
        
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        
        // 关闭所有流
        for (_, stream) in outputStreams {
            stream.close()
        }
        outputStreams.removeAll()
        
        for (_, stream) in inputStreams {
            stream.close()
        }
        inputStreams.removeAll()
        
        session?.disconnect()
        session?.delegate = nil
        session = nil
        
        currentRoom = nil
        nearbyRooms.removeAll()
        discoveredPeers.removeAll()
        connectionState = .disconnected
        activeSpeakers.removeAll()
    }
    
    /// 更新自己的专注状态
    func updateFocusState(isFocusing: Bool) {
        myPeer.isFocusing = isFocusing
        myPeer.focusStartTime = isFocusing ? Date() : nil
        
        // 更新房间中的自己
        updatePeerInRoom(myPeer)
        
        // 广播状态
        broadcastStatus()
    }
    
    /// 是否在房间中
    var isInRoom: Bool {
        currentRoom != nil
    }
    
    /// 自己的 Peer ID
    var myPeerId: String {
        myPeer.id
    }
    
    /// 是否可以说话（有其他人连接时才能说话）
    var canTalk: Bool {
        guard currentRoom != nil, let session = session else { return false }
        return !session.connectedPeers.isEmpty
    }
    
    // MARK: - Room Update Helpers
    
    /// 更新房间中的参与者（触发 @Published 更新）
    private func updatePeerInRoom(_ peer: FocusPeer) {
        guard var room = currentRoom else { return }
        room.updatePeer(peer)
        currentRoom = room
        print("[FocusRoomService] Updated peer in room: \(peer.displayName), total peers: \(room.peers.count)")
    }
    
    /// 从房间中移除参与者（触发 @Published 更新）
    private func removePeerFromRoom(withId id: String) {
        guard var room = currentRoom else { return }
        room.removePeer(withId: id)
        currentRoom = room
        print("[FocusRoomService] Removed peer from room: \(id), remaining peers: \(room.peers.count)")
    }
    
    // MARK: - Voice Chat
    
    /// 开始说话（按住说话）
    func startTalking() {
        guard currentRoom != nil, let session = session, !session.connectedPeers.isEmpty else {
            print("[FocusRoomService] Cannot talk: not in room or no peers")
            return
        }
        
        guard !isTalking else { return }
        
        print("[FocusRoomService] Start talking")
        isTalking = true
        
        // 配置音频会话
        configureAudioSession()
        
        // 向所有连接的 peer 开启音频流
        for peer in session.connectedPeers {
            startAudioStream(to: peer)
        }
        
        // 开始录音
        startRecording()
        
        // 广播说话状态
        broadcastTalkingState(isTalking: true)
    }
    
    /// 停止说话
    func stopTalking() {
        guard isTalking else { return }
        
        print("[FocusRoomService] Stop talking")
        isTalking = false
        
        // 停止录音
        stopRecording()
        
        // 关闭输出流
        for (peerId, stream) in outputStreams {
            stream.close()
            print("[FocusRoomService] Closed output stream to \(peerId)")
        }
        outputStreams.removeAll()
        
        // 广播说话状态
        broadcastTalkingState(isTalking: false)
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
        
        updatePeerInRoom(myPeer)
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
    
    private func broadcastTalkingState(isTalking: Bool) {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        var peer = myPeer!
        peer.isTalking = isTalking
        let message = FocusStatusMessage(type: .talkingState, peer: peer)
        
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("[FocusRoomService] Failed to broadcast talking state: \(error)")
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
                    self.updatePeerInRoom(message.peer)
                    print("[FocusRoomService] Updated peer status: \(message.peer.displayName), focusing: \(message.peer.isFocusing)")
                    
                case .syncRequest:
                    // 回复自己的状态
                    self.broadcastStatus()
                    
                case .syncResponse:
                    self.updatePeerInRoom(message.peer)
                    
                case .talkingState:
                    if message.peer.isTalking {
                        self.activeSpeakers.insert(message.peer.id)
                    } else {
                        self.activeSpeakers.remove(message.peer.id)
                    }
                    self.updatePeerInRoom(message.peer)
                }
            }
        } catch {
            print("[FocusRoomService] Failed to decode message: \(error)")
        }
    }
    
    // MARK: - Audio Configuration
    
    private func configureAudioSession() {
        guard !isAudioConfigured else { return }
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            isAudioConfigured = true
            print("[FocusRoomService] Audio session configured for voice chat")
        } catch {
            print("[FocusRoomService] Failed to configure audio session: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        guard audioEngine == nil else { return }
        
        let engine = AVAudioEngine()
        audioEngine = engine
        
        // 设置播放节点
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
        audioPlayerNode = playerNode
        
        print("[FocusRoomService] Audio engine created")
    }
    
    private func stopAudioEngine() {
        if let engine = audioEngine {
            engine.stop()
            if let playerNode = audioPlayerNode {
                engine.detach(playerNode)
            }
        }
        audioEngine = nil
        audioPlayerNode = nil
        audioConverter = nil
        recordingFormat = nil
        isAudioConfigured = false
    }
    
    private func startAudioStream(to peer: MCPeerID) {
        guard let session = session else { return }
        
        do {
            let stream = try session.startStream(withName: "audio", toPeer: peer)
            stream.schedule(in: .main, forMode: .common)
            stream.open()
            outputStreams[peer.displayName] = stream
            print("[FocusRoomService] Started audio stream to \(peer.displayName)")
        } catch {
            print("[FocusRoomService] Failed to start audio stream: \(error)")
        }
    }
    
    private func startRecording() {
        setupAudioEngine()
        guard let engine = audioEngine else { return }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        recordingFormat = inputFormat
        
        print("[FocusRoomService] Input format: \(inputFormat)")
        
        // 创建格式转换器（从输入格式转换到 16kHz mono）
        if inputFormat.sampleRate != playbackFormat.sampleRate || inputFormat.channelCount != playbackFormat.channelCount {
            audioConverter = AVAudioConverter(from: inputFormat, to: playbackFormat)
            print("[FocusRoomService] Audio converter created: \(inputFormat.sampleRate)Hz -> \(playbackFormat.sampleRate)Hz")
        }
        
        // 使用较大的缓冲区减少回调频率
        // 注意：音频回调在后台线程，需要捕获必要的变量
        let converter = audioConverter
        let format = playbackFormat
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            // 在后台线程处理音频
            self?.processAndSendAudioBufferSync(buffer, converter: converter, targetFormat: format)
        }
        
        do {
            try engine.start()
            print("[FocusRoomService] Recording started")
        } catch {
            print("[FocusRoomService] Failed to start audio engine: \(error)")
        }
    }
    
    private func stopRecording() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioConverter = nil
        print("[FocusRoomService] Recording stopped")
    }
    
    /// 在后台线程处理和发送音频（nonisolated 以避免 actor 隔离问题）
    nonisolated private func processAndSendAudioBufferSync(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat) {
        var bufferToSend: AVAudioPCMBuffer = buffer
        
        // 如果需要格式转换
        if let converter = converter {
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
                return
            }
            
            var error: NSError?
            var hasData = true
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if hasData {
                    hasData = false
                    outStatus.pointee = .haveData
                    return buffer
                } else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                print("[FocusRoomService] Audio conversion error: \(error)")
                return
            }
            
            bufferToSend = convertedBuffer
        }
        
        // 将 Float32 PCM 数据转换为 Int16 以减少带宽
        guard let channelData = bufferToSend.floatChannelData else { return }
        
        let frameLength = Int(bufferToSend.frameLength)
        guard frameLength > 0 else { return }
        
        var int16Data = [Int16](repeating: 0, count: frameLength)
        
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            // 将 Float [-1, 1] 转换为 Int16 [-32768, 32767]
            int16Data[i] = Int16(max(-32768, min(32767, sample * 32767)))
        }
        
        let data = Data(bytes: int16Data, count: frameLength * MemoryLayout<Int16>.size)
        
        // 需要在主线程访问 outputStreams
        Task { @MainActor [weak self] in
            self?.sendAudioData(data)
        }
    }
    
    private func sendAudioData(_ data: Data) {
        for (peerId, stream) in outputStreams {
            if stream.hasSpaceAvailable {
                data.withUnsafeBytes { bytes in
                    if let baseAddress = bytes.baseAddress {
                        let written = stream.write(baseAddress.assumingMemoryBound(to: UInt8.self), maxLength: data.count)
                        if written < 0 {
                            print("[FocusRoomService] Failed to write to stream for \(peerId)")
                        }
                    }
                }
            }
        }
    }
    
    private func handleIncomingAudioStream(_ stream: InputStream, from peerID: MCPeerID) {
        print("[FocusRoomService] Receiving audio stream from \(peerID.displayName)")
        
        inputStreams[peerID.displayName] = stream
        stream.delegate = self
        stream.schedule(in: .main, forMode: .common)
        stream.open()
        
        // 确保音频引擎已启动
        setupAudioEngine()
        guard let engine = audioEngine, let playerNode = audioPlayerNode else { return }
        
        if !engine.isRunning {
            do {
                try engine.start()
                playerNode.play()
                print("[FocusRoomService] Audio engine started for playback")
            } catch {
                print("[FocusRoomService] Failed to start audio engine for playback: \(error)")
            }
        }
    }
}

// MARK: - StreamDelegate

extension FocusRoomService: StreamDelegate {
    nonisolated func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        guard let inputStream = aStream as? InputStream else { return }
        
        switch eventCode {
        case .hasBytesAvailable:
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
            
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                Task { @MainActor in
                    self.playReceivedAudio(data)
                }
            }
            
        case .endEncountered:
            Task { @MainActor in
                // 找到对应的 peer 并清理
                for (peerId, stream) in self.inputStreams {
                    if stream === inputStream {
                        self.inputStreams.removeValue(forKey: peerId)
                        self.activeSpeakers.remove(peerId)
                        break
                    }
                }
            }
            inputStream.close()
            
        case .errorOccurred:
            print("[FocusRoomService] Stream error")
            inputStream.close()
            
        default:
            break
        }
    }
    
    private func playReceivedAudio(_ data: Data) {
        guard let engine = audioEngine, engine.isRunning,
              let playerNode = audioPlayerNode else { return }
        
        // 将 Int16 数据转换回 Float32
        let frameCount = data.count / MemoryLayout<Int16>.size
        guard frameCount > 0 else { return }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        data.withUnsafeBytes { bytes in
            guard let int16Pointer = bytes.baseAddress?.assumingMemoryBound(to: Int16.self),
                  let channelData = buffer.floatChannelData else { return }
            
            for i in 0..<frameCount {
                // 将 Int16 [-32768, 32767] 转换回 Float [-1, 1]
                channelData[0][i] = Float(int16Pointer[i]) / 32767.0
            }
        }
        
        // 播放音频
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
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
                self.updatePeerInRoom(newPeer)
                
                // 发送同步请求
                let message = FocusStatusMessage(type: .syncRequest, peer: self.myPeer)
                if let data = try? JSONEncoder().encode(message) {
                    try? session.send(data, toPeers: [peerID], with: .reliable)
                }
                
            case .notConnected:
                self.removePeerFromRoom(withId: peerID.displayName)
                self.activeSpeakers.remove(peerID.displayName)
                
                // 清理音频资源
                self.outputStreams[peerID.displayName]?.close()
                self.outputStreams.removeValue(forKey: peerID.displayName)
                self.inputStreams[peerID.displayName]?.close()
                self.inputStreams.removeValue(forKey: peerID.displayName)
                
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
        if streamName == "audio" {
            Task { @MainActor in
                self.handleIncomingAudioStream(stream, from: peerID)
            }
        }
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
            
            // 保存 peerID 用于后续加入
            self.discoveredPeers[peerID.displayName] = peerID
            
            let room = DiscoveredRoom(
                id: peerID.displayName,
                roomName: roomName,
                hostName: hostName,
                peerCount: 1
            )
            
            if !self.nearbyRooms.contains(room) {
                self.nearbyRooms.append(room)
            }
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            print("[FocusRoomService] Lost peer: \(peerID.displayName)")
            self.nearbyRooms.removeAll { $0.id == peerID.displayName }
            self.discoveredPeers.removeValue(forKey: peerID.displayName)
        }
    }
    
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            print("[FocusRoomService] Failed to browse: \(error)")
            self.errorMessage = "无法搜索房间: \(error.localizedDescription)"
        }
    }
}
