import Foundation
import XCTest
@testable import BlockDockCore

final class LaunchOptionsTests: XCTestCase {
    func testMalformedDemoPathsFailBeforeAppDataCanBeSelected() {
        for mode in ["--demo", "--demo-expired"] {
            for arguments in [[mode], [mode, "--data-dir"], [mode, "--data-dir", ""],
                              [mode, "--data-dir", "  "], [mode, "--data-dir", "--render-demo", "/tmp/out.png"]] {
                XCTAssertThrowsError(try LaunchOptions(arguments: arguments), "\(arguments)")
            }
        }
        XCTAssertThrowsError(try LaunchOptions(arguments: ["--render-demo", "/tmp/out.png"]))
    }

    func testConflictingAndUnknownOptionsAreRejected() {
        for arguments in [["--unknown"], ["--demo", "--demo-expired", "--data-dir", "/tmp/demo"],
                          ["--data-dir", "/tmp/one", "--data-dir", "/tmp/two"],
                          ["--data-dir", "/tmp/demo", "--render-demo"]] {
            XCTAssertThrowsError(try LaunchOptions(arguments: arguments), "\(arguments)")
        }
    }

    func testOrdinaryLaunchAndIsolatedRenderUseExplicitOptions() throws {
        let ordinary = try LaunchOptions(arguments: [])
        XCTAssertNil(ordinary.dataDirectory)
        XCTAssertNil(ordinary.demo)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = root.appendingPathComponent("demo folder")
        let png = root.appendingPathComponent("result.png")
        let options = try LaunchOptions(arguments: ["--demo-expired", "--data-dir", data.path,
                                                    "--render-demo", png.path])
        XCTAssertEqual(options.dataDirectory?.path, data.path)
        XCTAssertEqual(options.renderOutput?.path, png.path)
        XCTAssertEqual(options.demo, .expired)
    }

    func testRendererRefusesDataFilesAndExistingAliasesWithoutChangingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let data = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = data.appendingPathComponent("blocks.json")
        let position = data.appendingPathComponent("badge-position.json")
        func reject(_ output: URL) {
            XCTAssertThrowsError(try LaunchOptions(arguments: ["--demo", "--data-dir", data.path,
                                                                "--render-demo", output.path]))
        }
        reject(history)  // Even a not-yet-created data file must be protected.
        reject(position)
        let bytes = Data("saved history".utf8)
        try bytes.write(to: history)
        let symbolic = root.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: history)
        let hardlink = root.appendingPathComponent("hardlink.png")
        try FileManager.default.linkItem(at: history, to: hardlink)
        reject(symbolic)
        reject(hardlink)
        let output = root.appendingPathComponent("result.png")
        let badge = root.appendingPathComponent("result-badge.png")
        try bytes.write(to: badge)
        reject(output)
        XCTAssertEqual(try Data(contentsOf: history), bytes)
        XCTAssertEqual(try Data(contentsOf: badge), bytes)
    }
}
