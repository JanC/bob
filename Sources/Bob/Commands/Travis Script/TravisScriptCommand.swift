/*
 * Copyright (c) 2017 N26 GmbH.
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

/// Script old target
/// Struct used to map targets to scripts
public struct TravisTarget {
    /// Name used in the command parameters
    public let name: String
    /// Script to trigger
    public let script: Script
    public init(name: String, script: Script) {
        self.name = name
        self.script = script
    }
}

/// Command executing a script on TravisCI
/// Script are provided via `TravisTarget`s. In case 
/// only 1 traget is provided, the user does not have 
/// to type in the target name
public class TravisScriptCommand {
    public let name: String
    fileprivate let travis: TravisCI
    fileprivate let targets: [TravisTarget]
    fileprivate let defaultBranch: BranchName
    fileprivate let gitHub: GitHub?
    private let appVersionProvider: AppVersionProvider
    
    /// Initializer for the command
    ///
    /// - Parameters:
    ///   - name: Command name to use
    ///   - travis: TravisCI instance
    ///   - targets: Array of possible targets the user can use
    ///   - gitHub: If GitHub config is provided, the command will perform a branch check before invoking TravisCI api
    public init(name: String, travis: TravisCI, targets: [TravisTarget], defaultBranch: BranchName, gitHub: GitHub? = nil, appVersionProvider: AppVersionProvider) {
        self.name = name
        self.travis = travis
        self.targets = targets
        self.defaultBranch = defaultBranch
        self.gitHub = gitHub
        self.appVersionProvider = appVersionProvider
    }
}

extension TravisScriptCommand: Command {
    enum Constants {
        static let branchSpecifier: String = "-b"
    }

    public var usage: String {
        let target = self.targets.count == 1 ? "" : " {{target}}"
        var message = "Triger a script by saying `\(self.name + target) \(Constants.branchSpecifier) {{branch}}`. I'll do the job for you. `branch` parameter is optional and it defaults to `\(self.defaultBranch)`"

        if self.targets.count != 1 {
            message += "\nAvailable targets:"
            self.targets.forEach({ message += "\n• " + $0.name })
        }

        return message
    }

    public func execute(with parameters: [String], replyingTo sender: MessageSender) throws {
        var params = parameters
        /// Resolve target
        var target: TravisTarget!
        if self.targets.count == 1 {
            /// Only 1 possible target, the user doesn't have to specify
            target = self.targets[0]
        } else {
            /// More possible targets, resolve which one needs to be used
            guard params.count > 0 else { throw "No parameters provided. See `\(self.name) usage` for instructions on how to use this command" }
            let targetName = params[0]
            params.remove(at: 0)
            guard let existingTarget = self.targets.first(where: { $0.name == targetName }) else { throw "Unknown target `\(targetName)`." }
            target = existingTarget
        }

        /// Resolve branch
        var branch: BranchName = self.defaultBranch
        if let branchSpecifierIndex = params.index(where: { $0 == Constants.branchSpecifier }) {
            guard params.count > branchSpecifierIndex + 1 else { throw "Branch name not specified after `\(Constants.branchSpecifier)`" }
            branch = BranchName(params[branchSpecifierIndex + 1])
            params.remove(at: branchSpecifierIndex + 1)
            params.remove(at: branchSpecifierIndex)
        }

        guard params.count == 0 else { throw "To many parameters. See `\(self.name) usage` for instructions on how to use this command" }

        _ = try self.assertGitHubBranchIfPossible(branch).flatMap {
            return try self.travis.execute(target.script, on: branch)
        }.flatMap(to: TravisCI.Request.self) { response  in
            sender.send("Got it! Executing target *" + target.name + "* success.")
            return try self.travis.request(id: response.request.id)
        }.flatMap { buildRequest in
            try self.pollTravisForBuild(buildRequest: buildRequest)
        }.flatMap { completedRequest in
            return try self.createBuildUrlsMessage(fromCompletedRequest: completedRequest)
        }.map { message in
            sender.send(message)
        }
        .catch { error in
            sender.send("Executing target *" + target.name + "* failed: `\(error)`")
        }
    }

    /// Polls the travis build until it's out of the "loading" state in order to get the travis build id
    private func pollTravisForBuild(buildRequest: TravisCI.Request) throws -> Future<TravisCI.Request.Complete> {
        return try self.travis.poll(requestId: buildRequest.id, until: { request -> TravisCI.Poll<TravisCI.Request.Complete> in
            switch request.state {
            case .pending:
                return .continue
            case .complete(let completedRequest):
                return .stop(completedRequest)
            }
        })
    }

    /**
     Creates the started build url message + app version ready to be posted as it is to Slack

     The message is in a form of
     ```
     1.01 (20195045): https://travis-ci.org/foo/bar/builds/travis-build-id
     ```

     */
    private func createBuildUrlsMessage(fromCompletedRequest completedRequest: TravisCI.Request.Complete) throws -> Future<String> {
        return try self.appVersionProvider.fetchVersion(on: completedRequest.branchName).map { version in
            let buildNumbersUrls: [(version: String, url: URL)] = completedRequest.builds.map { build in
                let travisVersion = version.fullVersion
                let url = self.travis.buildURL(from: build)
                return (version: travisVersion, url: url)
            }

            let message = buildNumbersUrls.reduce("Build URL: ") { $0 + "\n `\($1.version): \($1.url.absoluteString)`" }
            return message

        }.catchMap { error in
            // fallback message without the version number
            let urls = completedRequest.builds.map { self.travis.buildURL(from: $0) }
            let message = urls.reduce("Build URL: ") { $0 + "\n \($1.absoluteString)" }
            return message
        }
    }
    private func assertGitHubBranchIfPossible(_ branch: BranchName) throws -> Future<Void> {
        guard let gitHub = self.gitHub else {
            return travis.worker.future()
        }
        return try gitHub.assertBranchExists(branch)
    }
}
