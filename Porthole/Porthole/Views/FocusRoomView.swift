//
//  FocusRoomView.swift
//  Porthole
//
//  专注房间管理界面
//  支持创建房间、发现并加入附近房间
//

import SwiftUI

struct FocusRoomView: View {
    @StateObject private var roomService = FocusRoomService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var roomName: String = ""
    @State private var showCreateRoom = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景
                Color(red: 250/255, green: 247/255, blue: 240/255)
                    .ignoresSafeArea()
                
                if let room = roomService.currentRoom {
                    // 已在房间中
                    roomContentView(room)
                } else {
                    // 未加入房间
                    lobbyView
                }
            }
            .navigationTitle(roomService.currentRoom?.name ?? "专注房间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                if roomService.currentRoom != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("退出") {
                            roomService.leaveRoom()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .onAppear {
                if roomService.currentRoom == nil {
                    roomService.startBrowsing()
                }
            }
            .onDisappear {
                roomService.stopBrowsing()
            }
            .sheet(isPresented: $showCreateRoom) {
                createRoomSheet
            }
        }
    }
    
    // MARK: - Lobby View (未加入房间)
    
    private var lobbyView: some View {
        VStack(spacing: 24) {
            // 创建房间按钮
            Button {
                showCreateRoom = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                    Text("创建房间")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.black.opacity(0.8))
                .cornerRadius(14)
            }
            .padding(.horizontal, 20)
            
            // 附近房间列表
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("附近的房间")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.black.opacity(0.4))
                    
                    Spacer()
                    
                    if roomService.connectionState == .browsing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 20)
                
                if roomService.nearbyRooms.isEmpty {
                    emptyRoomsView
                } else {
                    nearbyRoomsList
                }
            }
            
            Spacer()
        }
        .padding(.top, 20)
    }
    
    private var emptyRoomsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.black.opacity(0.15))
            
            Text("正在搜索附近的房间...")
                .font(.system(size: 14))
                .foregroundStyle(.black.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private var nearbyRoomsList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(roomService.nearbyRooms) { room in
                    nearbyRoomRow(room)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func nearbyRoomRow(_ room: DiscoveredRoom) -> some View {
        Button {
            roomService.joinRoom(room)
        } label: {
            HStack(spacing: 14) {
                // 房间图标
                Circle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.black.opacity(0.5))
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(room.roomName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.8))
                    
                    Text("由 \(room.hostName) 创建")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.4))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black.opacity(0.3))
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Room Content View (已在房间中)
    
    private func roomContentView(_ room: FocusRoom) -> some View {
        VStack(spacing: 20) {
            // 房间状态
            VStack(spacing: 8) {
                Text(room.isHost ? "你创建了这个房间" : "你已加入房间")
                    .font(.system(size: 13))
                    .foregroundStyle(.black.opacity(0.4))
                
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 14))
                    Text("\(room.peers.count) 人")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.black.opacity(0.6))
            }
            .padding(.top, 10)
            
            // 参与者列表
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(room.peers) { peer in
                        peerRow(peer)
                    }
                }
                .padding(.horizontal, 20)
            }
            
            Spacer()
            
            // 提示
            Text("上滑启动 PiP 开始专注")
                .font(.system(size: 13))
                .foregroundStyle(.black.opacity(0.35))
                .padding(.bottom, 20)
        }
    }
    
    private func peerRow(_ peer: FocusPeer) -> some View {
        HStack(spacing: 14) {
            // 头像
            Circle()
                .fill(peer.isFocusing ? Color.green.opacity(0.2) : Color.black.opacity(0.08))
                .frame(width: 48, height: 48)
                .overlay {
                    Text(String(peer.displayName.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(peer.isFocusing ? .green : .black.opacity(0.4))
                }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(peer.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black.opacity(0.8))
                    
                    if peer.id == FocusRoomService.shared.currentRoom?.hostPeerId {
                        Text("房主")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(peer.isFocusing ? Color.green : Color.black.opacity(0.2))
                        .frame(width: 6, height: 6)
                    
                    Text(peer.isFocusing ? "专注中 · \(formatDuration(peer.currentFocusDuration))" : "空闲")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.4))
                }
            }
            
            Spacer()
            
            // 今日时长
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDuration(peer.totalFocusDurationToday))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.6))
                
                Text("今日")
                    .font(.system(size: 10))
                    .foregroundStyle(.black.opacity(0.3))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
    
    // MARK: - Create Room Sheet
    
    private var createRoomSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("房间名称")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    TextField("输入房间名称", text: $roomName)
                        .font(.system(size: 17))
                        .padding(14)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(10)
                }
                .padding(.horizontal, 20)
                
                Button {
                    let name = roomName.isEmpty ? "\(UIDevice.current.name) 的房间" : roomName
                    roomService.createRoom(name: name)
                    showCreateRoom = false
                } label: {
                    Text("创建")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(12)
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("创建房间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        showCreateRoom = false
                    }
                }
            }
        }
        .presentationDetents([.height(250)])
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    FocusRoomView()
}
