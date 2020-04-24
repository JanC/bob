//
//  GithubAppVersionProvider.swift
//  Bob
//
//  Created by Jan Chaloupecky on 05.12.19.
//

import Foundation
import Vapor

public class GithubFileAppVersionProvider: AppVersionProvider {

    public struct Configutation {
        /// The path of the plist path to look for the app version
        public let versionPlistPath: String

        public init(versionPlistPath: String) {
            self.versionPlistPath = versionPlistPath
        }
    }

    let gitHub: GitHub
    let configuration: Configutation

    public init(gitHub: GitHub, configuration: Configutation) {
        self.gitHub = gitHub
        self.configuration = configuration
    }

    public func fetchVersion(on branch: BranchName) throws -> Future<Version> {
        return try gitHub.currentState(on: branch).map(to: TreeItem.self) { currentState in
            return try currentState.items.firstItem(named: self.configuration.versionPlistPath)
        }.flatMap { treeItem in
            return try self.version(plistFile: treeItem)
        }
    }
    private func version(plistFile: TreeItem) throws -> Future<Version> {
        return try gitHub.gitBlob(sha: plistFile.sha).map(to: Version.self) { blob in
            guard let content = blob.string else { throw "Could not convert plist file content to String" }
            return try Version(fromPlistContent: content)
        }
    }
}

private extension Array where Element == TreeItem {
    func firstItem(named name: String) throws -> TreeItem {
        guard let item = filter({ $0.path == name }).first else { throw "TreeItem '\(name)' not found" }
        return item
    }
}

