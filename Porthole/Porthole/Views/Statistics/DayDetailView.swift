//
//  DayDetailView.swift
//  Porthole
//
//  Detailed view showing all sessions for a specific day.
//

import SwiftUI

// Note: Theme colors (statsOceanBlue, statsAmberGlow, statsJadeGreen, etc.) are defined
// in CalendarStatsView.swift as a public Color extension

/// Detailed view for a single day's usage
struct DayDetailView: View {
    let date: Date
    @ObservedObject private var tracker = DisplayTimeTracker.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary card
                SummaryCard(
                    displayDuration: displayDuration,
                    awayDuration: totalAwayDuration
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if sessions.isEmpty {
                    // Empty state
                    EmptyStateView()
                        .frame(minHeight: 200)
                } else {
                    // Compact session list
                    VStack(spacing: 8) {
                        ForEach(sessions, id: \.id) { session in
                            CompactSessionRow(session: session)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 20)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(formattedDate)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var sessions: [DisplaySession] {
        tracker.sessions(for: date)
    }

    private var totalDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.duration }
    }

    private var displayDuration: TimeInterval {
        totalDuration - totalAwayDuration
    }

    private var totalAwayDuration: TimeInterval {
        sessions.reduce(0) { $0 + $1.totalAwayDuration }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - Summary Card

struct SummaryCard: View {
    let displayDuration: TimeInterval
    let awayDuration: TimeInterval

    var body: some View {
        HStack(spacing: 0) {
            // Display duration
            VStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.statsOceanBlue)

                Text(formatDuration(displayDuration))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("亮屏")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            // Divider
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1, height: 50)

            // Away duration
            VStack(spacing: 4) {
                Image(systemName: "moon.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.statsAmberGlow)

                Text(formatDuration(awayDuration))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("熄屏")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text("无使用记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Compact Session Row

struct CompactSessionRow: View {
    let session: DisplaySession

    var body: some View {
        HStack(spacing: 12) {
            // Provider icon with color
            Image(systemName: providerIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(providerColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Provider name and time
            VStack(alignment: .leading, spacing: 2) {
                Text(providerName)
                    .font(.system(size: 14, weight: .medium))

                Text("\(formattedStartTime) - \(formattedEndTime)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Duration
            Text(session.formattedDuration)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(providerColor)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var providerIcon: String {
        switch session.providerType {
        case "time": return "clock.fill"
        case "timer": return "timer"
        case "camera": return "video.fill"
        case "cat": return "cat.fill"
        case "video": return "play.rectangle.fill"
        default: return "questionmark"
        }
    }

    private var providerName: String {
        switch session.providerType {
        case "time": return "时钟"
        case "timer": return "计时器"
        case "camera": return "实景"
        case "cat": return "小猫"
        case "video": return "视频"
        default: return session.providerType
        }
    }

    private var providerColor: Color {
        switch session.providerType {
        case "time": return Color.statsOceanBlue
        case "timer": return Color.statsJadeGreen
        case "camera": return Color.statsLavender
        case "cat": return Color.statsPeachPink
        case "video": return Color.statsAmberGold
        default: return .gray
        }
    }

    private var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: session.startTime)
    }

    private var formattedEndTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: session.endTime ?? Date())
    }
}

#Preview {
    NavigationStack {
        DayDetailView(date: Date())
    }
}
