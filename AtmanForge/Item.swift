//
//  Item.swift
//  AtmanForge
//
//  Created by Niklas Wahrman on 26.1.2026.
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
