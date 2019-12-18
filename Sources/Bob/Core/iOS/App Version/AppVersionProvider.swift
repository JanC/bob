//
//  AppVersionFetcher.swift
//  Bob
//
//  Created by Jan Chaloupecky on 18.12.19.
//

import Foundation
import typealias Async.Future

public protocol AppVersionProvider {
    func fetchVersion(on branch: BranchName) throws -> Future<Version>
}
