/*
 * Copyright (c) 2018 N26 GmbH.
 *
 * This file is part of Bob.
 *
 * Bob is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Bob is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Bob.  If not, see <http://www.gnu.org/licenses/>.
 */

import Foundation
import Vapor

// Command used to bump up build numbers directly on GitHub
public class BumpCommand {
    enum Constants {
        static let branchSpecifier: String = "-b"
    }
    
    fileprivate let gitHub: GitHub
    fileprivate let plistPaths: [String]
    fileprivate let message: String
    fileprivate let author: Author

    private let appVersionProvider: AppVersionProvider


    /// Source of the version we will bump
    fileprivate var versionPlist: String {
        return self.plistPaths[0]
    }
    /// Initializer
    ///
    /// - Parameters:
    ///   - config: Configuration to use to connect to github
    ///   - plistPaths: Paths to .plist files to update. Path relative from the root of the repository
    ///   - author: Commit author. Shows up in GitHub
    ///   - messageFormat: Format for the commit message. `<version>` will be replaced with the version string
    public init(gitHub: GitHub, plistPaths: [String], author: Author, message: String = "[General] Aligns version to <version>") {
        self.gitHub = gitHub
        self.plistPaths = plistPaths
        self.message = message
        self.author = author
        self.appVersionProvider = GithubFileAppVersionProvider(gitHub: gitHub, configuration: GithubFileAppVersionProvider.Configutation(versionPlistPath: plistPaths[0]))
    }
}

extension BumpCommand: Command {
    public var name: String {
        return "bump"
    }

    public var usage: String {
        return "Bump up build number by typing `bump`. Specify a branch by typing `\(Constants.branchSpecifier) {branch}`."
    }

    public func execute(with parameters: [String], replyingTo sender: MessageSender) throws {
        guard plistPaths.count > 0 else {
            throw "Failed to bump. Misconfiguration of the `bump` command. Missing Plist file paths."
        }

        var params = parameters

        var specifiedBranch: BranchName?
        if let branchSpecifierIndex = params.index(where: { $0 == Constants.branchSpecifier }) {
            guard params.count > branchSpecifierIndex + 1 else { throw "Branch name not specified after `\(Constants.branchSpecifier)`" }
            specifiedBranch = BranchName(params[branchSpecifierIndex + 1])
            params.remove(at: branchSpecifierIndex + 1)
            params.remove(at: branchSpecifierIndex)
        }

        guard let branch = specifiedBranch else { throw "Please specify a branch" }

        sender.send("One sec...")

        _ = try self.appVersionProvider.fetchVersion(on: branch).flatMap(to: GitHub.Git.Reference.self) { version in
            let bumpedVersion = try version.bump()
            let align = VersionUpdater(plistPaths: self.plistPaths, version: bumpedVersion)
            let message = version.commitMessage(template: self.message)

            return try self.gitHub.newCommit(updatingItemsWith: align, on: branch, by: self.author, message: message)
        }.map { _ in
            sender.send("ok")
        }.catch { error in
            sender.send("Command failed with error ```\(error)```")
        }
    }
}

private extension Array where Element == TreeItem {
    func firstItem(named name: String) throws -> TreeItem {
        guard let item = filter({ $0.path == name }).first else { throw "TreeItem '\(name)' not found" }
        return item
    }
}
