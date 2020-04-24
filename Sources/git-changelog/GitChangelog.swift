import Foundation

struct Changelog {
    typealias Category = String
    typealias Entry = String
    typealias ReleaseID = String

    struct Release {
        let date: Date
        let id: Changelog.ReleaseID
        var categorizedEntries: [Category: [Entry]]
    }

    var unreleased: Release = Release(date: Date(), id: "don't care", categorizedEntries: [:])
    var releases: [ReleaseID: Release] = [:]
}


public final class GitChangelog {
    let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public enum Error: Swift.Error {
        case invalidArgumentCount
        case commandFailed
    }

    private let arguments: [String]

    private let git: GitShell

    public init(arguments: [String] = CommandLine.arguments) throws {
        self.arguments = arguments
        self.git = try GitShell(bash: Bash())
    }

    public func run() throws {
        guard self.arguments.count >= 1 else {
            throw Error.invalidArgumentCount
        }

        if self.arguments.count > 1 {
            let subcommand = self.arguments[1]
            switch subcommand {
            case "--version":
                print("v\(VERSION)")
            default:
                print("Unrecognized commande line arguments")
            }
        } else {
            var changelog: Changelog = Changelog()
            var currentReleaseID: Changelog.ReleaseID?

            let commits = try! self.git.commits()
            try! commits.forEach { commit in
                // this commit has version bump

                let changelogBody = commit.body.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "[changelog]").dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

                let pattern = #"(added|changed|deprecated|removed|fixed|security|release):\w?(.*)"#
                let regex = try NSRegularExpression(pattern: pattern, options: [])

                let nsrange = NSRange(changelogBody.startIndex..<changelogBody.endIndex,
                in: changelogBody)
                regex.enumerateMatches(in: changelogBody, options: [], range: nsrange) {
                     (match, _, stop) in

                    guard let match = match else { return }

                    if match.numberOfRanges == 3 {
                        guard let firstCaptureRange = Range(match.range(at: 1),
                        in: changelogBody),
                        let secondCaptureRange = Range(match.range(at: 2),
                                                       in: changelogBody) else {
                                                        return
                        }

                        let category = changelogBody[firstCaptureRange].trimmingCharacters(in: .whitespacesAndNewlines)
                        let message = changelogBody[secondCaptureRange].trimmingCharacters(in: .whitespacesAndNewlines)

                        switch category {
                        case "release":
                            currentReleaseID = message
                            changelog.releases[currentReleaseID!] = Changelog.Release(date: commit.date, id: currentReleaseID!, categorizedEntries: [:])
                        default:
                            if let releaseID = currentReleaseID {
                                if let _ = changelog.releases[releaseID]!.categorizedEntries[category] {
                                    changelog.releases[releaseID]!.categorizedEntries[category]!.append(message)
                                } else {
                                    changelog.releases[releaseID]!.categorizedEntries[category] = [message]
                                }
                            } else {
                                if let _ = changelog.unreleased.categorizedEntries[category] {
                                    changelog.unreleased.categorizedEntries[category]!.append(message)
                                } else {
                                    changelog.unreleased.categorizedEntries[category] = [message]
                                }
                            }
                        }
                    }
                }
            }

            var markdownChanglog = ""

            markdownChanglog += """
            # Changelog

            All notable changes to this project will be documented in this file.

            The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
            and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
            """

            markdownChanglog += "\n\n## Unreleased - now\n"

            changelog.unreleased.categorizedEntries.forEach { (category, entries) in
                markdownChanglog += "\n### \(category.capitalized)\n"
                entries.forEach { (entry) in
                    markdownChanglog += "- \(entry)\n"
                }
            }

            changelog.releases.forEach { (releaseID, release) in
                markdownChanglog += "\n\n## \(releaseID) - \(self.dateFormatter.string(from: release.date))\n"
                release.categorizedEntries.forEach { (category, entries) in
                    markdownChanglog += "\n### \(category.capitalized)\n"
                    entries.forEach { (entry) in
                        markdownChanglog += "- \(entry)\n"
                    }
                }
            }

            print(markdownChanglog)

        }
    }
}

extension String {
  func replaceCharactersFromSet(characterSet: CharacterSet, replacementString: String = "") -> String {
    return self.components(separatedBy: characterSet).joined(separator: replacementString)
  }
}