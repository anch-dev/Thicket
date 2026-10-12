import GameController
import ThicketCore
import ThicketKit

/// Game controllers and hardware keyboards via GameController.framework.
///
/// State is *polled* every tick (so a lost "button up" can never leave a button
/// stuck), and change handlers additionally latch presses that start and end
/// between two polls.
final class HardwareInput {
    private var detectors = [EdgeDetector(), EdgeDetector()]
    /// Last state seen by each controller's change handler, to latch only new presses.
    private var handlerState: [Buttons] = [[], []]
    private var versusMode = false
    private var observers: [NSObjectProtocol] = []
    /// Called on any controller press (used to hide touch controls).
    var onActivity: (() -> Void)?

    init() {
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect,
                     .GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.installHandlers()
                self?.reset()
            })
        }
        installHandlers()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    var controllers: [GCController] {
        GCController.controllers().filter { $0.extendedGamepad != nil || $0.microGamepad != nil }
    }

    var hasController: Bool { !controllers.isEmpty }
    var hasKeyboard: Bool { GCKeyboard.coalesced != nil }

    func reset() {
        for i in detectors.indices { detectors[i].reset() }
        handlerState = [[], []]
    }

    private func installHandlers() {
        for (i, c) in controllers.prefix(2).enumerated() {
            if let pad = c.extendedGamepad {
                pad.valueChangedHandler = { [weak self] gp, _ in
                    guard let self else { return }
                    let now = Self.buttons(gp)
                    let newlyPressed = now.subtracting(self.handlerState[i])
                    self.handlerState[i] = now
                    if !newlyPressed.isEmpty {
                        self.detectors[self.versusMode ? i : 0].notePress(newlyPressed)
                        self.onActivity?()
                    }
                }
            } else if let micro = c.microGamepad {
                micro.valueChangedHandler = { [weak self] gp, _ in
                    guard let self else { return }
                    let now = Self.buttons(micro: gp)
                    let newlyPressed = now.subtracting(self.handlerState[i])
                    self.handlerState[i] = now
                    if !newlyPressed.isEmpty {
                        self.detectors[self.versusMode ? i : 0].notePress(newlyPressed)
                    }
                }
            }
        }
        if let kb = GCKeyboard.coalesced?.keyboardInput {
            kb.keyChangedHandler = { [weak self] _, _, code, pressed in
                guard let self, pressed else { return }
                let key = Int(code.rawValue)
                if self.versusMode {
                    if let b = KeyMap.versusP1[key] { self.detectors[0].notePress(b) }
                    if let b = KeyMap.versusP2[key] { self.detectors[1].notePress(b) }
                } else if let b = KeyMap.solo[key] {
                    self.detectors[0].notePress(b)
                }
                self.onActivity?()
            }
        }
    }

    static func buttons(_ gp: GCExtendedGamepad) -> Buttons {
        var b: Buttons = []
        let stick = gp.leftThumbstick
        if gp.dpad.up.isPressed || stick.yAxis.value > 0.5 { b.insert(.up) }
        if gp.dpad.down.isPressed || stick.yAxis.value < -0.5 { b.insert(.down) }
        if gp.dpad.left.isPressed || stick.xAxis.value < -0.5 { b.insert(.left) }
        if gp.dpad.right.isPressed || stick.xAxis.value > 0.5 { b.insert(.right) }
        // South face button = A, east = B, west/north = A+B.
        if gp.buttonA.isPressed { b.insert(.a) }
        if gp.buttonB.isPressed { b.insert(.b) }
        if gp.buttonX.isPressed || gp.buttonY.isPressed { b.formUnion([.a, .b]) }
        if gp.buttonMenu.isPressed { b.insert(.pause) }
        if gp.buttonOptions?.isPressed == true { b.insert(.start) }
        return b
    }

    static func buttons(micro gp: GCMicroGamepad) -> Buttons {
        var b: Buttons = []
        if gp.dpad.up.isPressed { b.insert(.up) }
        if gp.dpad.down.isPressed { b.insert(.down) }
        if gp.dpad.left.isPressed { b.insert(.left) }
        if gp.dpad.right.isPressed { b.insert(.right) }
        if gp.buttonA.isPressed { b.insert(.a) }
        if gp.buttonX.isPressed { b.insert(.b) }
        if gp.buttonMenu.isPressed { b.insert(.pause) }
        return b
    }

    private func keyboardHeld(_ map: [Int: Buttons]) -> Buttons {
        guard let kb = GCKeyboard.coalesced?.keyboardInput else { return [] }
        var b: Buttons = []
        for (code, buttons) in map where kb.button(forKeyCode: GCKeyCode(rawValue: code))?.isPressed == true {
            b.formUnion(buttons)
        }
        return b
    }

    /// Polls all devices. In versus, controller 1 and the left half of the
    /// keyboard drive player 1; controller 2 and the right half drive player 2.
    func poll(versus: Bool) -> [SourceState] {
        versusMode = versus
        let pads = controllers
        var held: [Buttons] = [[], []]
        for (i, c) in pads.prefix(2).enumerated() {
            if let pad = c.extendedGamepad {
                held[versus ? i : 0].formUnion(Self.buttons(pad))
            } else if let micro = c.microGamepad {
                held[versus ? i : 0].formUnion(Self.buttons(micro: micro))
            }
        }
        if versus {
            held[0].formUnion(keyboardHeld(KeyMap.versusP1))
            held[1].formUnion(keyboardHeld(KeyMap.versusP2))
        } else {
            held[0].formUnion(keyboardHeld(KeyMap.solo))
        }
        return [detectors[0].frame(held: held[0]), detectors[1].frame(held: held[1])]
    }
}
