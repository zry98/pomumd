//
//  LogManager.swift
//  pomumd
//
//  Manages log retrieval using AsyncStream for efficient polling.
//  Replaces timer-based polling with stream-based approach.
//

import Foundation
import OSLog
import Combine

/// Manages log retrieval and monitoring with AsyncStream
@MainActor
class LogManager: ObservableObject {
    @Published private(set) var logs: [OSLogEntryLog] = []

    private var lastFetchTime: Date?
    private let maxLogCount = 10_000
    private var streamTask: Task<Void, Never>?
    private var consumeTask: Task<Void, Never>?
    private var continuation: AsyncStream<[OSLogEntryLog]>.Continuation?

    // MARK: - Monitoring Control

    /// Start monitoring logs with AsyncStream
    func startMonitoring(interval: TimeInterval = 5.0) {
        // Stop any existing monitoring
        stopMonitoring()

        let (stream, continuation) = AsyncStream.makeStream(of: [OSLogEntryLog].self)
        self.continuation = continuation

        // Task to poll logs at intervals
        streamTask = Task {
            while !Task.isCancelled {
                do {
                    let newLogs = try LogStoreAccess.retrieveLogs(
                        since: lastFetchTime,
                        maxCount: 5000
                    )

                    if !newLogs.isEmpty {
                        continuation.yield(newLogs)
                    }

                    lastFetchTime = Date()
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    // Continue monitoring even if one fetch fails
                    continue
                }
            }
            continuation.finish()
        }

        // Task to consume stream
        consumeTask = Task {
            for await newLogs in stream {
                await appendLogs(newLogs)
            }
        }
    }

    /// Stop monitoring logs
    func stopMonitoring() {
        streamTask?.cancel()
        consumeTask?.cancel()
        continuation?.finish()
        streamTask = nil
        consumeTask = nil
        continuation = nil
    }

    // MARK: - Log Management

    /// Append new logs with deduplication
    private func appendLogs(_ newLogs: [OSLogEntryLog]) {
        // Deduplicate using composite key (timestamp + message hash)
        let existingKeys = Set(logs.map { logKey($0) })
        let uniqueNewLogs = newLogs.filter { !existingKeys.contains(logKey($0)) }

        logs.append(contentsOf: uniqueNewLogs)

        // Prune if exceeding limit
        if logs.count > maxLogCount {
            logs.removeFirst(logs.count - maxLogCount)
        }
    }

    /// Generate composite key for deduplication
    private func logKey(_ log: OSLogEntryLog) -> String {
        // Composite key: timestamp + message hash for better deduplication
        return "\(log.date.timeIntervalSince1970)_\(log.composedMessage.hashValue)"
    }

    /// Clear all logs
    func clearLogs() {
        logs.removeAll()
        lastFetchTime = nil
    }
}
