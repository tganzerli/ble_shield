import Foundation

final class BleShieldNativeLogger {
  static let shared = BleShieldNativeLogger()

  private init() {}

  private lazy var dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter
  }()

  private var currentLogLevel: BleLogLevel = .none

  func setLogLevel(_ logLevel: BleLogLevel) {
    currentLogLevel = logLevel
  }

  func logError(_ message: String) {
    guard allows(.error) else { return }
    print("BleShieldNative:ERROR \(withTimestamp(message))")
  }

  func logWarning(_ message: String) {
    guard allows(.warning) else { return }
    print("BleShieldNative:WARN \(withTimestamp(message))")
  }

  func logInfo(_ message: String) {
    guard allows(.info) else { return }
    print("BleShieldNative:INFO \(withTimestamp(message))")
  }

  func logDebug(_ message: String) {
    guard allows(.debug) else { return }
    print("BleShieldNative:DEBUG \(withTimestamp(message))")
  }

  func logVerbose(_ message: String) {
    guard allows(.verbose) else { return }
    print("BleShieldNative:VERBOSE \(withTimestamp(message))")
  }

  private func allows(_ level: BleLogLevel) -> Bool {
    return currentLogLevel != .none && level.rawValue <= currentLogLevel.rawValue
  }

  private func withTimestamp(_ message: String) -> String {
    let time = dateFormatter.string(from: Date())
    return "[\(time)] \(message)"
  }
}
