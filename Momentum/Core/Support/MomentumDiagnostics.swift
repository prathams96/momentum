import OSLog

enum MomentumDiagnostics {
    static let signposter = OSSignposter(
        subsystem: "com.pratham.momentum",
        category: "Performance"
    )
}
