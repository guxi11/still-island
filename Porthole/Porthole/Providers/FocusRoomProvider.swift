//
//  FocusRoomProvider.swift
//  Porthole
//
//  专注房间 PiP 内容提供者
//  在 PiP 窗口中显示房间成员的专注状态
//

import UIKit
import Combine

@MainActor
final class FocusRoomProvider: PiPContentProvider {
    
    // MARK: - PiPContentProvider Static Properties
    
    static let providerType: String = "focusRoom"
    static let displayName: String = "专注房间"
    static let iconName: String = "person.2.fill"
    
    // MARK: - PiPContentProvider
    
    let contentView: UIView
    let preferredFrameRate: Int = 1
    
    // MARK: - Private Properties
    
    private let containerView: UIView
    private let roomNameLabel: UILabel
    private let peersStackView: UIStackView
    private let statusLabel: UILabel
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        let containerSize = CGSize(width: 200, height: 100)
        
        // Container
        containerView = UIView(frame: CGRect(origin: .zero, size: containerSize))
        containerView.backgroundColor = UIColor.black
        
        // Room name label
        roomNameLabel = UILabel()
        roomNameLabel.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        roomNameLabel.textColor = .white.withAlphaComponent(0.5)
        roomNameLabel.textAlignment = .left
        roomNameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Peers stack view (horizontal)
        peersStackView = UIStackView()
        peersStackView.axis = .horizontal
        peersStackView.spacing = 8
        peersStackView.alignment = .center
        peersStackView.distribution = .fill
        peersStackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Status label (显示专注人数)
        statusLabel = UILabel()
        statusLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(roomNameLabel)
        containerView.addSubview(peersStackView)
        containerView.addSubview(statusLabel)
        
        NSLayoutConstraint.activate([
            // Room name at top left
            roomNameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            roomNameLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            roomNameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            
            // Status in center
            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            
            // Peers at bottom
            peersStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            peersStackView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            peersStackView.heightAnchor.constraint(equalToConstant: 24)
        ])
        
        self.contentView = containerView
        
        containerView.setNeedsLayout()
        containerView.layoutIfNeeded()
    }
    
    // MARK: - PiPContentProvider Methods
    
    func start() {
        print("[FocusRoomProvider] start()")
        
        // 初始更新
        updateUI()
        
        // 订阅房间变化
        setupRoomObserver()
        
        // 定时更新 UI（更新专注时长显示）
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateUI()
            }
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    func stop() {
        print("[FocusRoomProvider] stop()")
        timer?.invalidate()
        timer = nil
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func setupRoomObserver() {
        // 订阅 FocusRoomService 的所有变化
        FocusRoomService.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // 延迟一帧确保值已更新
                DispatchQueue.main.async {
                    self?.updateUI()
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateUI() {
        let room = FocusRoomService.shared.currentRoom
        print("[FocusRoomProvider] updateUI called, room: \(room?.name ?? "nil"), peers: \(room?.peers.count ?? 0)")
        
        guard let room = room else {
            roomNameLabel.text = "专注房间"
            statusLabel.text = "暂未加入房间"
            statusLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
            clearPeerViews()
            return
        }
        
        // 恢复状态标签字体
        statusLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 24, weight: .bold)
        
        // 房间名称
        roomNameLabel.text = room.name
        
        // 专注状态
        let focusingCount = room.focusingCount
        let totalCount = room.peers.count
        statusLabel.text = "\(focusingCount)/\(totalCount) 专注中"
        
        // 更新参与者头像
        updatePeerViews(room.peers)
        
        contentView.setNeedsDisplay()
    }
    
    private func clearPeerViews() {
        peersStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }
    
    private func updatePeerViews(_ peers: [FocusPeer]) {
        clearPeerViews()
        
        // 最多显示 5 个头像
        let displayPeers = Array(peers.prefix(5))
        
        for peer in displayPeers {
            let avatarView = createAvatarView(for: peer)
            peersStackView.addArrangedSubview(avatarView)
        }
        
        // 如果超过 5 个，显示 +N
        if peers.count > 5 {
            let moreLabel = UILabel()
            moreLabel.text = "+\(peers.count - 5)"
            moreLabel.font = UIFont.systemFont(ofSize: 10, weight: .medium)
            moreLabel.textColor = .white.withAlphaComponent(0.5)
            peersStackView.addArrangedSubview(moreLabel)
        }
    }
    
    private func createAvatarView(for peer: FocusPeer) -> UIView {
        let size: CGFloat = 24
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        view.layer.cornerRadius = size / 2
        view.backgroundColor = peer.isFocusing
            ? UIColor.systemGreen.withAlphaComponent(0.3)
            : UIColor.white.withAlphaComponent(0.15)
        
        // 首字母
        let label = UILabel()
        label.text = String(peer.displayName.prefix(1)).uppercased()
        label.font = UIFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = peer.isFocusing ? .systemGreen : .white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        // 专注中的绿色边框
        if peer.isFocusing {
            view.layer.borderWidth = 1.5
            view.layer.borderColor = UIColor.systemGreen.cgColor
        }
        
        return view
    }
}
