import SwiftUI

struct HomeView: View {
    @StateObject private var pipManager = PiPManager.shared
    @StateObject private var cardManager = CardManager.shared
    
    // State for view position
    @State private var viewState: HomeViewState = .main
    @State private var dragOffset: CGFloat = 0
    @State private var wasPiPActive = false
    
    // Deep blue background color matching the Porthole theme
    private let backgroundColor = Color(red: 10/255, green: 24/255, blue: 48/255)
    
    enum HomeViewState {
        case sidebar
        case main
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let sidebarWidth = geometry.size.width * 0.6
                let screenWidth = geometry.size.width
                
                ZStack(alignment: .leading) {
                    // Layer 1: Main Content (Always visible, stationary)
                    ZStack {
                        // Background
                        backgroundColor
                            .ignoresSafeArea()
                        
                        // Light Rays - Only visible when PiP is active AND in main view
                        LightRayView()
                            .opacity((pipManager.isPiPActive && viewState == .main) ? 1.0 : 0)
                            .animation(.easeInOut(duration: 1.5), value: pipManager.isPiPActive)
                            .animation(.easeInOut(duration: 0.3), value: viewState)
                            .ignoresSafeArea()
                        
                        // Global PiP Host - Positioned at Top-Left for smooth animation
                        VStack {
                            HStack {
                                if (pipManager.isPreparingPiP || pipManager.isPiPActive),
                                   let displayLayer = pipManager.displayLayer {
                                    PiPHostView(
                                        displayLayer: displayLayer,
                                        onViewCreated: { view in
                                            print("[HomeView] Binding PiP view layer")
                                            pipManager.bindToViewLayer(view)
                                        }
                                    )
                                    .frame(width: 1, height: 1)
                                    .opacity(0.01)
                                    .allowsHitTesting(false)
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                        
                        // Dimming Overlay when Sidebar is open
                        if viewState == .sidebar {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.spring()) {
                                        viewState = .main
                                    }
                                }
                                .transition(.opacity)
                        }
                    }
                    .frame(width: screenWidth)
                    
                    // Layer 2: Sidebar (Overlay from Left)
                    SidebarView(
                        pipManager: pipManager
                    )
                    .frame(width: sidebarWidth)
                    .background(Color(.systemGroupedBackground))
                    .offset(x: sidebarOffset(sidebarWidth: sidebarWidth))
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let translation = value.translation.width
                            
                            switch viewState {
                            case .main:
                                if translation > 0 { // Only allow opening sidebar
                                    dragOffset = translation
                                }
                            case .sidebar:
                                if translation < 0 { // Only allow closing sidebar
                                    dragOffset = translation
                                }
                            }
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 50
                            let translation = value.translation.width
                            
                            withAnimation(.spring()) {
                                switch viewState {
                                case .main:
                                    if translation > threshold {
                                        viewState = .sidebar
                                    }
                                case .sidebar:
                                    if translation < -threshold {
                                        viewState = .main
                                    }
                                }
                                dragOffset = 0
                            }
                        }
                )
            }
            .navigationBarHidden(true)
            .onAppear {
                // Delay slightly to ensure CardManager is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    autoStartPiP()
                }
            }
            .onChange(of: cardManager.cards.isEmpty) { isEmpty in
                if !isEmpty {
                    autoStartPiP()
                }
            }
            .onChange(of: pipManager.isPiPActive) { isActive in
                if isActive {
                    wasPiPActive = true
                    // Auto close sidebar when PiP starts
                    withAnimation(.spring()) {
                        viewState = .main
                    }
                } else if wasPiPActive {
                    // PiP was active and now is closed -> Open Sidebar
                    withAnimation(.spring()) {
                        viewState = .sidebar
                    }
                }
            }
        }
    }
    
    private func sidebarOffset(sidebarWidth: CGFloat) -> CGFloat {
        let baseOffset = viewState == .sidebar ? 0 : -sidebarWidth
        
        // Only adjust if we are interacting with the sidebar layer
        if viewState == .main && dragOffset > 0 {
            return baseOffset + dragOffset
        } else if viewState == .sidebar && dragOffset < 0 {
            return baseOffset + dragOffset
        }
        
        return baseOffset
    }
    
    private func autoStartPiP() {
        // Only auto-start if not already active and we have a last opened card
        guard !pipManager.isPiPActive, !pipManager.isPreparingPiP,
              let lastCardId = cardManager.lastOpenedCardId,
              let card = cardManager.cards.first(where: { $0.id == lastCardId }),
              let providerType = card.providerType else {
            return
        }
        
        print("[HomeView] Auto-starting PiP for card: \(lastCardId)")
        
        // Create and start provider
        let provider = providerType.createProvider(with: card.configurationData)
        pipManager.preparePiP(provider: provider)
    }
}

struct SidebarView: View {
    @ObservedObject var pipManager: PiPManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("舷窗")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                Spacer()
            }
            .padding(.top, 100) // Increased top padding
            .padding(.horizontal, 24)
            .padding(.bottom, 10)
            
            ScrollView {
                VStack(spacing: 24) {
                    PiPSectionView(pipManager: pipManager, shouldBindPiP: false)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    
                    // Statistics Button
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                            
                            Text("使用统计")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.quaternary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    
                    // Privacy Policy Link
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Text("隐私政策")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    HomeView()
}
