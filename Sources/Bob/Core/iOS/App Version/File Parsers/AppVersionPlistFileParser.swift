//
//  AppVersionPlistFileParser.swift
//  Bob
//
//  Created by Jan Chaloupecky on 19.12.19.
//

import Foundation

struct AppVersionPlistFileParser: AppVersionFileParser {
    static func parseVersion(fromFile data: Data) throws -> Version {
        guard let fileContentString = String(data: data, encoding: .utf8) else {
            throw "Could not convert version file data to String."
        }
        return try Version(fromPlistContent: fileContentString)
    }
}
