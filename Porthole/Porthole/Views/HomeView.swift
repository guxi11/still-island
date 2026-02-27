//
//  HomeView.swift
//  Porthole
//
//  New interaction design:
//  - Center: Card carousel (swipe left/right to switch, showing adjacent card edges)
//  - Swipe up: Start PiP, show statistics summary
//  - Swipe down: Show edit panel (delete, change video, add card)
//  - Swipe down (when PiP active): Close PiP
//

import SwiftUI
import AVKit

struct HomeView: View {
    @StateObject private var pipManager = PiPManager.shared
    @StateObject private var cardManager = CardManager.shared
    @StateObject private var tracker = DisplayTimeTracker.shared
    
    // Current card index
    @State private var currentCardIndex: Int = 0
    
    // Drag state
    @State private var dragOffset: CGSize = .zero
    @State private var dragDirection: DragDirection? = nil
    
    // 卡片滑动状态
    enum CardSwipeState {
        case idle           // 初始状态
        case swipingUp      // 正在上滑
        case swipingDown    // 正在下滑（编辑面板）
    }
    @State private var cardSwipeState: CardSwipeState = .idle
    
    // PiP host view state
    @State private var currentProvider: PiPContentProvider?
    @State private var pipViewId = UUID()
    
    // Edit panel state
    @State private var showEditPanel = false
    @State private var editPanelOffset: CGFloat = 0
    
    // Sheet states
    @State private var showAddCard = false
    @State private var showVideoPicker = false
    @State private var editingCardId: UUID?
    @State private var showStatistics = false
    @State private var showPrivacyPolicy = false
    @State private var showFocusRoom = false
    
    // Warm cream/milk white background
    private let backgroundColor = Color(red: 250/255, green: 247/255, blue: 240/255)
    
    enum DragDirection {
        case horizontal
        case vertical
    }
    
    // Current card
    private var currentCard: CardInstance? {
        guard !cardManager.cards.isEmpty,
              currentCardIndex >= 0,
              currentCardIndex < cardManager.cards.count else {
            return nil
        }
        return cardManager.cards[currentCardIndex]
    }
    
    var body: some View {
        GeometryReader { geometry in
            let screenSize = geometry.size
            let safeArea = geometry.safeAreaInsets
            
            // 计算卡片位置
            let cardWidth: CGFloat = 260
            let cardHeight: CGFloat = 150
            let cardSpacing: CGFloat = 28
            let miniScale: CGFloat = 0.25
            
            // 中心位置
            let centerX = screenSize.width / 2
            let centerY = screenSize.height / 2 - 20
            
            // 左上角位置（缩小后的卡片中心点）- 更靠近角落
            let cornerX: CGFloat = 30 + (cardWidth * miniScale) / 2
            let cornerY: CGFloat = 16 + (cardHeight * miniScale) / 2
            
            // 是否在角落（只有在非上滑手势过程中才生效）
            let inCorner = (pipManager.isPiPActive || pipManager.isPreparingPiP) && cardSwipeState != .swipingUp
            
            ZStack {
                // Background
                backgroundColor
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture(minimumDistance: 20)
                            .onChanged { value in
                                handleDragChanged(value, screenSize: screenSize)
                            }
                            .onEnded { value in
                                handleDragEnded(value, screenSize: screenSize)
                            }
                    )
                
                // 所有卡片 - 统一渲染，通过位置变化实现动画
                if !cardManager.cards.isEmpty {
                    ForEach(Array(cardManager.cards.enumerated()), id: \.element.id) { index, card in
                        let isCurrent = index == currentCardIndex
                        
                        // 计算位置
                        let baseOffset = CGFloat(index - currentCardIndex) * (cardWidth + cardSpacing)
                        
                        // 当前卡片的目标位置和缩放
                        let targetX: CGFloat = {
                            if isCurrent && inCorner {
                                // 在角落时，支持下滑拖动
                                if dragOffset.height > 0 {
                                    let progress = min(dragOffset.height / 200, 1.0)
                                    return cornerX + (centerX - cornerX) * progress
                                }
                                return cornerX
                            }
                            // 上滑时跟手移动到角落
                            if isCurrent && dragOffset.height < 0 {
                                let progress = min(abs(dragOffset.height) / 150, 1.0)
                                return centerX + (cornerX - centerX) * progress
                            }
                            return centerX + baseOffset + dragOffset.width
                        }()
                        
                        let targetY: CGFloat = {
                            if isCurrent && inCorner {
                                // 在角落时，支持下滑拖动
                                if dragOffset.height > 0 {
                                    let progress = min(dragOffset.height / 200, 1.0)
                                    return cornerY + (centerY - cornerY) * progress
                                }
                                return cornerY
                            }
                            // 上滑时跟手移动到角落
                            if isCurrent && dragOffset.height < 0 {
                                let progress = min(abs(dragOffset.height) / 150, 1.0)
                                return centerY + (cornerY - centerY) * progress
                            }
                            // 普通状态下滑显示编辑面板
                            if isCurrent && dragOffset.height > 0 {
                                return centerY + min(dragOffset.height * 0.3, 50)
                            }
                            return centerY
                        }()
                        
                        let targetScale: CGFloat = {
                            if isCurrent && inCorner {
                                if dragOffset.height > 0 {
                                    let progress = min(dragOffset.height / 200, 1.0)
                                    return miniScale + (1.0 - miniScale) * progress
                                }
                                return miniScale
                            }
                            // 上滑时跟手缩小
                            if isCurrent && dragOffset.height < 0 {
                                let progress = min(abs(dragOffset.height) / 150, 1.0)
                                return 1.0 - (1.0 - miniScale) * progress
                            }
                            return isCurrent ? 1.0 : 0.85
                        }()
                        
                        let targetOpacity: Double = {
                            if inCorner {
                                if !isCurrent { return 0 }
                                if pipManager.isPiPActive && !pipManager.isPreparingPiP && dragOffset.height == 0 {
                                    return 0.15
                                }
                                return 1.0
                            }
                            if abs(index - currentCardIndex) > 2 { return 0 }
                            return isCurrent ? 1.0 : 0.55
                        }()
                        
                        CardItemView(
                            card: card,
                            cardWidth: cardWidth,
                            cardHeight: cardHeight,
                            isCurrentCard: isCurrent,
                            isPiPActive: pipManager.isPiPActive && isCurrent,
                            isPreparing: pipManager.isPreparingPiP && isCurrent
                        )
                        .scaleEffect(targetScale)
                        .position(x: targetX, y: targetY)
                        .opacity(targetOpacity)
                        .zIndex(isCurrent ? 10 : Double(cardManager.cards.count - abs(index - currentCardIndex)))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: inCorner)
                        .animation(.interpolatingSpring(stiffness: 300, damping: 30), value: currentCardIndex)
                    }
                }
                
                // PiP host view - 放在卡片飞行终点位置
                if (pipManager.isPreparingPiP || pipManager.isPiPActive), let layer = pipManager.displayLayer {
                    PiPHostView(
                        displayLayer: layer,
                        onViewCreated: { view in
                            pipManager.bindToViewLayer(view)
                        }
                    )
                    .frame(width: cardWidth * miniScale, height: cardHeight * miniScale)
                    .position(x: cornerX, y: cornerY)
                    .opacity(0.01)
                }
                
                // Empty state
                if cardManager.cards.isEmpty {
                    emptyStateView
                }
                
                // 计算上滑进度（用于统计数据和提示的动画）
                let swipeUpProgress: CGFloat = {
                    // 已经在角落或正在准备：显示完整统计数据
                    // if inCorner || pipManager.isPreparingPiP {
                    if inCorner {
                        return 1.0
                    }
                    // 上滑手势中：跟随手势进度
                    if dragOffset.height < 0 && cardSwipeState == .swipingUp {
                        return min(abs(dragOffset.height) / 150, 1.0)
                    }
                    return 0
                }()
                
                // 下滑进度（PiP 激活时）
                let swipeDownProgress: CGFloat = {
                    if inCorner && dragOffset.height > 0 {
                        return min(dragOffset.height / 200, 1.0)
                    }
                    return 0
                }()
                
                // Statistics overlay with handle - 随上滑动作入场，下滑出场
                if pipManager.isPiPActive || pipManager.isPreparingPiP || swipeUpProgress > 0 {
                    let effectiveProgress = swipeUpProgress * (1 - swipeDownProgress)
                    // 判断当前是否为专注房间卡片且 PiP 激活
                    let isFocusRoomPiPActive = pipManager.isPiPActive && currentCard?.providerType == .focusRoom
                    
                    VStack(spacing: 0) {
                        Spacer()
                        
                        VStack(spacing: 12) {
                            // 横杠指示器（在统计数据上方）
                            SwipeIndicator(progress: swipeUpProgress)
                            
                            // 专注房间入口（仅在专注房间 PiP 激活时显示在数据区域上方）
                            if isFocusRoomPiPActive {
                                Button {
                                    showFocusRoom = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 15))
                                        Text(FocusRoomService.shared.currentRoom?.name ?? "专注房间")
                                            .font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .foregroundStyle(.black.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(12)
                                }
                            }
                            
                            // 统计数据内容
                            statisticsContent(safeArea: safeArea)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, safeArea.bottom + 40)
                    }
                    .opacity(Double(effectiveProgress))
                    .offset(y: CGFloat((1 - effectiveProgress) * 100))
                    .animation(nil, value: effectiveProgress)
                }
                
                // Swipe up hint (only in idle state)
                if !cardManager.cards.isEmpty && !showEditPanel && swipeUpProgress == 0 && !inCorner {
                    SwipeIndicator(progress: 0)
                        .padding(.bottom, 180)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                
                // Edit panel overlay
                if showEditPanel {
                    editPanelOverlay(screenSize: screenSize, safeArea: safeArea)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            syncCardIndex()
        }
        .onChange(of: cardManager.cards) { _ in
            syncCardIndex()
        }
        .onChange(of: pipManager.isPiPActive) { isActive in
            if !isActive {
                currentProvider = nil
            } else {
                // PiP 启动成功后，如果是专注房间卡片且未加入房间，自动弹出房间弹窗
                if currentCard?.providerType == .focusRoom && !FocusRoomService.shared.isInRoom {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showFocusRoom = true
                    }
                }
            }
        }
        .sheet(isPresented: $showAddCard) {
            AddCardSheet(
                cardManager: cardManager,
                insertAfterIndex: currentCardIndex
            ) { newIndex in
                // Navigate to newly added card
                if let index = newIndex {
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                        currentCardIndex = index
                    }
                }
            }
        }
        .sheet(isPresented: $showVideoPicker) {
            VideoPickerView(isPresented: $showVideoPicker) { url in
                handleVideoPicked(url)
            }
        }
        .sheet(isPresented: $showStatistics) {
            NavigationStack {
                StatisticsView()
            }
            .presentationDetents([.fraction(0.8)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
            }
            .presentationDetents([.fraction(0.8)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFocusRoom) {
            FocusRoomView()
                .presentationDetents([.fraction(0.7)])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Subviews
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.black.opacity(0.2))
            
            Text("还没有卡片")
                .font(.headline)
                .foregroundStyle(.black.opacity(0.4))
            
            Button {
                showAddCard = true
            } label: {
                Text("添加卡片")
                    .font(.subheadline)
                    .foregroundStyle(.black.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.08))
                    .cornerRadius(20)
            }
        }
    }
    
    // MARK: - Statistics Content
    
    private func statisticsContent(safeArea: EdgeInsets) -> some View {
        VStack(spacing: 20) {
            // Today's stats
            todayStatsCard
            
            // Quick links
            quickLinksSection
        }
    }
    
    private var todayStatsCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("今日")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.black.opacity(0.4))
                Spacer()
            }
            
            HStack(spacing: 28) {
                // Display time
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDuration(todayDisplayDuration))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.75))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.statsOceanBlue)
                            .frame(width: 6, height: 6)
                        Text("看见生活")
                            .font(.system(size: 11))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
                
                // Away time
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatDuration(todayAwayDuration))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.45))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.statsAmberGlow)
                            .frame(width: 6, height: 6)
                        Text("回归生活")
                            .font(.system(size: 11))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
                
                Spacer()
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }
    
    private var quickLinksSection: some View {
        HStack(spacing: 12) {
            // Statistics button
            Button {
                showStatistics = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 14))
                    Text("详细统计")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.black.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            }
            
            // Privacy policy button
            Button {
                showPrivacyPolicy = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 14))
                    Text("隐私政策")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.black.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Edit Panel Overlay
    
    private func editPanelOverlay(screenSize: CGSize, safeArea: EdgeInsets) -> some View {
        ZStack {
            // Dimming background
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showEditPanel = false
                    }
                }
            
            // Panel content
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 8) {
                    // Handle bar
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 36, height: 4)
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                    
                    // Edit options - cleaner style
                    VStack(spacing: 0) {
                        // Change video (only for video cards)
                        if let card = currentCard,
                           card.providerType == .video {
                            editRow(
                                icon: "video.badge.ellipsis",
                                title: "更换视频",
                                iconColor: .blue
                            ) {
                                editingCardId = card.id
                                showVideoPicker = true
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showEditPanel = false
                                }
                            }
                            
                            Divider()
                                .padding(.leading, 52)
                        }
                        
                        // Add card
                        if cardManager.canAddCards {
                            editRow(
                                icon: "plus.rectangle.on.rectangle",
                                title: "添加卡片",
                                iconColor: .green
                            ) {
                                showAddCard = true
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showEditPanel = false
                                }
                            }
                            
                            Divider()
                                .padding(.leading, 52)
                        }
                        
                        // Delete card
                        if currentCard != nil {
                            editRow(
                                icon: "trash",
                                title: "删除卡片",
                                iconColor: .red
                            ) {
                                deleteCurrentCard()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    showEditPanel = false
                                }
                            }
                        }
                    }
                    .background(.ultraThinMaterial)
                    .cornerRadius(14)
                    .padding(.horizontal, 20)
                    .padding(.bottom, safeArea.bottom + 16)
                }
                .offset(y: editPanelOffset)
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        editPanelOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 80 || value.velocity.height > 400 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showEditPanel = false
                            editPanelOffset = 0
                        }
                    } else {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            editPanelOffset = 0
                        }
                    }
                }
        )
    }
    
    private func editRow(icon: String, title: String, iconColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Gesture Handling
    
    private func handleDragChanged(_ value: DragGesture.Value, screenSize: CGSize) {
        // Don't handle gestures when edit panel is open
        guard !showEditPanel else { return }
        
        // 忽略从屏幕底部边缘开始的手势（避免与系统手势冲突）
        let startY = value.startLocation.y
        let bottomSafeZone: CGFloat = 50  // 底部安全区域
        if startY > screenSize.height - bottomSafeZone {
            return
        }
        
        let translation = value.translation
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        
        // Determine drag direction on first significant movement
        if dragDirection == nil && (horizontalDistance > 15 || verticalDistance > 15) {
            dragDirection = horizontalDistance > verticalDistance ? .horizontal : .vertical

            // 设置滑动状态
            if dragDirection == .vertical {
                if translation.height < 0 && !pipManager.isPiPActive {
                    // 上滑：立即响应，同时开始准备 PiP
                    cardSwipeState = .swipingUp
                    // 上滑开始时立即准备 PiP（只在未准备且未激活时调用）
                    if !pipManager.isPreparingPiP {
                        preparePiPEarly()
                    }
                } else if translation.height > 0 && !pipManager.isPiPActive && !pipManager.isPreparingPiP && cardSwipeState == .idle {
                    // 下滑：只有在完全空闲状态才允许进入编辑模式
                    cardSwipeState = .swipingDown
                }
            }
        }
        
        guard let direction = dragDirection else { return }
        
        switch direction {
        case .horizontal:
            // 禁止在上滑、PiP准备中、PiP激活时的左右滑动
            if !pipManager.isPiPActive && !pipManager.isPreparingPiP && cardSwipeState != .swipingUp && cardManager.cards.count > 1 {
                dragOffset = CGSize(width: translation.width, height: 0)
            }
            
        case .vertical:
            if !pipManager.isPiPActive {
                // PiP 未激活时：处理上滑和下滑
                if cardSwipeState == .swipingUp {
                    // 上滑状态：允许上滑（即使在准备中也要跟手）
                    let clampedHeight = min(translation.height, 0)
                    dragOffset = CGSize(width: 0, height: clampedHeight)
                } else if cardSwipeState == .swipingDown && !pipManager.isPreparingPiP {
                    // 下滑状态：只在未准备时允许下滑（编辑模式）
                    dragOffset = CGSize(width: 0, height: max(translation.height, 0))
                } else if !pipManager.isPreparingPiP {
                    // 其他情况：未准备时允许自由拖动
                    dragOffset = CGSize(width: 0, height: translation.height)
                }
            } else if pipManager.isPiPActive {
                // PiP 激活时：只允许下滑关闭 PiP
                if translation.height > 0 {
                    dragOffset = CGSize(width: 0, height: translation.height)
                }
            }
            // PiP 准备中且非上滑状态：不处理拖动
        }
    }
    
    private func handleDragEnded(_ value: DragGesture.Value, screenSize: CGSize) {
        // Don't handle gestures when edit panel is open
        guard !showEditPanel else { return }

        let translation = value.translation
        let velocity = value.velocity

        guard let direction = dragDirection else {
            // 如果没有方向，直接重置
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                dragOffset = .zero
            }
            dragDirection = nil
            cardSwipeState = .idle
            return
        }

        switch direction {
        case .horizontal:
            // Switch cards with smooth animation
            if !pipManager.isPiPActive && !pipManager.isPreparingPiP && cardManager.cards.count > 1 {
                let threshold: CGFloat = screenSize.width * 0.15
                let velocityThreshold: CGFloat = 400

                withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                    if translation.width < -threshold || velocity.width < -velocityThreshold {
                        currentCardIndex = min(currentCardIndex + 1, cardManager.cards.count - 1)
                    } else if translation.width > threshold || velocity.width > velocityThreshold {
                        currentCardIndex = max(currentCardIndex - 1, 0)
                    }
                }
            }

            // 重置状态
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                dragOffset = .zero
            }
            dragDirection = nil
            cardSwipeState = .idle

        case .vertical:
            let threshold: CGFloat = 80
            let velocityThreshold: CGFloat = 800

            if !pipManager.isPiPActive && !pipManager.isPreparingPiP {
                if cardSwipeState == .swipingUp {
                    if translation.height < -threshold || velocity.height < -velocityThreshold {
                        // 上滑成功 - 立即重置状态，让卡片通过 inCorner 状态跳转到角落
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dragOffset = .zero
                        dragDirection = nil

                        // 先重置状态，让布局计算切换到 inCorner 模式
                        cardSwipeState = .idle

                        // 然后确认启动 PiP
                        if pipManager.isPreparingPiP {
                            // 已经在准备中，确认启动
                            pipManager.confirmStartPiP()
                        } else {
                            // 没有准备（可能是视频卡片没选视频），调用 startPiP 处理
                            startPiP()
                        }
                    } else {
                        // 上滑取消，取消准备
                        pipManager.cancelPrepare()

                        // 重置状态
                        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                            dragOffset = .zero
                        }
                        dragDirection = nil
                        cardSwipeState = .idle
                    }
                } else if cardSwipeState == .swipingDown && (translation.height > threshold || velocity.height > velocityThreshold) {
                    // Swipe down to show edit panel (only if PiP is not active/preparing and started from idle)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        showEditPanel = true
                    }

                    // 重置状态
                    dragOffset = .zero
                    dragDirection = nil
                    cardSwipeState = .idle
                } else {
                    // 其他情况，重置状态
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                        dragOffset = .zero
                    }
                    dragDirection = nil
                    cardSwipeState = .idle
                }
            } else if pipManager.isPiPActive {
                // PiP 激活时：下滑关闭 PiP
                if translation.height > threshold || velocity.height > velocityThreshold {
                    stopPiP()
                }

                // 重置状态
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                    dragOffset = .zero
                }
                dragDirection = nil
                cardSwipeState = .idle
            } else {
                // PiP 准备中：只重置状态，不执行任何操作
                withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
                    dragOffset = .zero
                }
                dragDirection = nil
                cardSwipeState = .idle
            }
        }
    }
    
    // MARK: - PiP Control
    
    private func startPiP() {
        guard let card = currentCard,
              let providerType = card.providerType else {
            return
        }
        
        // For video provider, check if video is selected
        if providerType == .video {
            let config = VideoCardConfiguration.decode(from: card.configurationData)
            if config?.videoURL == nil {
                editingCardId = card.id
                showVideoPicker = true
                return
            }
        }
        
        // For focus room provider, allow starting PiP even without room
        // Provider will show "暂未加入房间" state
        
        print("[HomeView] Starting PiP for card: \(card.id)")
        
        pipViewId = UUID()
        cardManager.updateLastOpenedCard(id: card.id)
        
        let provider = providerType.createProvider(with: card.configurationData)
        currentProvider = provider
        
        // 直接启动 PiP
        pipManager.preparePiP(provider: provider)
    }
    
    /// 提前准备 PiP（在上滑开始时调用）
    private func preparePiPEarly() {
        // 避免重复准备
        guard !pipManager.isPreparingPiP && !pipManager.isPiPActive else { return }
        
        guard let card = currentCard,
              let providerType = card.providerType else {
            return
        }
        
        // For video provider, check if video is selected
        if providerType == .video {
            let config = VideoCardConfiguration.decode(from: card.configurationData)
            if config?.videoURL == nil {
                // 没有视频时，需要在上滑成功时弹出选择器
                return
            }
        }
        
        // For focus room provider, allow preparing PiP even without room
        // Provider will show "暂未加入房间" state
        
        print("[HomeView] Early preparing PiP for card: \(card.id)")
        
        pipViewId = UUID()
        cardManager.updateLastOpenedCard(id: card.id)
        
        let provider = providerType.createProvider(with: card.configurationData)
        currentProvider = provider
        
        // 提前准备 PiP
        pipManager.preparePiP(provider: provider)
    }
    
    private func stopPiP() {
        print("[HomeView] Stopping PiP")
        pipManager.stopPiP()
        currentProvider = nil
    }
    
    private func deleteCurrentCard() {
        guard let card = currentCard else { return }
        
        // Stop PiP if this card is active
        if pipManager.isPiPActive {
            pipManager.stopPiP()
        }
        
        // Adjust index before deletion
        let wasLastCard = currentCardIndex == cardManager.cards.count - 1
        
        cardManager.removeCard(id: card.id)
        
        // Update index
        if wasLastCard && currentCardIndex > 0 {
            currentCardIndex -= 1
        }
    }
    
    // MARK: - Helpers
    
    private func syncCardIndex() {
        if let lastId = cardManager.lastOpenedCardId,
           let index = cardManager.cards.firstIndex(where: { $0.id == lastId }) {
            currentCardIndex = index
        } else if !cardManager.cards.isEmpty {
            currentCardIndex = 0
        }
    }
    
    private func handleVideoPicked(_ url: URL) {
        guard let cardId = editingCardId else { return }
        
        cardManager.updateVideoConfiguration(cardId: cardId, videoURL: url)
        editingCardId = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            startPiP()
        }
    }
    
    // MARK: - Statistics Helpers
    
    private var todayDisplayDuration: TimeInterval {
        let total = tracker.totalDuration(for: Date())
        let away = tracker.totalAwayDuration(for: Date())
        return total - away
    }
    
    private var todayAwayDuration: TimeInterval {
        tracker.totalAwayDuration(for: Date())
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            return "\(hours)时\(minutes)分"
        } else {
            return "\(minutes)分"
        }
    }
}

// MARK: - Card Item View

struct CardItemView: View {
    let card: CardInstance
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let isCurrentCard: Bool
    let isPiPActive: Bool
    let isPreparing: Bool
    
    var body: some View {
        if let providerType = card.providerType {
            ZStack {
                // Preview content
                let videoConfig = VideoCardConfiguration.decode(from: card.configurationData)
                PiPStaticPreview(providerType: providerType, videoURL: videoConfig?.videoURL)
                
                // Label
                VStack {
                    Spacer()
                    HStack {
                        Text(providerType.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(providerType.hasLightBackground ? .black.opacity(0.7) : .white.opacity(0.9))
                            .shadow(color: providerType.hasLightBackground ? .clear : .black.opacity(0.3), radius: 2)
                        Spacer()
                    }
                    .padding(14)
                }
                
                // Loading indicator
                if isPreparing {
                    Color.black.opacity(0.3)
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                }
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(isCurrentCard ? 0.12 : 0.06), radius: isCurrentCard ? 10 : 5, x: 0, y: isCurrentCard ? 5 : 2)
        }
    }
}

// MARK: - Add Card Sheet

struct AddCardSheet: View {
    @ObservedObject var cardManager: CardManager
    let insertAfterIndex: Int
    let onCardAdded: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(cardManager.availableProvidersToAdd(), id: \.rawValue) { providerType in
                    Button {
                        let newIndex = cardManager.addCard(providerType: providerType, afterIndex: insertAfterIndex)
                        dismiss()
                        onCardAdded(newIndex)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: providerType.iconName)
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(providerType.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("添加卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Swipe Indicator Component

/// 上滑/下滑指示器组件 - 箭头变形成横杠
/// progress: 0 = 显示上滑箭头, 1 = 显示横杠
struct SwipeIndicator: View {
    let progress: CGFloat
    
    // 使用 easeInOut 曲线让动画更自然
    private var smoothProgress: CGFloat {
        // 三次贝塞尔缓动
        let t = progress
        return t * t * (3 - 2 * t)
    }
    
    // 文字透明度（前半段快速消失）
    private var textOpacity: Double {
        Double(max(0, 1 - progress * 3))
    }
    
    // 文字缩放
    private var textScale: CGFloat {
        max(0.5, 1 - progress * 0.5)
    }
    
    // 箭头整体缩放（轻微）
    private var chevronScale: CGFloat {
        1 - smoothProgress * 0.1
    }
    
    var body: some View {
        VStack(spacing: max(2, 6 * (1 - smoothProgress))) {
            // 使用 Canvas 绘制变形的箭头
            Canvas { context, size in
                let centerX = size.width / 2
                let centerY = size.height / 2
                
                // 箭头参数
                let armLength: CGFloat = 8 + smoothProgress * 10  // 8 -> 18
                let angle = (1 - smoothProgress) * .pi / 4  // 45° -> 0°
                let thickness: CGFloat = 2.5
                let cornerRadius: CGFloat = 1.25
                
                // 计算两条线的端点
                // 左边的线
                let leftStart = CGPoint(
                    x: centerX - cos(angle) * armLength,
                    y: centerY + sin(angle) * armLength * (1 - smoothProgress * 0.5)
                )
                let leftEnd = CGPoint(x: centerX, y: centerY)
                
                // 右边的线
                let rightStart = CGPoint(x: centerX, y: centerY)
                let rightEnd = CGPoint(
                    x: centerX + cos(angle) * armLength,
                    y: centerY + sin(angle) * armLength * (1 - smoothProgress * 0.5)
                )
                
                // 绘制路径
                var path = Path()
                
                if smoothProgress < 0.95 {
                    // 箭头形态：两条线
                    path.move(to: leftStart)
                    path.addLine(to: leftEnd)
                    path.move(to: rightStart)
                    path.addLine(to: rightEnd)
                } else {
                    // 完全变成横杠
                    let barWidth: CGFloat = 36
                    path.move(to: CGPoint(x: centerX - barWidth/2, y: centerY))
                    path.addLine(to: CGPoint(x: centerX + barWidth/2, y: centerY))
                }
                
                context.stroke(
                    path,
                    with: .color(.black.opacity(0.3)),
                    style: StrokeStyle(
                        lineWidth: thickness,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
            .frame(width: 50, height: 16)
            .scaleEffect(chevronScale)
            
            // 文字（逐渐消失）
            if textOpacity > 0.01 {
                Text("上滑启动")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.black.opacity(0.25 * textOpacity))
                    .scaleEffect(textScale)
            }
        }
        .frame(height: 40)
        .allowsHitTesting(false)
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
