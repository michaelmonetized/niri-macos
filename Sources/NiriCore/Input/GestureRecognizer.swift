import Foundation
import CoreGraphics
import AppKit

/// Scroll action types
public enum ScrollAction {
    case horizontalWindowScroll(direction: Int)  // -1 = left, 1 = right
    case verticalWorkspaceScroll(direction: Int) // -1 = up, 1 = down
    case none
}

/// Recognizes trackpad gestures for scrolling the workspace
public class GestureRecognizer {
    public static let shared = GestureRecognizer()
    
    private let logger = Logger.shared
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Gesture state
    private var isScrolling = false
    private var scrollVelocity: CGFloat = 0
    private var lastScrollTime: TimeInterval = 0
    private var momentumTimer: Timer?
    
    // Discrete scroll accumulator (for snap-to-window behavior)
    private var horizontalScrollAccumulator: CGFloat = 0
    private var verticalScrollAccumulator: CGFloat = 0
    private let scrollThreshold: CGFloat = 25.0  // Threshold for one "click" (increased for less sensitivity)
    private var lastScrollEventTime: TimeInterval = 0
    private let scrollResetDelay: TimeInterval = 0.25  // Reset accumulator after pause
    
    // Cooldown to prevent rapid-fire triggers
    private var lastHorizontalTriggerTime: TimeInterval = 0
    private var lastVerticalTriggerTime: TimeInterval = 0
    private let triggerCooldown: TimeInterval = 0.15  // Minimum time between triggers
    
    // Configuration
    var scrollMultiplier: CGFloat = 1.5
    var momentumDecay: CGFloat = 0.95
    var minimumVelocity: CGFloat = 0.5
    var threeFingerSwipeEnabled = true
    var discreteScrollEnabled = true  // 1 click = 1 window/workspace
    
    // Modifier keys for different actions
    // Cmd+Shift+scroll = horizontal window scrolling
    // Cmd+scroll = vertical workspace scrolling
    var horizontalScrollModifiers: CGEventFlags = [.maskCommand, .maskShift]
    var workspaceScrollModifiers: CGEventFlags = [.maskCommand]
    
    // Callbacks
    public var onScroll: ((CGFloat) -> Void)?
    public var onScrollBegan: (() -> Void)?
    public var onScrollEnded: (() -> Void)?
    
    // Discrete callbacks (for snap-to-window/workspace)
    public var onFocusWindowLeft: (() -> Void)?
    public var onFocusWindowRight: (() -> Void)?
    public var onWorkspaceUp: (() -> Void)?
    public var onWorkspaceDown: (() -> Void)?
    
    // Swipe gesture callbacks
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    var onSwipeUp: (() -> Void)?
    var onSwipeDown: (() -> Void)?
    
    private init() {}
    
    // MARK: - Lifecycle
    
    public func start() {
        logger.info("Gesture recognizer starting...")
        
        // Create event tap for scroll events
        let eventMask: CGEventMask = (1 << CGEventType.scrollWheel.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let recognizer = Unmanaged<GestureRecognizer>.fromOpaque(refcon).takeUnretainedValue()
                return recognizer.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            logger.error("Failed to create event tap - accessibility permissions required")
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        logger.info("Gesture recognizer started")
    }
    
    public func stop() {
        momentumTimer?.invalidate()
        momentumTimer = nil
        
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        
        logger.info("Gesture recognizer stopped")
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Handle tap disabled events
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        
        guard type == .scrollWheel else {
            return Unmanaged.passRetained(event)
        }
        
        // Check for modifier keys
        let flags = event.flags
        let hasCommand = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasControl = flags.contains(.maskControl)
        let hasOption = flags.contains(.maskAlternate)
        
        // Determine scroll action based on modifiers:
        // Cmd+Shift+scroll = horizontal window scrolling (focus left/right)
        // Cmd+scroll = vertical workspace scrolling (workspace up/down)
        let isHorizontalWindowScroll = hasCommand && hasShift && !hasControl && !hasOption
        let isWorkspaceScroll = hasCommand && !hasShift && !hasControl && !hasOption
        
        // Get scroll data
        let deltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)  // Horizontal
        let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)  // Vertical
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        
        // Ignore momentum events for discrete scrolling
        if momentumPhase != 0 && discreteScrollEnabled {
            if isHorizontalWindowScroll || isWorkspaceScroll {
                return nil  // Consume momentum events when using our modifiers
            }
            return Unmanaged.passRetained(event)
        }
        
        // Reset accumulator if too much time has passed
        let currentTime = CACurrentMediaTime()
        if currentTime - lastScrollEventTime > scrollResetDelay {
            horizontalScrollAccumulator = 0
            verticalScrollAccumulator = 0
        }
        lastScrollEventTime = currentTime
        
        // Handle Cmd+Shift+scroll: horizontal window scrolling (discrete: 1 click = 1 window)
        if isHorizontalWindowScroll {
            if discreteScrollEnabled {
                // Accumulate scroll for discrete behavior
                // Use horizontal scroll primarily, but also accept vertical scroll converted to horizontal
                let effectiveDelta = abs(deltaX) > abs(deltaY) ? CGFloat(deltaX) : CGFloat(-deltaY)
                horizontalScrollAccumulator += effectiveDelta
                
                // Trigger focus change when threshold is reached (with cooldown)
                let canTrigger = currentTime - lastHorizontalTriggerTime >= triggerCooldown
                
                if horizontalScrollAccumulator >= scrollThreshold && canTrigger {
                    onFocusWindowRight?()
                    horizontalScrollAccumulator = 0
                    lastHorizontalTriggerTime = currentTime
                    logger.debug("Discrete scroll: focus right")
                } else if horizontalScrollAccumulator <= -scrollThreshold && canTrigger {
                    onFocusWindowLeft?()
                    horizontalScrollAccumulator = 0
                    lastHorizontalTriggerTime = currentTime
                    logger.debug("Discrete scroll: focus left")
                }
            } else {
                // Continuous scroll mode (legacy)
                let delta = CGFloat(deltaX) * scrollMultiplier
                if abs(delta) > 0.1 {
                    onScroll?(delta)
                }
            }
            return nil  // Consume the event
        }
        
        // Handle Cmd+scroll: vertical workspace scrolling (discrete: 1 click = 1 workspace)
        if isWorkspaceScroll {
            if discreteScrollEnabled {
                // Accumulate vertical scroll
                verticalScrollAccumulator += CGFloat(deltaY)
                
                // Trigger workspace change when threshold is reached (with cooldown)
                // Note: positive deltaY = scroll down = workspace down (next workspace)
                let canTrigger = currentTime - lastVerticalTriggerTime >= triggerCooldown
                
                if verticalScrollAccumulator >= scrollThreshold && canTrigger {
                    onWorkspaceDown?()
                    verticalScrollAccumulator = 0
                    lastVerticalTriggerTime = currentTime
                    logger.debug("Discrete scroll: workspace down")
                } else if verticalScrollAccumulator <= -scrollThreshold && canTrigger {
                    onWorkspaceUp?()
                    verticalScrollAccumulator = 0
                    lastVerticalTriggerTime = currentTime
                    logger.debug("Discrete scroll: workspace up")
                }
            }
            return nil  // Consume the event
        }
        
        // Handle unmodified horizontal swipes (3-finger swipe)
        let isHorizontalSwipe = abs(deltaX) > abs(deltaY) * 2 && abs(deltaX) > 0.5
        
        if threeFingerSwipeEnabled && isHorizontalSwipe && !hasCommand && !hasShift && !hasControl && !hasOption {
            // Handle scroll phases
            if phase == 1 || (momentumPhase == 0 && !isScrolling && isHorizontalSwipe) {
                // Scroll began
                isScrolling = true
                momentumTimer?.invalidate()
                onScrollBegan?()
            }
            
            if isScrolling {
                // Apply scroll (continuous mode for free scrolling)
                let delta = CGFloat(deltaX) * scrollMultiplier
                if abs(delta) > 0.1 {
                    scrollVelocity = delta
                    lastScrollTime = CACurrentMediaTime()
                    onScroll?(delta)
                }
                
                // Check for scroll end
                if phase == 4 || (momentumPhase == 0 && phase == 0 && isScrolling) {
                    // Scroll ended - start momentum
                    isScrolling = false
                    startMomentum()
                    onScrollEnded?()
                }
            }
            
            // Don't consume - let system handle native swipe
            return Unmanaged.passRetained(event)
        }
        
        return Unmanaged.passRetained(event)
    }
    
    // MARK: - Momentum Scrolling
    
    private func startMomentum() {
        guard abs(scrollVelocity) > minimumVelocity else { return }
        
        momentumTimer?.invalidate()
        momentumTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Apply momentum scroll
            if abs(self.scrollVelocity) > self.minimumVelocity {
                self.onScroll?(self.scrollVelocity)
                self.scrollVelocity *= self.momentumDecay
            } else {
                timer.invalidate()
                self.momentumTimer = nil
                self.scrollVelocity = 0
            }
        }
    }
    
    /// Cancel any ongoing momentum
    public func cancelMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
        scrollVelocity = 0
    }
}
