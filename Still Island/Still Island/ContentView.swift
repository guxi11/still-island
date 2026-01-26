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
        NavigationSplitView {
            List {
                // PiP Control Section - dual-column layout
                PiPSectionView(pipManager: pipManager)
                
                // Statistics Navigation
                Section {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text("使用统计")
                                    .font(.headline)
                                Text("查看悬浮窗口使用时长")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("数据")
                }
            }
            .navigationTitle("觉知")
        } detail: {
            VStack(spacing: 20) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("保持觉知，珍惜时间")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
}
