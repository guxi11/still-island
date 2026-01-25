//
//  Item.swift
//  Still Island
//
//  Created by zhangyuanyuan on 2026/1/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
