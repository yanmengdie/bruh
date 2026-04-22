import Foundation

enum MessageThreadReadState {
    static func markRead(thread: MessageThread, at date: Date?) {
        if let date {
            let existing = thread.lastReadAt ?? .distantPast
            if date > existing {
                thread.lastReadAt = date
            }
        }
        thread.unreadCount = 0
        thread.updatedAt = .now
    }

    static func unreadCountsByThreadId(
        threads: [MessageThread],
        deliveries: [ContentDelivery]
    ) -> [String: Int] {
        let canonicalThreadIdByLookupKey = threadIdLookupMap(for: threads)
        let readCutoffByThreadId = Dictionary(
            uniqueKeysWithValues: threads.map { ($0.id, $0.lastReadAt ?? .distantPast) }
        )
        var counts: [String: Int] = [:]

        for delivery in deliveries {
            guard let threadId = canonicalThreadId(
                for: delivery,
                canonicalThreadIdByLookupKey: canonicalThreadIdByLookupKey
            ) else {
                continue
            }
            guard delivery.sortDate > (readCutoffByThreadId[threadId] ?? .distantPast) else {
                continue
            }
            counts[threadId, default: 0] += 1
        }

        return counts
    }

    static func unreadCount(for thread: MessageThread, deliveries: [ContentDelivery]) -> Int {
        unreadCountsByThreadId(threads: [thread], deliveries: deliveries)[thread.id]
            ?? max(0, thread.unreadCount)
    }

    private static func threadIdLookupMap(for threads: [MessageThread]) -> [String: String] {
        var threadIdsByLookupKey: [String: String] = [:]

        for thread in threads {
            for key in uniqueLookupKeys([thread.id, thread.personaId]) where threadIdsByLookupKey[key] == nil {
                threadIdsByLookupKey[key] = thread.id
            }
        }

        return threadIdsByLookupKey
    }

    private static func canonicalThreadId(
        for delivery: ContentDelivery,
        canonicalThreadIdByLookupKey: [String: String]
    ) -> String? {
        for key in uniqueLookupKeys([delivery.threadId, delivery.personaId]) {
            if let threadId = canonicalThreadIdByLookupKey[key] {
                return threadId
            }
        }
        return nil
    }

    private static func uniqueLookupKeys(_ rawValues: [String?]) -> [String] {
        var seen: Set<String> = []
        var keys: [String] = []

        for rawValue in rawValues {
            guard let key = normalizedLookupKey(rawValue), seen.insert(key).inserted else {
                continue
            }
            keys.append(key)
        }

        return keys
    }

    private static func normalizedLookupKey(_ rawValue: String?) -> String? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        return rawValue
    }
}
