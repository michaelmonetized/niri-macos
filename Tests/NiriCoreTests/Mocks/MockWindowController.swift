import Foundation
import CoreGraphics
@testable import NiriCore

final class MockWindowController: WindowManipulating {

    // MARK: - Configurable return values

    var setFrameReturnValue: Bool = true
    var focusReturnValue: Bool = true
    var setPositionReturnValue: Bool = true
    var setSizeReturnValue: Bool = true
    var minimizeReturnValue: Bool = true

    // MARK: - Call recording

    private(set) var setFrameCalls: [(windowID: WindowID, frame: CGRect)] = []
    private(set) var focusCalls: [WindowID] = []
    private(set) var setPositionCalls: [(windowID: WindowID, position: CGPoint)] = []
    private(set) var setSizeCalls: [(windowID: WindowID, size: CGSize)] = []
    private(set) var minimizeCalls: [WindowID] = []
    private(set) var batchSetFramesCalls: [[(WindowID, CGRect)]] = []
    private(set) var clearCacheCalls: [pid_t?] = []

    // MARK: - WindowManipulating

    @discardableResult
    func setWindowFrame(_ windowID: WindowID, frame: CGRect) -> Bool {
        setFrameCalls.append((windowID: windowID, frame: frame))
        return setFrameReturnValue
    }

    @discardableResult
    func focusWindow(_ windowID: WindowID) -> Bool {
        focusCalls.append(windowID)
        return focusReturnValue
    }

    @discardableResult
    func setWindowPosition(_ windowID: WindowID, position: CGPoint) -> Bool {
        setPositionCalls.append((windowID: windowID, position: position))
        return setPositionReturnValue
    }

    @discardableResult
    func setWindowSize(_ windowID: WindowID, size: CGSize) -> Bool {
        setSizeCalls.append((windowID: windowID, size: size))
        return setSizeReturnValue
    }

    @discardableResult
    func minimizeWindow(_ windowID: WindowID) -> Bool {
        minimizeCalls.append(windowID)
        return minimizeReturnValue
    }

    func batchSetFrames(_ frames: [(WindowID, CGRect)]) {
        batchSetFramesCalls.append(frames)
    }

    func clearCache(for pid: pid_t?) {
        clearCacheCalls.append(pid)
    }

    // MARK: - Helpers

    func reset() {
        setFrameCalls.removeAll()
        focusCalls.removeAll()
        setPositionCalls.removeAll()
        setSizeCalls.removeAll()
        minimizeCalls.removeAll()
        batchSetFramesCalls.removeAll()
        clearCacheCalls.removeAll()
    }
}
