//
//  SharedCameraSetupView.swift
//  Porthole
//
//  UI for setting up and managing shared camera rooms.
//

import SwiftUI
import MultipeerConnectivity

// MARK: - Shared Camera Setup View

struct SharedCameraSetupView: View {
    @StateObject private var viewModel: SharedCameraSetupViewModel
    @Environment(\.dismiss) private var dismiss
    
    let provider: SharedCameraProvider
    let onStartPiP: () -> Void
    
    init(provider: SharedCameraProvider, onStartPiP: @escaping () -> Void) {
        self.provider = provider
        self.onStartPiP = onStartPiP
        self._viewModel = StateObject(wrappedValue: SharedCameraSetupViewModel(provider: provider))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                headerSection
                
                // Room state dependent content
                switch viewModel.roomState {
                case .idle:
                    idleContent
                case .creating:
                    connectingContent(message: "正在创建房间...")
                case .joining:
                    connectingContent(message: "正在搜索房间...")
                case .connected:
                    connectedContent
                case .disconnected(let reason):
                    disconnectedContent(reason: reason)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("实景共享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            Text("与附近的设备共享摄像头画面")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Idle Content
    
    private var idleContent: some View {
        VStack(spacing: 16) {
            // Create Room
            VStack(spacing: 12) {
                Text("创建房间")
                    .font(.headline)
                
                TextField("房间名称", text: $viewModel.roomName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                
                Button(action: {
                    viewModel.createRoom()
                }) {
                    Label("创建并共享", systemImage: "plus.circle.fill")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.roomName.isEmpty)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            
            Text("或者")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Join Room
            VStack(spacing: 12) {
                Text("加入房间")
                    .font(.headline)
                
                Text("搜索附近正在共享的设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button(action: {
                    viewModel.joinRoom()
                }) {
                    Label("搜索并加入", systemImage: "magnifyingglass")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Connecting Content
    
    private func connectingContent(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(message)
                .font(.headline)
            
            Button("取消") {
                viewModel.leaveRoom()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    // MARK: - Connected Content
    
    private var connectedContent: some View {
        VStack(spacing: 20) {
            // Room info
            VStack(spacing: 8) {
                Text(viewModel.currentRoomName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("\(viewModel.participants.count) 位参与者")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Participants list
            participantsList
            
            // Display mode selector
            displayModeSelector
            
            // Actions
            VStack(spacing: 12) {
                Button(action: {
                    onStartPiP()
                    dismiss()
                }) {
                    Label("开始画中画", systemImage: "pip.enter")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: {
                    viewModel.leaveRoom()
                }) {
                    Label("离开房间", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Participants List
    
    private var participantsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("参与者")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(viewModel.participants) { participant in
                        ParticipantRow(
                            participant: participant,
                            isSelected: participant.id == viewModel.selectedPeerId,
                            isLocal: participant.id == viewModel.localPeerId
                        ) {
                            viewModel.selectPeer(participant.id)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 150)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Display Mode Selector
    
    private var displayModeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("显示模式")
                .font(.headline)
            
            HStack(spacing: 12) {
                ForEach(SharedDisplayMode.allCases) { mode in
                    DisplayModeButton(
                        mode: mode,
                        isSelected: viewModel.displayMode == mode
                    ) {
                        viewModel.setDisplayMode(mode)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Disconnected Content
    
    private func disconnectedContent(reason: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            
            Text("连接已断开")
                .font(.headline)
            
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button("重新连接") {
                viewModel.resetState()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Participant Row

struct ParticipantRow: View {
    let participant: RoomParticipant
    let isSelected: Bool
    let isLocal: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                // Avatar
                Circle()
                    .fill(isLocal ? Color.blue : Color.gray)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Image(systemName: isLocal ? "person.fill" : "person.wave.2.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
                
                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(participant.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if isLocal {
                            Text("(我)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if participant.isHost {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(participant.isConnected ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)
                        
                        Text(participant.isSharingCamera ? "正在共享" : "未共享")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected && !isLocal {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(isLocal)
    }
}

// MARK: - Display Mode Button

struct DisplayModeButton: View {
    let mode: SharedDisplayMode
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: mode.iconName)
                    .font(.title2)
                
                Text(mode.displayName)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .blue : .primary)
    }
}

// MARK: - View Model

@MainActor
class SharedCameraSetupViewModel: ObservableObject {
    
    @Published var roomName: String = ""
    @Published var roomState: RoomState = .idle
    @Published var participants: [RoomParticipant] = []
    @Published var displayMode: SharedDisplayMode = .sideBySide
    @Published var selectedPeerId: String?
    
    var currentRoomName: String {
        if case .connected(let name) = roomState {
            return name
        }
        return roomName
    }
    
    var localPeerId: String {
        provider.multipeerService.localPeerId
    }
    
    private let provider: SharedCameraProvider
    
    init(provider: SharedCameraProvider) {
        self.provider = provider
        
        // Initial state
        self.roomState = provider.multipeerService.state
        self.participants = provider.multipeerService.participants
        self.displayMode = provider.displayMode
        self.selectedPeerId = provider.multipeerService.selectedRemotePeerId
        
        // Generate default room name
        self.roomName = "\(UIDevice.current.name)的房间"
        
        // Observe changes
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe multipeer service state
        // Note: In a real app, you'd use Combine publishers or proper bindings
        // For simplicity, we'll manually update in actions
    }
    
    func createRoom() {
        provider.createRoom(name: roomName)
        updateState()
    }
    
    func joinRoom() {
        provider.joinRoom()
        updateState()
    }
    
    func leaveRoom() {
        provider.leaveRoom()
        updateState()
    }
    
    func selectPeer(_ peerId: String) {
        selectedPeerId = peerId
        provider.multipeerService.selectedRemotePeerId = peerId
    }
    
    func setDisplayMode(_ mode: SharedDisplayMode) {
        displayMode = mode
        provider.displayMode = mode
    }
    
    func resetState() {
        roomState = .idle
    }
    
    func updateState() {
        roomState = provider.multipeerService.state
        participants = provider.multipeerService.participants
        selectedPeerId = provider.multipeerService.selectedRemotePeerId
    }
}

// MARK: - Preview

#Preview {
    SharedCameraSetupView(
        provider: SharedCameraProvider(),
        onStartPiP: {}
    )
}
