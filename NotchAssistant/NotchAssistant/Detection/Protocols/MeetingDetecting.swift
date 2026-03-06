import Foundation

protocol MeetingDetecting: Sendable {
    func detectActiveMeeting() async -> Bool
    var isMeetingActive: Bool { get async }
}
