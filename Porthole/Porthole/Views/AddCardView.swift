//
//  AddCardView.swift
//  Porthole
//
//  Sheet view for selecting which card type to add.
//

import SwiftUI

/// Sheet view for selecting which card type to add to the home page
struct AddCardView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var cardManager = CardManager.shared

    let onAdd: (PiPProviderType) -> Void

    var body: some View {
        NavigationView {
            List {
                ForEach(cardManager.availableProvidersToAdd(), id: \.self) { providerType in
                    Button {
                        onAdd(providerType)
                        dismiss()
                    } label: {
                        HStack(spacing: 16) {
                            // Icon
                            Image(systemName: providerType.iconName)
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                                .frame(width: 32)

                            // Name and description
                            VStack(alignment: .leading, spacing: 2) {
                                Text(providerType.displayName)
                                    .font(.body)
                                    .foregroundStyle(.primary)

                                if providerType.allowsMultipleInstances {
                                    Text("可添加多个")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "plus.circle")
                                .foregroundStyle(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("添加卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    AddCardView(onAdd: { _ in })
}
