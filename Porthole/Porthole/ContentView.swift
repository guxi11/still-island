//
//  ContentView.swift
//  Porthole
//
//  Created by zhangyuanyuan on 2026/1/25.
//

import SwiftUI
import AVKit

struct ContentView: View {
    @StateObject private var pipManager = PiPManager.shared
    
    var body: some View {
        NavigationStack {
            HomeView()
        }
    }
}

#Preview {
    ContentView()
}
