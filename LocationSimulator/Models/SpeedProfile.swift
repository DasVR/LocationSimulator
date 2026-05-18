enum SpeedProfile: Hashable, CaseIterable {
    case walking
    case biking
    case driving
    case custom(speed: Double) // m/s

    static var allCases: [SpeedProfile] {
        [.walking, .biking, .driving, .custom(speed: 0)]
    }

    var defaultSpeed: Double { // m/s
        switch self {
        case .walking: return 1.4   // ~5 km/h
        case .biking: return 4.2    // ~15 km/h
        case .driving: return 13.9  // ~50 km/h
        case .custom(let speed): return speed
        }
    }

    var displayName: String {
        switch self {
        case .walking: return "Walking"
        case .biking: return "Biking"
        case .driving: return "Driving"
        case .custom: return "Custom"
        }
    }
}
