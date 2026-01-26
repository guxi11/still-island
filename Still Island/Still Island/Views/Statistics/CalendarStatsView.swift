//
//  CalendarStatsView.swift
//  Still Island
//
//  Calendar view showing daily usage with visual indicators.
//

import SwiftUI

/// Calendar view with monthly navigation and usage intensity indication
struct CalendarStatsView: View {
    @Binding var selectedDate: Date
    @ObservedObject private var tracker = DisplayTimeTracker.shared
    @State private var currentMonth = Date()
    @State private var showDayDetail = false
    
    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols
    
    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
                
                Spacer()
                
                Text(monthYearString)
                    .font(.headline)
                
                Spacer()
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal)
            
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(daysInMonth, id: \.self) { date in
                    if let date = date {
                        DayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            duration: tracker.totalDuration(for: date),
                            maxDuration: maxDurationInMonth
                        )
                        .onTapGesture {
                            selectedDate = date
                            showDayDetail = true
                        }
                    } else {
                        // Empty cell for padding
                        Color.clear
                            .aspectRatio(1, contentMode: .fill)
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.top)
        .sheet(isPresented: $showDayDetail) {
            NavigationStack {
                DayDetailView(date: selectedDate)
            }
            .presentationDetents([.medium, .large])
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
        
        // Get the weekday of the first day (1 = Sunday, 2 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        
        // Create array with padding for days before the month starts
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        
        // Add all days in the month
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private var maxDurationInMonth: TimeInterval {
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))!
        let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
        
        let dailyTotals = tracker.dailyTotals(from: startOfMonth, to: endOfMonth)
        return dailyTotals.map { $0.duration }.max() ?? 0
    }
    
    // MARK: - Actions
    
    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = newMonth
        }
    }
    
    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = newMonth
        }
    }
}

/// Individual day cell in the calendar
struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let duration: TimeInterval
    let maxDuration: TimeInterval
    
    private let calendar = Calendar.current
    
    var body: some View {
        ZStack {
            // Background indicating usage intensity
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
            
            // Day number
            Text("\(calendar.component(.day, from: date))")
                .font(.callout)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(textColor)
        }
        .aspectRatio(1, contentMode: .fill)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }
    
    private var backgroundFill: Color {
        if duration == 0 {
            return Color(.tertiarySystemGroupedBackground)
        }
        
        // Calculate intensity based on duration relative to max
        let intensity = maxDuration > 0 ? min(duration / maxDuration, 1.0) : 0
        let opacity = 0.2 + (intensity * 0.6) // Range from 0.2 to 0.8
        
        return Color.green.opacity(opacity)
    }
    
    private var textColor: Color {
        if isToday {
            return .blue
        }
        if duration > 0 && duration / maxDuration > 0.5 {
            return .white
        }
        return .primary
    }
}

#Preview {
    CalendarStatsView(selectedDate: .constant(Date()))
}
