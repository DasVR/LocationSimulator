struct SpeedGradient: Equatable {
    let fromRatio: Double // 0.0 - 1.0 (start of gradient along route)
    let toRatio: Double   // 0.0 - 1.0 (end of gradient along route)
    let targetSpeed: Double // m/s

    var isValid: Bool {
        fromRatio >= 0 && toRatio <= 1 && fromRatio < toRatio
    }
}
