enum PipLoadState {
    case loading
    case ready
    case failed

    var description: String {
        switch self {
        case .loading: "Loading 3D"
        case .ready: "3D"
        case .failed: "Static preview"
        }
    }
}
