//
//  ContentView.swift
//  Still Island
//
//  Created by zhangyuanyuan on 2026/1/25.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var pipManager = PiPManager.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Top spacing for breathing room
                    Spacer()
                        .frame(height: 20)
                    
                    // PiP Control Section - dual-column layout
                    PiPSectionView(pipManager: pipManager)
                        .padding(.horizontal, 20)
                    
                    // Statistics Navigation - entire row is tappable
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
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.quaternary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                        .frame(height: 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    ContentView()
}
