import Foundation
import CoreGraphics
import AppKit
import QuartzCore

/// Manages spring-based animations for window movements
public class AnimationController {
    public static let shared = AnimationController()
    
    private let logger = Logger.shared
    private var displayLink: CVDisplayLink?
    private var isRunning = false
    
    // Active animations
    private var windowAnimations: [WindowID: WindowAnimation] = [:]
    private var scrollAnimation: ScrollAnimation?
    private let animationQueue = DispatchQueue(label: "niri.animation", qos: .userInteractive)
    private let lock = NSLock()
    
    // Configuration
    public var config = AnimationConfig()
    
    // Callbacks
    public var onWindowFrameUpdate: ((WindowID, CGRect) -> Void)?
    public var onScrollUpdate: ((CGFloat) -> Void)?
    public var onAnimationsComplete: (() -> Void)?
    
    private init() {}
    
    // MARK: - Lifecycle
    
    public func start() {
        guard !isRunning else { return }
        
        // Create display link for smooth 60fps updates
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        
        guard let displayLink = link else {
            logger.error("Failed to create display link")
            return
        }
        
        self.displayLink = displayLink
        
        CVDisplayLinkSetOutputCallback(displayLink, { (link, now, outputTime, flags, flagsOut, context) -> CVReturn in
            guard let context = context else { return kCVReturnSuccess }
            let controller = Unmanaged<AnimationController>.fromOpaque(context).takeUnretainedValue()
            controller.tick()
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        
        CVDisplayLinkStart(displayLink)
        isRunning = true
        
        logger.info("Animation controller started")
    }
    
    public func stop() {
        guard isRunning else { return }
        
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil
        isRunning = false
        
        lock.lock()
        windowAnimations.removeAll()
        scrollAnimation = nil
        lock.unlock()
        
        logger.info("Animation controller stopped")
    }
    
    // MARK: - Animation API
    
    /// Animate a window to a target frame
    public func animateWindow(_ windowID: WindowID, to targetFrame: CGRect, from currentFrame: CGRect? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        let startFrame = currentFrame ?? windowAnimations[windowID]?.currentFrame ?? targetFrame
        
        // If already animating, preserve velocity
        let existingVelocity = windowAnimations[windowID]?.velocity ?? .zero
        
        windowAnimations[windowID] = WindowAnimation(
            startFrame: startFrame,
            targetFrame: targetFrame,
            currentFrame: startFrame,
            velocity: existingVelocity,
            spring: config.horizontalMovement
        )
    }
    
    /// Animate scroll offset
    public func animateScroll(to target: CGFloat, from current: CGFloat? = nil) {
        lock.lock()
        defer { lock.unlock() }
        
        let startValue = current ?? scrollAnimation?.currentValue ?? target
        let existingVelocity = scrollAnimation?.velocity ?? 0
        
        scrollAnimation = ScrollAnimation(
            startValue: startValue,
            targetValue: target,
            currentValue: startValue,
            velocity: existingVelocity,
            spring: config.workspaceSwitch
        )
    }
    
    /// Set window frame immediately (no animation)
    public func setWindowImmediate(_ windowID: WindowID, frame: CGRect) {
        lock.lock()
        windowAnimations.removeValue(forKey: windowID)
        lock.unlock()
        
        DispatchQueue.main.async { [weak self] in
            self?.onWindowFrameUpdate?(windowID, frame)
        }
    }
    
    /// Set scroll offset immediately (no animation)
    func setScrollImmediate(_ value: CGFloat) {
        lock.lock()
        scrollAnimation = nil
        lock.unlock()
        
        DispatchQueue.main.async { [weak self] in
            self?.onScrollUpdate?(value)
        }
    }
    
    /// Cancel all animations
    public func cancelAll() {
        lock.lock()
        windowAnimations.removeAll()
        scrollAnimation = nil
        lock.unlock()
    }
    
    /// Cancel animation for specific window
    public func cancelWindow(_ windowID: WindowID) {
        lock.lock()
        windowAnimations.removeValue(forKey: windowID)
        lock.unlock()
    }
    
    /// Check if any animations are running
    public var hasActiveAnimations: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !windowAnimations.isEmpty || scrollAnimation != nil
    }
    
    // MARK: - Animation Tick
    
    private func tick() {
        let dt: TimeInterval = Constants.animationFrameInterval
        
        lock.lock()
        
        var framesToUpdate: [(WindowID, CGRect)] = []
        var scrollToUpdate: CGFloat?
        var animationsRemoved = false
        
        // Update window animations
        for (windowID, var animation) in windowAnimations {
            animation.step(dt: dt, springConfig: config.horizontalMovement)
            windowAnimations[windowID] = animation
            
            if animation.isSettled {
                framesToUpdate.append((windowID, animation.targetFrame))
                windowAnimations.removeValue(forKey: windowID)
                animationsRemoved = true
            } else {
                framesToUpdate.append((windowID, animation.currentFrame))
            }
        }
        
        // Update scroll animation
        if var scroll = scrollAnimation {
            scroll.step(dt: dt, springConfig: config.workspaceSwitch)
            scrollAnimation = scroll
            
            if scroll.isSettled {
                scrollToUpdate = scroll.targetValue
                scrollAnimation = nil
                animationsRemoved = true
            } else {
                scrollToUpdate = scroll.currentValue
            }
        }
        
        let shouldNotifyComplete = animationsRemoved && windowAnimations.isEmpty && scrollAnimation == nil

        // Capture callback references under lock to prevent TOCTOU races
        let windowCallback = self.onWindowFrameUpdate
        let scrollCallback = self.onScrollUpdate
        let completeCallback = shouldNotifyComplete ? self.onAnimationsComplete : nil

        lock.unlock()

        // Dispatch updates to main thread using captured callbacks
        DispatchQueue.main.async {
            for (windowID, frame) in framesToUpdate {
                windowCallback?(windowID, frame)
            }

            if let scroll = scrollToUpdate {
                scrollCallback?(scroll)
            }

            completeCallback?()
        }
    }
}

// MARK: - Animation Types

struct WindowAnimation {
    var startFrame: CGRect
    var targetFrame: CGRect
    var currentFrame: CGRect
    var velocity: CGPoint
    var spring: SpringConfig
    
    var isSettled: Bool {
        let positionSettled = abs(currentFrame.origin.x - targetFrame.origin.x) < Constants.animationSettledThreshold &&
                              abs(currentFrame.origin.y - targetFrame.origin.y) < Constants.animationSettledThreshold
        let sizeSettled = abs(currentFrame.width - targetFrame.width) < Constants.animationSettledThreshold &&
                          abs(currentFrame.height - targetFrame.height) < Constants.animationSettledThreshold
        let velocitySettled = abs(velocity.x) < Constants.animationSettledThreshold && abs(velocity.y) < Constants.animationSettledThreshold
        return positionSettled && sizeSettled && velocitySettled
    }
    
    mutating func step(dt: TimeInterval, springConfig: SpringConfig) {
        // Animate X
        let (newX, newVelX) = springStep(
            current: currentFrame.origin.x,
            target: targetFrame.origin.x,
            velocity: velocity.x,
            dt: dt,
            config: springConfig
        )
        
        // Animate Y
        let (newY, newVelY) = springStep(
            current: currentFrame.origin.y,
            target: targetFrame.origin.y,
            velocity: velocity.y,
            dt: dt,
            config: springConfig
        )
        
        // Animate width (using same spring)
        let (newWidth, _) = springStep(
            current: currentFrame.width,
            target: targetFrame.width,
            velocity: 0,
            dt: dt,
            config: springConfig
        )
        
        // Animate height
        let (newHeight, _) = springStep(
            current: currentFrame.height,
            target: targetFrame.height,
            velocity: 0,
            dt: dt,
            config: springConfig
        )
        
        currentFrame = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
        velocity = CGPoint(x: newVelX, y: newVelY)
    }
}

struct ScrollAnimation {
    var startValue: CGFloat
    var targetValue: CGFloat
    var currentValue: CGFloat
    var velocity: CGFloat
    var spring: SpringConfig
    
    var isSettled: Bool {
        abs(currentValue - targetValue) < Constants.animationSettledThreshold && abs(velocity) < Constants.animationSettledThreshold
    }
    
    mutating func step(dt: TimeInterval, springConfig: SpringConfig) {
        let (newValue, newVelocity) = springStep(
            current: currentValue,
            target: targetValue,
            velocity: velocity,
            dt: dt,
            config: springConfig
        )
        currentValue = newValue
        velocity = newVelocity
    }
}

// MARK: - Spring Physics

private func springStep(
    current: CGFloat,
    target: CGFloat,
    velocity: CGFloat,
    dt: TimeInterval,
    config: SpringConfig
) -> (CGFloat, CGFloat) {
    let displacement = current - target
    let springForce = -config.stiffness * displacement
    let dampingForce = -config.damping * velocity * 2 * sqrt(config.stiffness * config.mass)
    let acceleration = (springForce + dampingForce) / config.mass
    
    var newVelocity = velocity + acceleration * dt
    var newPosition = current + newVelocity * dt
    
    // Snap to target if close enough
    if abs(newPosition - target) < config.epsilon && abs(newVelocity) < config.epsilon {
        newPosition = target
        newVelocity = 0
    }
    
    return (newPosition, newVelocity)
}

// MARK: - CGPoint Extension

extension CGPoint {
    static var zero: CGPoint { CGPoint(x: 0, y: 0) }
}
