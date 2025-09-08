import Foundation

struct Event {
    let uid: String?
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let description: String?
    let url: URL?
    let organizer: String?
    let attendees: [String]
    let categories: [String]
    let status: EventStatus
    let created: Date?
    let lastModified: Date?
    let sequence: Int
    let fingerprint: String
}

enum EventStatus: String {
    case confirmed = "CONFIRMED"
    case tentative = "TENTATIVE"
    case cancelled = "CANCELLED"
}

