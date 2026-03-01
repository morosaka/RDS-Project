// Sources/CSVSwiftSDK/CSVDelimiter.swift v1.0.0
/**
 * Generic CSV parsing utility.
 * --- Revision History ---
 * v1.0.0 - 2026-03-01 - Initial standardization.
 */
//
//  CSVDelimiter.swift
//  SwiftCSV
//
//  Created by Christian Tietze on 01.07.22.
//  Copyright © 2022 SwiftCSV. All rights reserved.
//

public enum CSVDelimiter: Equatable, ExpressibleByUnicodeScalarLiteral, Sendable {

    public typealias UnicodeScalarLiteralType = Character

    case comma, semicolon, tab
    case character(Character)

    public init(unicodeScalarLiteral: Character) {
        self.init(rawValue: unicodeScalarLiteral)
    }

    init(rawValue: Character) {
        switch rawValue {
        case ",":  self = .comma
        case ";":  self = .semicolon
        case "\t": self = .tab
        default:   self = .character(rawValue)
        }
    }

    public var rawValue: Character {
        switch self {
        case .comma: return ","
        case .semicolon: return ";"
        case .tab: return "\t"
        case .character(let character): return character
        }
    }
}
