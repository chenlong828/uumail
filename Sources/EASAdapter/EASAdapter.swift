import EASClient
import Foundation
import MailDomain
import MeetingDomain
import SyncContract

/// Adapts the EAS client to the domain gateway port. This is the anti-corruption
/// point: EAS status codes become `MailError` here and nowhere else.
public struct EASAdapter: MailGateway, MailWriteGateway {
    public let client: EASClient
    public init(client: EASClient) { self.client = client }

    public func probe() async throws -> ServerCapabilities {
        do {
            let capabilities = try await client.options()
            return ServerCapabilities(
                protocolVersions: capabilities.protocolVersions,
                commands: capabilities.commands
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func provisionIfNeeded() async throws {
        if await client.currentPolicyKey() == nil {
            do {
                _ = try await client.provision()
            } catch {
                throw Self.map(error)
            }
        }
    }

    public func fetchFolders(syncKey: String) async throws -> FolderListing {
        do {
            let result = try await client.folderSync(syncKey: syncKey)
            return FolderListing(
                folders: result.folders.map {
                    Folder(
                        serverID: $0.serverID,
                        parentID: $0.parentID,
                        displayName: $0.displayName,
                        type: $0.type
                    )
                },
                syncKey: result.syncKey
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta {
        do {
            let result = try await client.sync(
                collectionID: collectionID, syncKey: syncKey, window: window, filterType: filterType
            )
            return Self.delta(result)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - Write port

    public func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        do {
            let result = try await client.sync(
                collectionID: collectionID,
                syncKey: syncKey,
                change: .read(serverID: serverID)
            )
            return Self.delta(result)
        } catch {
            throw Self.map(error)
        }
    }

    public func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        do {
            let result = try await client.sync(
                collectionID: collectionID,
                syncKey: syncKey,
                change: .delete(serverID: serverID)
            )
            return Self.delta(result)
        } catch {
            throw Self.map(error)
        }
    }

    /// Read and write responses share one shape; both keep every field the server sent.
    private static func delta(_ result: SyncResult) -> MessageDelta {
        let meetings = (result.added + result.changed).compactMap { message -> MeetingDeltaEntry? in
            guard let invite = meeting(message) else { return nil }
            return MeetingDeltaEntry(serverID: message.serverID, subject: message.subject, invite: invite)
        }
        return MessageDelta(
            added: result.added.map(Self.message),
            changed: result.changed.map(Self.message),
            removedServerIDs: result.removedServerIDs,
            syncKey: result.syncKey,
            moreAvailable: result.moreAvailable,
            meetings: meetings
        )
    }

    /// Keeps the gateway's own flags: `EASClient` already retries a truncated body
    /// without a cap, but the server can still answer short — the scene turns that
    /// into the "正文过长" note.
    public func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody {
        do {
            let fetched = try await client.fetchBody(collectionID: collectionID, serverID: serverID)
            return FetchedBody(
                text: fetched.payload,
                isHTML: fetched.isHTML,
                isTruncated: fetched.isTruncated
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func fetchAttachment(fileReference: String) async throws -> Data {
        do {
            return try await client.fetchAttachment(fileReference: fileReference)
        } catch {
            throw Self.map(error)
        }
    }

    public func send(mime: Data, clientID: String) async throws {
        do {
            try await client.send(mime: mime, clientID: clientID)
        } catch {
            throw Self.map(error)
        }
    }

    static func message(_ message: EASMessage) -> Message {
        Message(
            serverID: message.serverID,
            subject: message.subject,
            sender: message.from,
            recipients: message.to,
            receivedRaw: message.dateReceived,
            isRead: message.isRead ?? false,
            importance: message.importance,
            bodyPreview: message.bodyPreview,
            attachments: message.attachments.map {
                Attachment(
                    displayName: $0.displayName,
                    fileReference: $0.fileReference,
                    size: $0.size,
                    contentID: $0.contentID
                )
            },
            cc: message.cc
        )
    }

    /// Maps an EAS meeting request onto the domain value; `nil` for plain mail, cancelled
    /// requests stay as a meeting flagged `isCancelled` so the store can delete the row.
    static func meeting(_ message: EASMessage) -> MeetingInvite? {
        guard let meetingClass = message.messageClass,
              meetingClass.hasPrefix("IPM.Schedule.Meeting."),
              let eas = message.meeting,
              let uid = eas.uid, !uid.isEmpty,
              let start = eas.start,
              let end = eas.end
        else { return nil }

        let cancelled = meetingClass == "IPM.Schedule.Meeting.Canceled"
        let frequency: RecurrenceRule.Frequency? = eas.recurrence.flatMap {
            switch $0.type {
            case 0: .daily
            case 1: .weekly
            case 2: .monthlyDay
            case 3: .monthlyWeekday
            case 5: .yearlyDay
            case 6: .yearlyWeekday
            default: nil
            }
        }
        let rule = eas.recurrence.flatMap { recurrence -> RecurrenceRule? in
            guard let frequency, eas.instanceType != 3 else { return nil }
            let mask = recurrence.daysOfWeek ?? 0
            return RecurrenceRule(
                frequency: frequency,
                interval: max(1, recurrence.interval ?? 1),
                until: recurrence.until,
                occurrences: recurrence.occurrences,
                weekdays: Weekday.set(fromMask: mask),
                dayOfMonth: recurrence.dayOfMonth,
                weekOfMonth: recurrence.weekOfMonth,
                monthOfYear: recurrence.monthOfYear,
                firstDayOfWeek: Weekday.calendarWeekday(recurrence.firstDayOfWeek),
                lastDayOfMonth: mask == 127
            )
        }
        return MeetingInvite(
            uid: uid,
            subject: message.subject,
            start: start,
            end: end,
            isAllDay: eas.allDay,
            location: eas.location,
            organizer: eas.organizer,
            reminderMinutes: eas.reminderMinutes,
            responseRequested: eas.responseRequested,
            busyStatus: eas.busyStatus,
            messageType: MeetingMessageType(rawValue: eas.messageType ?? 1) ?? .initial,
            isCancelled: cancelled,
            dtstamp: eas.dtstamp,
            timeZone: eas.timeZone.map {
                MeetingTimeZone(name: $0.name, offsetSeconds: -$0.biasMinutes * 60)
            },
            recurrence: rule,
            exceptionRecurrenceID: eas.instanceType == 3 ? eas.recurrenceId : nil
        )
    }

    /// The single EAS → domain error mapping. Nothing above this layer sees `EASError`.
    public static func map(_ error: Error) -> MailError {
        guard let eas = error as? EASError else {
            return .offline
        }
        switch eas {
        case .authFailed: return .authFailed
        case .deviceNotRegistered: return .deviceNotRegistered
        case .policyRequired: return .policyBlocked
        case .syncKeyInvalid: return .syncKeyInvalid
        case .throttled(let after): return .throttled(seconds: after)
        case .transient: return .offline
        case .gatewayRejected, .protocolRejected, .permanent, .malformedResponse:
            return .unsupported
        }
    }
}

// MARK: - Drafts (REQ-0044)

extension EASAdapter {
    public func createDraft(
        _ payload: DraftPayload, collectionID: String, syncKey: String, clientID: String
    ) async throws -> DraftWriteResult {
        do {
            let result = try await client.createDraft(
                Self.draft(payload), collectionID: collectionID,
                syncKey: syncKey, clientID: clientID
            )
            return DraftWriteResult(serverID: result.serverID, syncKey: result.syncKey)
        } catch {
            throw Self.map(error)
        }
    }

    public func updateDraft(
        serverID: String, payload: DraftPayload, collectionID: String, syncKey: String
    ) async throws -> DraftWriteResult {
        do {
            let result = try await client.updateDraft(
                serverID: serverID, draft: Self.draft(payload),
                collectionID: collectionID, syncKey: syncKey
            )
            return DraftWriteResult(serverID: result.serverID, syncKey: result.syncKey)
        } catch {
            throw Self.map(error)
        }
    }

    public func deleteDraft(
        serverID: String, collectionID: String, syncKey: String
    ) async throws -> DraftWriteResult {
        do {
            let result = try await client.deleteDraft(
                serverID: serverID, collectionID: collectionID, syncKey: syncKey
            )
            return DraftWriteResult(serverID: result.serverID, syncKey: result.syncKey)
        } catch {
            throw Self.map(error)
        }
    }

    private static func draft(_ payload: DraftPayload) -> EASDraft {
        EASDraft(
            to: payload.to, cc: payload.cc,
            subject: payload.subject, bodyHTML: payload.bodyHTML
        )
    }
}
