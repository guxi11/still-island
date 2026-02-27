//
//  AddCardButton.swift
//  Porthole
//
//  Button to add a new card to the home page.
//

import SwiftUI

/// A dashed button card for adding new cards to the home page
struct AddCardButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .foregroundStyle(.secondary.opacity(0.3))

                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.5))

                    Text("添加卡片")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            .frame(height: 110)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AddCardButton(onTap: {})
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}
