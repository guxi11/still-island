//
//  CalendarStatsView.swift
//  Porthole
//
//  Calendar view showing daily usage with visual indicators.
//

import SwiftUI

// MARK: - Theme Colors (shared across Statistics views)
extension Color {
    /// 海洋蓝 - 代表专注时的屏幕亮起时间，如同平静的海面
    static let statsOceanBlue = Color(red: 0.20, green: 0.55, blue: 0.82)
    /// 珊瑚橙 - 代表休息时间，如同温暖的晚霞
    static let statsAmberGlow = Color(red: 0.95, green: 0.45, blue: 0.35)
    /// 翡翠绿 - 计时器类型
    static let statsJadeGreen = Color(red: 0.25, green: 0.72, blue: 0.58)
    /// 薰衣草紫 - 实景相机类型
    static let statsLavender = Color(red: 0.58, green: 0.44, blue: 0.86)
    /// 蜜桃粉 - 小猫伴侣类型
    static let statsPeachPink = Color(red: 0.96, green: 0.60, blue: 0.55)
    /// 琥珀金 - 视频类型
    static let statsAmberGold = Color(red: 0.95, green: 0.68, blue: 0.25)
}

/// Calendar view with monthly navigation and usage intensity indication
struct CalendarStatsView: View {
    @Binding var selectedDate: Date
    @ObservedObject private var tracker = DisplayTimeTracker.shared
    @State private var currentMonth = Date()
    @State private var showDayDetail = false

    private let calendar = Calendar.current
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Month navigation card
                HStack {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text(monthYearString)
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    Spacer()

                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Calendar grid card
                VStack(spacing: 12) {
                    // Weekday headers
                    HStack(spacing: 0) {
                        ForEach(weekdaySymbols, id: \.self) { symbol in
                            Text(symbol)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    // Calendar grid - GitHub style heatmap
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(daysInMonth, id: \.self) { date in
                            if let date = date {
                                ModernDayCell(
                                    date: date,
                                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                                    isToday: calendar.isDateInToday(date),
                                    duration: displayDuration(for: date),
                                    maxDuration: maxDisplayDurationInMonth
                                )
                                .onTapGesture {
                                    selectedDate = date
                                    showDayDetail = true
                                }
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.clear)
                                    .aspectRatio(1, contentMode: .fill)
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .padding(.horizontal, 16)

                // Legend
                HStack(spacing: 8) {
                    Text("少")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(intensityColor(level: level))
                            .frame(width: 14, height: 14)
                    }

                    Text("多")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)

                Spacer(minLength: 40)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("日历")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDayDetail) {
            NavigationStack {
                DayDetailView(date: selectedDate)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Helper Functions

    private func intensityColor(level: Int) -> Color {
        switch level {
        case 0: return Color(.systemFill)
        case 1: return Color.statsOceanBlue.opacity(0.25)
        case 2: return Color.statsOceanBlue.opacity(0.50)
        case 3: return Color.statsOceanBlue.opacity(0.75)
        default: return Color.statsOceanBlue
        }
    }

    // MARK: - Computed Properties

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: currentMonth)
    }

    private var daysInMonth: [Date?] {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let range = calendar.range(of: .day, in: .month, for: startOfMonth)!

        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }

        return days
    }

    private var maxDisplayDurationInMonth: TimeInterval {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!

        let dailyTotals = tracker.dailyTotals(from: startOfMonth, to: endOfMonth)
        return dailyTotals.map { $0.duration - $0.awayDuration }.max() ?? 0
    }

    private func displayDuration(for date: Date) -> TimeInterval {
        let total = tracker.totalDuration(for: date)
        let away = tracker.totalAwayDuration(for: date)
        return total - away
    }

    // MARK: - Actions

    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentMonth = newMonth
            }
        }
    }

    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentMonth = newMonth
            }
        }
    }
}

/// Modern day cell with GitHub-style heatmap design
struct ModernDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let duration: TimeInterval
    let maxDuration: TimeInterval

    private let calendar = Calendar.current

    var body: some View {
        ZStack {
            // Background - intensity based fill
            RoundedRectangle(cornerRadius: 6)
                .fill(fillColor)

            // Day number
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 13, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(textColor)
        }
        .aspectRatio(1, contentMode: .fill)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? Color.statsOceanBlue : (isSelected ? Color.statsOceanBlue.opacity(0.5) : Color.clear), lineWidth: isToday ? 2 : 1.5)
        )
    }

    private var fillColor: Color {
        if duration == 0 {
            return Color(.systemFill)
        }
        let intensity = maxDuration > 0 ? min(duration / maxDuration, 1.0) : 0
        return Color.statsOceanBlue.opacity(0.2 + (intensity * 0.8))
    }

    private var textColor: Color {
        if duration == 0 {
            return .secondary
        }
        let intensity = maxDuration > 0 ? min(duration / maxDuration, 1.0) : 0
        return intensity > 0.5 ? .white : .primary
    }
}

#Preview {
    NavigationStack {
        CalendarStatsView(selectedDate: .constant(Date()))
    }
}
