//
//  VideoPickerView.swift
//  Porthole
//
//  A view for picking videos from the photo library.
//

import SwiftUI
import PhotosUI

/// SwiftUI view for picking videos from photo library
struct VideoPickerView: View {
    @Binding var isPresented: Bool
    let onVideoPicked: (URL) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                // Title
                Text("选择视频")
                    .font(.title2.bold())

                // Description
                Text("从相册中选择一个MP4视频用于浮窗循环播放")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Photo picker
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("选择视频", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .disabled(isProcessing)

                // Processing indicator
                if isProcessing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("处理中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        isPresented = false
                    }
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            if let item = newItem {
                processSelectedItem(item)
            }
        }
    }

    private func processSelectedItem(_ item: PhotosPickerItem) {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                // Load the video as a transferable file
                if let movie = try await item.loadTransferable(type: VideoTransferable.self) {
                    await MainActor.run {
                        isProcessing = false
                        onVideoPicked(movie.url)
                        isPresented = false
                    }
                } else {
                    await MainActor.run {
                        isProcessing = false
                        errorMessage = "无法加载视频"
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    errorMessage = "加载失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

/// Transferable type for video files
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            // Copy to app's documents directory for persistence
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let videoDirectory = documentsDirectory.appendingPathComponent("Videos", isDirectory: true)

            // Create Videos directory if needed
            try? FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true)

            // Generate unique filename
            let filename = "video_\(UUID().uuidString).mp4"
            let destinationURL = videoDirectory.appendingPathComponent(filename)

            // Remove existing file if any
            try? FileManager.default.removeItem(at: destinationURL)

            // Copy file
            try FileManager.default.copyItem(at: received.file, to: destinationURL)

            return VideoTransferable(url: destinationURL)
        }
    }
}

#Preview {
    VideoPickerView(isPresented: .constant(true)) { url in
        print("Selected video: \(url)")
    }
}
