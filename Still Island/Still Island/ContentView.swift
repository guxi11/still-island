//
//  ContentView.swift
//  Still Island
//
//  Created by zhangyuanyuan on 2026/1/25.
//

import SwiftUI
import SwiftData
import AVKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @StateObject private var pipManager = PiPManager.shared
    
    // Keep a strong reference to the time provider
    @State private var timeProvider: TimeDisplayProvider?
    
    var body: some View {
        NavigationSplitView {
            List {
                // PiP Control Section
                Section {
                    Button(action: togglePiP) {
                        HStack {
                            Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text(pipManager.isPiPActive ? "关闭悬浮时钟" : "启动悬浮时钟")
                                    .font(.headline)
                                Text(pipManager.isPiPActive ? "点击关闭 PiP 窗口" : "在其他应用上方显示时间")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if pipManager.isPiPActive {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 10, height: 10)
                            } else if pipManager.isPreparingPiP {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(pipManager.isPreparingPiP)
                    
                    // PiP preview - this hosts the display layer in the view hierarchy
                    if pipManager.isPreparingPiP || pipManager.isPiPActive {
                        PiPHostView(
                            displayLayer: pipManager.displayLayer ?? AVSampleBufferDisplayLayer(),
                            onViewCreated: { view in
                                print("[ContentView] SampleBufferDisplayView created, binding to PiPManager...")
                                pipManager.bindToViewLayer(view)
                            }
                        )
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onAppear {
                            print("[ContentView] PiPHostView appeared")
                        }
                    }
                    
                    // Show error message if any
                    if let error = pipManager.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("悬浮窗口")
                } footer: {
                    Text("提示：启动后将应用切到后台可以看到悬浮窗口")
                        .font(.caption2)
                }
                
                // Original Items Section
                Section {
                    ForEach(items) { item in
                        NavigationLink {
                            Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                        } label: {
                            Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        }
                    }
                    .onDelete(perform: deleteItems)
                } header: {
                    Text("记录")
                }
            }
            .navigationTitle("觉知")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
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
    
    private func togglePiP() {
        if pipManager.isPiPActive || pipManager.isPreparingPiP {
            pipManager.stopPiP()
            timeProvider = nil
        } else {
            let provider = TimeDisplayProvider()
            timeProvider = provider
            pipManager.preparePiP(provider: provider)
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
