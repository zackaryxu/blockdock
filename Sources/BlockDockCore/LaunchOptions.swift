import Foundation

public struct LaunchOptions {
    public enum Demo: Equatable { case running, expired }
    public private(set) var dataDirectory: URL?
    public private(set) var renderOutput: URL?
    public private(set) var demo: Demo?
    public var badgeRenderOutput: URL? {
        guard let output = renderOutput else { return nil }
        return output.deletingLastPathComponent()
            .appendingPathComponent(output.deletingPathExtension().lastPathComponent + "-badge.png")
    }

    public init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "--data-dir", "--render-demo":
                guard index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--"),
                      !arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { throw LaunchError("\(option) requires a path.") }
                let path = URL(fileURLWithPath: arguments[index + 1], isDirectory: option == "--data-dir")
                if option == "--data-dir" {
                    guard dataDirectory == nil else { throw LaunchError("Specify --data-dir only once.") }
                    dataDirectory = path
                } else {
                    guard renderOutput == nil else { throw LaunchError("Specify --render-demo only once.") }
                    renderOutput = path
                }
                index += 1
            case "--demo", "--demo-expired":
                guard demo == nil else { throw LaunchError("Choose only one demo mode.") }
                demo = option == "--demo" ? .running : .expired
            default:
                throw LaunchError("Unknown option: \(option)")
            }
            index += 1
        }
        if (demo != nil || renderOutput != nil) && dataDirectory == nil {
            throw LaunchError("Demo and rendering modes require --data-dir with an explicit path.")
        }
        if let output = renderOutput, let badge = badgeRenderOutput, let directory = dataDirectory {
            let protected = ["blocks.json", "badge-position.json"].map {
                directory.appendingPathComponent($0).standardizedFileURL.resolvingSymlinksInPath().path
            }
            for target in [output, badge] {
                let resolved = target.standardizedFileURL.resolvingSymlinksInPath().path
                guard !protected.contains(resolved) else {
                    throw LaunchError("Screenshots cannot replace app data. Choose another output path.")
                }
                guard !FileManager.default.fileExists(atPath: target.path) else {
                    throw LaunchError("Screenshot output already exists: \(target.path). Choose a new path.")
                }
            }
        }
    }
}

public struct LaunchError: Error, LocalizedError {
    private let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
