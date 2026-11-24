import Foundation

// MARK: - Configuration

public struct EASConfiguration: Sendable {
    public var host: String
    /// Account used in the `User` query parameter. Must NOT carry the domain.
    public var account: String
    public var password: String
    /// Domain used only in the `Authorization` header (`DOMAIN\account`).
    public var domain: String
    /// A device id already registered and activated by the access gateway.
    public var deviceID: String
    public var deviceType: String
    public var protocolVersion: String
    /// Only for internal CAs. Off by default; enabling it disables TLS verification.
    public var allowInsecureTLS: Bool

    public init(
        host: String,
        account: String,
        password: String,
        domain: String,
        deviceID: String,
        deviceType: String = "iPhone",
        protocolVersion: String = "16.1",
        allowInsecureTLS: Bool = false
    ) {
        self.host = host
        self.account = account
        self.password = password
        self.domain = domain
        self.deviceID = deviceID
        self.deviceType = deviceType
        self.protocolVersion = protocolVersion
        self.allowInsecureTLS = allowInsecureTLS
    }

    var authorizationHeader: String {
        let user = domain.isEmpty ? account : "\(domain)\\\(account)"
        let token = Data("\(user):\(password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    var endpoint: URL {
        URL(string: "https://\(host)/Microsoft-Server-ActiveSync")!
    }
}

// MARK: - Errors

public enum EASError: Error, Equatable, Sendable {
    case authFailed
    /// `200` with a zero-byte body: the gateway swallowed the request because the
    /// device is not registered/activated. Never retry this one.
    case deviceNotRegistered
    /// `444`: the gateway closed the connection — missing Cmd/User/DeviceId/DeviceType.
    case gatewayRejected
    case policyRequired(status: Int, message: String?)
    /// `502` after a long hang: the request body's wire format was rejected.
    case protocolRejected(detail: String)
    case syncKeyInvalid
    case throttled(retryAfterSeconds: Int?)
    case transient(reason: String)
    case permanent(status: Int, detail: String?)
    case malformedResponse(String)
}

// MARK: - Values

public struct EASFolder: Equatable, Sendable {
    public let serverID: String
    public let parentID: String?
    public let displayName: String
    public let type: Int

    public init(serverID: String, parentID: String?, displayName: String, type: Int) {
        self.serverID = serverID
        self.parentID = parentID
        self.displayName = displayName
        self.type = type
    }
}

public struct FolderSyncResult: Equatable, Sendable {
    public let folders: [EASFolder]
    public let syncKey: String
}

public struct EASAttachment: Equatable, Sendable {
    public var displayName: String
    public var fileReference: String
    public var size: Int?
    /// `ContentId`: the MIME content id the body's `cid:` references point at.
    public var contentID: String?

    public init(displayName: String, fileReference: String, size: Int?, contentID: String? = nil) {
        self.displayName = displayName
        self.fileReference = fileReference
        self.size = size
        self.contentID = contentID
    }
}

/// One meeting request carried by an e-mail (`MeetingRequest`, MS-ASEMAIL 2.2.2.48).
/// Dates are already UTC in the wire format; the time zone blob only supplies the
/// organizer's display name and fixed bias (DST rules are not parsed, see CMP-EAS spec).
public struct EASMeetingTimeZone: Equatable, Sendable {
    public var name: String?
    /// Minutes between UTC and local time with the opposite sign (`-480` = UTC+8).
    public var biasMinutes: Int

    public init(name: String? = nil, biasMinutes: Int) {
        self.name = name
        self.biasMinutes = biasMinutes
    }
}

/// The `Recurrences/Recurrence` pattern of a meeting request (MS-ASCAL 2.2.2.37).
/// `type` is 0/1/2/3/5/6 — value 4 does not exist.
public struct EASRecurrence: Equatable, Sendable {
    public var type: Int
    public var interval: Int?
    public var until: Date?
    public var occurrences: Int?
    public var daysOfWeek: Int?
    public var dayOfMonth: Int?
    public var weekOfMonth: Int?
    public var monthOfYear: Int?
    public var firstDayOfWeek: Int?

    public init(
        type: Int,
        interval: Int? = nil,
        until: Date? = nil,
        occurrences: Int? = nil,
        daysOfWeek: Int? = nil,
        dayOfMonth: Int? = nil,
        weekOfMonth: Int? = nil,
        monthOfYear: Int? = nil,
        firstDayOfWeek: Int? = nil
    ) {
        self.type = type
        self.interval = interval
        self.until = until
        self.occurrences = occurrences
        self.daysOfWeek = daysOfWeek
        self.dayOfMonth = dayOfMonth
        self.weekOfMonth = weekOfMonth
        self.monthOfYear = monthOfYear
        self.firstDayOfWeek = firstDayOfWeek
    }
}

public struct EASMeeting: Equatable, Sendable {
    public var uid: String?
    public var start: Date?
    public var end: Date?
    public var allDay: Bool
    public var dtstamp: Date?
    public var location: String?
    public var organizer: String?
    public var reminderMinutes: Int?
    public var responseRequested: Bool
    public var busyStatus: Int?
    /// 1 initial / 2 full update / 3 informational / 4 outdated / 5 delegator copy / 6 delegated.
    public var messageType: Int?
    /// 0 single / 1 recurring master / 2 single instance / 3 exception / 4 orphan instance.
    public var instanceType: Int?
    /// Original start (UTC) of the instance an exception replaces.
    public var recurrenceId: Date?
    public var timeZone: EASMeetingTimeZone?
    public var recurrence: EASRecurrence?

    public init(
        uid: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        allDay: Bool = false,
        dtstamp: Date? = nil,
        location: String? = nil,
        organizer: String? = nil,
        reminderMinutes: Int? = nil,
        responseRequested: Bool = false,
        busyStatus: Int? = nil,
        messageType: Int? = nil,
        instanceType: Int? = nil,
        recurrenceId: Date? = nil,
        timeZone: EASMeetingTimeZone? = nil,
        recurrence: EASRecurrence? = nil
    ) {
        self.uid = uid
        self.start = start
        self.end = end
        self.allDay = allDay
        self.dtstamp = dtstamp
        self.location = location
        self.organizer = organizer
        self.reminderMinutes = reminderMinutes
        self.responseRequested = responseRequested
        self.busyStatus = busyStatus
        self.messageType = messageType
        self.instanceType = instanceType
        self.recurrenceId = recurrenceId
        self.timeZone = timeZone
        self.recurrence = recurrence
    }
}

public struct EASMessage: Equatable, Sendable {
    public var serverID: String
    public var subject: String?
    public var from: String?
    public var to: String?
    public var cc: String?
    public var dateReceived: String?
    public var isRead: Bool?
    public var importance: Int?
    public var bodyPreview: String?
    public var attachments: [EASAttachment] = []
    /// `IPM.Schedule.Meeting.Request`, `…Canceled`, `IPM.Note`, …; nil when absent.
    public var messageClass: String?
    /// Present only when the message is a meeting request (MS-ASEMAIL 2.2.2.48).
    public var meeting: EASMeeting?

    public init(
        serverID: String,
        subject: String? = nil,
        from: String? = nil,
        to: String? = nil,
        dateReceived: String? = nil,
        isRead: Bool? = nil,
        importance: Int? = nil,
        bodyPreview: String? = nil,
        attachments: [EASAttachment] = [],
        cc: String? = nil,
        messageClass: String? = nil,
        meeting: EASMeeting? = nil
    ) {
        self.serverID = serverID
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.dateReceived = dateReceived
        self.isRead = isRead
        self.importance = importance
        self.bodyPreview = bodyPreview
        self.attachments = attachments
        self.messageClass = messageClass
        self.meeting = meeting
    }
}

public struct SyncResult: Equatable, Sendable {
    public var added: [EASMessage]
    public var changed: [EASMessage]
    public var removedServerIDs: [String]
    public var syncKey: String
    public var moreAvailable: Bool
}

/// One client-side mailbox mutation carried by a Sync command. The client sends exactly
/// one of these per request; responses still use the normal `SyncResult` shape.
public enum EASSyncChange: Equatable, Sendable {
    case read(serverID: String)
    case delete(serverID: String)
}

public struct PingResult: Equatable, Sendable {
    public var hasChanges: Bool
    public var status: Int

    public init(hasChanges: Bool, status: Int) {
        self.hasChanges = hasChanges
        self.status = status
    }
}

public struct EASServerCapabilities: Equatable, Sendable {
    public let protocolVersions: [String]
    public let commands: [String]

    public init(protocolVersions: [String], commands: [String]) {
        self.protocolVersions = protocolVersions
        self.commands = commands
    }
}

// MARK: - HTTP port

public struct EASHTTPRequest: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    /// Overrides the transport's total-time budget for this request. Attachment payloads
    /// arrive as one base64 blob and the gateway is slow, so they ask for more than the
    /// default; nil keeps the transport default.
    public var resourceTimeout: TimeInterval?

    public init(
        url: URL,
        method: String,
        headers: [String: String],
        body: Data?,
        resourceTimeout: TimeInterval? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.resourceTimeout = resourceTimeout
    }
}

public struct EASHTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol EASHTTPTransport: Sendable {
    func send(_ request: EASHTTPRequest) async throws -> EASHTTPResponse
}

// MARK: - Client

public actor EASClient {
    /// Attachment payloads come back as one base64 blob; the gateway needs roughly 6 s per
    /// MB, so the 120 s transport default cuts off anything over ~15 MB. Downloads get a
    /// single long budget; every other command keeps the default.
    public static let attachmentResourceTimeout: TimeInterval = 600

    public let configuration: EASConfiguration
    private let transport: any EASHTTPTransport
    private let codec: WBXMLCodec
    private let longHangThreshold: TimeInterval
    private var policyKey: String?
    private var cookie: String?

    public init(
        configuration: EASConfiguration,
        transport: any EASHTTPTransport,
        codec: WBXMLCodec = try! WBXMLCodec.standard(),
        policyKey: String? = nil,
        longHangThreshold: TimeInterval = 10
    ) {
        self.configuration = configuration
        self.transport = transport
        self.codec = codec
        self.policyKey = policyKey
        self.longHangThreshold = longHangThreshold
    }

    public func currentPolicyKey() -> String? { policyKey }

    // MARK: OPTIONS

    public func options() async throws -> EASServerCapabilities {
        let request = EASHTTPRequest(
            url: configuration.endpoint,
            method: "OPTIONS",
            headers: baseHeaders(policyKey: nil, includeContentType: false),
            body: nil
        )
        let (response, elapsed) = try await perform(request)
        try ensureSuccess(response, elapsed: elapsed, command: "OPTIONS")
        captureCookie(from: response)
        return EASServerCapabilities(
            protocolVersions: (response.header("ms-asprotocolversions") ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
            commands: (response.header("ms-ascommands") ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        )
    }

    // MARK: Provision

    @discardableResult
    public func provision() async throws -> String {
        let stepOne = try codec.encode(.children("Provision", [
            .children("DeviceInformation", [
                .children("Set", [
                    .text("Model", "MacBookPro"),
                    .text("FriendlyName", "macOS EAS"),
                    .text("OS", "macOS"),
                    .text("UserAgent", "Apple-iPhone18C4/2307.90"),
                ]),
            ]),
            .children("Policies", [
                .children("Policy", [.text("PolicyType", "MS-EAS-Provisioning-WBXML")]),
            ]),
        ]))
        let first = try await call("Provision", body: stepOne, policyKey: "")
        let firstDoc = try decode(first)
        guard let provisionNode = firstDoc.child("Provision"),
              let status = provisionNode.child("Status")?.stringValue()
        else {
            throw EASError.malformedResponse("Provision: no Provision/Status")
        }
        guard status == "1" else {
            throw EASError.permanent(status: first.status, detail: "Provision status=\(status)")
        }
        guard let temporaryKey = provisionNode.path("Policies", "Policy", "PolicyKey")?.stringValue(),
              !temporaryKey.isEmpty
        else {
            throw EASError.malformedResponse("Provision: no PolicyKey")
        }

        let stepTwo = try codec.encode(.children("Provision", [
            .children("Policies", [
                .children("Policy", [
                    .text("PolicyType", "MS-EAS-Provisioning-WBXML"),
                    .text("PolicyKey", temporaryKey),
                    .text("Status", "1"),
                ]),
            ]),
        ]))
        let second = try await call(
            "Provision",
            body: stepTwo,
            policyKey: temporaryKey,
            extraParameters: ["PolicyKey": temporaryKey]
        )
        let secondDoc = try decode(second)
        guard let node = secondDoc.child("Provision"),
              let status2 = node.child("Status")?.stringValue(), status2 == "1"
        else {
            throw EASError.permanent(status: second.status, detail: "Provision step 2 failed")
        }
        let finalKey = node.path("Policies", "Policy", "PolicyKey")?.stringValue() ?? temporaryKey
        policyKey = finalKey
        return finalKey
    }

    // MARK: FolderSync

    public func folderSync(syncKey: String = "0") async throws -> FolderSyncResult {
        if policyKey == nil {
            try await provision()
        }
        let body = try codec.encode(.children("FolderSync", [.text("SyncKey", syncKey)]))
        let response = try await call("FolderSync", body: body)
        let document = try decode(response)

        guard let folderSync = document.child("FolderSync"),
              let status = folderSync.child("Status")?.stringValue()
        else {
            throw EASError.malformedResponse("FolderSync: missing Status")
        }
        guard status == "1" else {
            throw EASError.permanent(status: response.status, detail: "FolderSync status=\(status)")
        }
        guard let newKey = folderSync.child("SyncKey")?.stringValue() else {
            throw EASError.malformedResponse("FolderSync: missing SyncKey")
        }

        var folders: [EASFolder] = []
        for add in folderSync.path("Changes")?.children.filter({ $0.name == "Add" }) ?? [] {
            guard let serverID = add.child("ServerId")?.stringValue() else { continue }
            folders.append(EASFolder(
                serverID: serverID,
                parentID: add.child("ParentId")?.stringValue(),
                displayName: add.child("DisplayName")?.stringValue() ?? "",
                type: Int(add.child("Type")?.stringValue() ?? "1") ?? 1
            ))
        }
        return FolderSyncResult(folders: folders, syncKey: newKey)
    }

    // MARK: Sync

    public func sync(
        collectionID: String,
        syncKey: String = "0",
        window: Int = 25,
        filterType: Int = 5,
        bodyPreviewCharacters: Int = 500,
        change: EASSyncChange? = nil
    ) async throws -> SyncResult {
        if policyKey == nil {
            try await provision()
        }
        let body: Data
        if let change {
            // One minimal write body: no WindowSize/Options/BodyPreference. A write
            // command is the only thing this request may carry.
            var commands: WBXMLElement
            switch change {
            case .read(let serverID):
                commands = .children("Change", [
                    .text("ServerId", serverID),
                    .children("ApplicationData", [.text("Read", "1")]),
                ])
            case .delete(let serverID):
                commands = .children("Delete", [.text("ServerId", serverID)])
            }
            body = try codec.encode(.children("Sync", [
                .children("Collections", [
                    .children("Collection", [
                        .text("SyncKey", syncKey),
                        .text("CollectionId", collectionID),
                        .children("Commands", [commands]),
                    ]),
                ]),
            ]))
        } else {
            // FilterType: 0 = all, 1..7 = 1d/3d/1w/2w/1m/3m/6m. Default is one month.
            var options: [WBXMLElement] = [.text("FilterType", String(filterType))]
            if bodyPreviewCharacters > 0 {
                options.append(.children("BodyPreference", [
                    .text("Type", "1"),
                    .text("TruncationSize", String(bodyPreviewCharacters)),
                ]))
            }
            body = try codec.encode(.children("Sync", [
                .children("Collections", [
                    .children("Collection", [
                        .text("SyncKey", syncKey),
                        .text("CollectionId", collectionID),
                        .text("WindowSize", String(window)),
                        .children("Options", options),
                    ]),
                ]),
            ]))
        }
        // A swallowed Sync is measured as HTTP 200 with zero bytes on this gateway
        // (2026-11-17), so it joins the stale-key path: reset and rebuild, never "device dead".
        let response = try await call(
            "Sync", body: body, isWrite: change != nil, emptyBodyError: .syncKeyInvalid
        )
        let document = try decode(response)

        // A Sync answer that carries no `Collection/Status` cannot say whether the state is
        // intact; the only recovery is the same one a stale key takes (reset + rebuild).
        guard let syncNode = document.child("Sync"),
              let collection = syncNode.path("Collections", "Collection"),
              let status = collection.child("Status")?.stringValue()
        else {
            throw EASError.syncKeyInvalid
        }
        switch status {
        case "1":
            break
        case "3", "4":
            throw EASError.syncKeyInvalid
        default:
            throw EASError.permanent(status: response.status, detail: "Sync status=\(status)")
        }

        guard let newKey = collection.child("SyncKey")?.stringValue() else {
            throw EASError.malformedResponse("Sync: missing SyncKey")
        }

        var added: [EASMessage] = []
        var changed: [EASMessage] = []
        var removed: [String] = []
        for command in collection.child("Commands")?.children ?? [] {
            switch command.name {
            case "Add":
                if let message = parseMessage(command) { added.append(message) }
            case "Change":
                if let message = parseMessage(command) { changed.append(message) }
            case "Delete":
                if let serverID = command.child("ServerId")?.stringValue() {
                    removed.append(serverID)
                }
            default:
                break
            }
        }

        return SyncResult(
            added: added,
            changed: changed,
            removedServerIDs: removed,
            syncKey: newKey,
            // The gateway puts MoreAvailable inside Collection; accept the top-level
            // shape too so fixtures and other gateways keep working.
            moreAvailable: collection.child("MoreAvailable") != nil
                || syncNode.child("MoreAvailable") != nil
        )
    }

    private func parseMessage(_ command: WBXMLNode) -> EASMessage? {
        guard let serverID = command.child("ServerId")?.stringValue() else { return nil }
        let application = command.child("ApplicationData")
        func value(_ name: String) -> String? {
            application?.child(name)?.stringValue()
        }
        func nonBlank(_ name: String) -> String? {
            guard let text = value(name)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return nil }
            return text
        }
        return EASMessage(
            serverID: serverID,
            subject: value("Subject"),
            from: value("From"),
            to: value("To"),
            dateReceived: value("DateReceived"),
            isRead: value("Read").flatMap { $0 == "1" },
            importance: value("Importance").flatMap(Int.init),
            bodyPreview: application?.path("Body", "Data")?.stringValue(),
            attachments: (application?.child("Attachments")?.children ?? []).compactMap { node in
                guard let reference = node.child("FileReference")?.stringValue() else { return nil }
                return EASAttachment(
                    displayName: node.child("DisplayName")?.stringValue() ?? "attachment",
                    fileReference: reference,
                    size: node.child("EstimatedDataSize").flatMap { Int($0.stringValue() ?? "") }
                        ?? node.child("AttSize").flatMap { Int($0.stringValue() ?? "") },
                    contentID: node.child("ContentId")?.stringValue()
                )
            },
            cc: nonBlank("Cc"),
            messageClass: nonBlank("MessageClass"),
            meeting: Self.parseMeeting(application)
        )
    }

    // MARK: Meeting requests

    /// Parses `MeetingRequest` into the plain wire model. A malformed child only drops that
    /// child (dates stay nil); it never fails the whole sync batch.
    static func parseMeeting(_ application: WBXMLNode?) -> EASMeeting? {
        guard let meeting = application?.child("MeetingRequest") else { return nil }
        func text(_ name: String) -> String? {
            guard let raw = meeting.child(name)?.stringValue()?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { return nil }
            return raw
        }
        let location = meeting.path("Location", "DisplayName")?.stringValue()
            ?? text("Location")
        return EASMeeting(
            uid: text("UID"),
            start: Self.parseISO8601(text("StartTime")),
            end: Self.parseISO8601(text("EndTime")),
            allDay: text("AllDayEvent") == "1",
            dtstamp: Self.parseISO8601(text("DtStamp")),
            location: location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
            organizer: text("Organizer"),
            reminderMinutes: text("Reminder").flatMap(Int.init),
            responseRequested: text("ResponseRequested") == "1",
            busyStatus: text("BusyStatus").flatMap(Int.init),
            messageType: text("MeetingMessageType").flatMap(Int.init),
            instanceType: text("InstanceType").flatMap(Int.init),
            recurrenceId: Self.parseISO8601(text("RecurrenceId")),
            timeZone: text("TimeZone").flatMap(Self.parseMeetingTimeZone),
            recurrence: Self.parseRecurrence(meeting)
        )
    }

    /// `Recurrences` wraps exactly one `Recurrence` in e-mail meeting requests; accept a
    /// direct child too so fixtures and calendar-shaped responses keep working.
    static func parseRecurrence(_ meeting: WBXMLNode) -> EASRecurrence? {
        guard let node = meeting.path("Recurrences", "Recurrence") ?? meeting.child("Recurrence"),
              let type = node.child("Type")?.stringValue().flatMap(Int.init)
        else { return nil }
        func number(_ name: String) -> Int? {
            node.child(name)?.stringValue().flatMap(Int.init)
        }
        return EASRecurrence(
            type: type,
            interval: number("Interval"),
            until: Self.parseCompactDateTime(node.child("Until")?.stringValue()),
            occurrences: number("Occurrences"),
            daysOfWeek: number("DayOfWeek"),
            dayOfMonth: number("DayOfMonth"),
            weekOfMonth: number("WeekOfMonth"),
            monthOfYear: number("MonthOfYear"),
            firstDayOfWeek: number("FirstDayOfWeek")
        )
    }

    /// The EAS `TimeZone` blob is a 172-byte TIME_ZONE_INFORMATION: int32 little-endian
    /// bias, then the 64-byte UTF-16LE standard name. DST rules are deliberately ignored.
    static func parseMeetingTimeZone(_ base64: String) -> EASMeetingTimeZone? {
        guard let data = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)),
              data.count >= 4
        else { return nil }
        let bias = data.prefix(4).withUnsafeBytes { $0.load(as: Int32.self) }
        var name: String?
        if data.count >= 68 {
            let nameBytes = data.subdata(in: 4..<68)
            let raw = String(data: nameBytes, encoding: .utf16LittleEndian) ?? ""
            name = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\0")).nilIfBlank
        }
        return EASMeetingTimeZone(name: name, biasMinutes: Int(bias))
    }

    static func parseISO8601(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// `Until` uses the Compact DateTime form: `yyyyMMddTHHmmssZ` (UTC).
    static func parseCompactDateTime(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.date(from: value)
    }

    // MARK: Body fetch

    /// What the gateway answered for one body request. `payload` is HTML when `isHTML`
    /// is true and plain text otherwise; presentation is the caller's problem.
    public struct FetchedBody: Equatable, Sendable {
        public var payload: String
        public var isHTML: Bool
        public var isTruncated: Bool

        public init(payload: String, isHTML: Bool, isTruncated: Bool) {
            self.payload = payload
            self.isHTML = isHTML
            self.isTruncated = isTruncated
        }
    }

    /// Fetches one message body through ItemOperations. Type 2 is HTML; the gateway
    /// truncates at `truncationSize` characters and flags the body with `Truncated`.
    /// When that flag comes back set, one more request goes out without a truncation
    /// limit, so the reader is not silently handed half a message.
    ///
    /// The cap is deliberately far above a normal mail body: this gateway measures it in
    /// bytes and raises `Truncated` at 20 000 even when nothing was cut, which would cost
    /// every message a second round trip.
    public func fetchBody(
        collectionID: String,
        serverID: String,
        truncationSize: Int = 200_000
    ) async throws -> FetchedBody {
        let limited = try await fetchBodyOnce(
            collectionID: collectionID, serverID: serverID, truncationSize: truncationSize
        )
        guard limited.isTruncated else { return limited }
        // Everything here is still usable: a failed second request must not cost the caller
        // the partial body it already has.
        guard let full = try? await fetchBodyOnce(
            collectionID: collectionID, serverID: serverID, truncationSize: nil
        ) else {
            return limited
        }
        // An unflagged answer is authoritative: the flag is the gateway's, not a size guess.
        if !full.isTruncated { return full }
        return full.payload.count > limited.payload.count ? full : limited
    }

    private func fetchBodyOnce(
        collectionID: String,
        serverID: String,
        truncationSize: Int?
    ) async throws -> FetchedBody {
        if policyKey == nil {
            try await provision()
        }
        var preference: [WBXMLElement] = [.text("Type", "2")]
        if let truncationSize {
            preference.append(.text("TruncationSize", String(truncationSize)))
        }
        // Order matters: this gateway answers ItemOperations status 2 (protocol error) when
        // `Options` trails CollectionId/ServerId, and status 1 when it follows Store.
        let body = try codec.encode(.children("ItemOperations", [
            .children("Fetch", [
                .text("Store", "Mailbox"),
                .children("Options", [
                    .children("BodyPreference", preference),
                ]),
                .text("CollectionId", collectionID),
                .text("ServerId", serverID),
            ]),
        ]))
        let response = try await call("ItemOperations", body: body)
        let document = try decode(response)

        guard let operations = document.child("ItemOperations"),
              let status = operations.child("Status")?.stringValue()
        else {
            throw EASError.malformedResponse("ItemOperations: missing Status")
        }
        guard status == "1" else {
            throw EASError.permanent(status: response.status, detail: "ItemOperations status=\(status)")
        }
        guard let fetch = operations.path("Response", "Fetch"),
              let fetchStatus = fetch.child("Status")?.stringValue()
        else {
            throw EASError.malformedResponse("ItemOperations: missing Response/Fetch")
        }
        guard fetchStatus == "1" else {
            throw EASError.permanent(status: response.status, detail: "Fetch status=\(fetchStatus)")
        }
        guard let bodyNode = fetch.path("Properties", "Body"),
              let data = bodyNode.child("Data")?.stringValue()
        else {
            throw EASError.malformedResponse("ItemOperations: missing Body/Data")
        }
        // Type 2 is HTML; a gateway that cannot produce it answers with plain text (1) or
        // echoes our preference, so treat anything that is not explicitly HTML as text.
        let isHTML = bodyNode.child("Type")?.stringValue() == "2"
        return FetchedBody(
            payload: data,
            isHTML: isHTML,
            isTruncated: bodyNode.child("Truncated")?.stringValue() == "1"
        )
    }

    // MARK: Ping

    /// Long poll for changes on one collection. The gateway holds the request up to
    /// `heartbeatSeconds` and answers with the changed folders, if any.
    public func ping(collectionID: String, heartbeatSeconds: Int = 300) async throws -> PingResult {
        if policyKey == nil {
            try await provision()
        }
        let body = try codec.encode(.children("Ping", [
            .text("HeartbeatInterval", String(heartbeatSeconds)),
            .children("Folders", [
                .children("Folder", [.text("Id", collectionID)]),
            ]),
        ]))
        let response = try await call("Ping", body: body, treatEmptyBodyAsSuccess: true)
        guard !response.body.isEmpty else {
            // A zero-byte answer means the gateway dropped the long poll; treat as no change.
            return PingResult(hasChanges: false, status: 0)
        }
        let document = try decode(response)
        guard let statusText = document.path("Ping", "Status")?.stringValue(),
              let status = Int(statusText)
        else {
            throw EASError.malformedResponse("Ping: missing Status")
        }
        let changed = document.path("Ping", "Folders", "Folder") != nil
        return PingResult(hasChanges: changed, status: status)
    }

    // MARK: Attachments

    /// Downloads one attachment by its `FileReference`.
    ///
    /// Exchange nests the payload at `ItemOperations/Response/Fetch/Properties/Data`
    /// (MS-ASCMD 2.2.3.39.2, verified against the gateway on 2026-11-21); a gateway that
    /// puts `Data` directly under `ItemOperations` is still accepted.
    public func fetchAttachment(fileReference: String) async throws -> Data {
        if policyKey == nil {
            try await provision()
        }
        let body = try codec.encode(.children("ItemOperations", [
            .children("Fetch", [
                .text("Store", "Mailbox"),
                .text("FileReference", fileReference),
            ]),
        ]))
        let response = try await call(
            "ItemOperations",
            body: body,
            resourceTimeout: Self.attachmentResourceTimeout
        )
        let document = try decode(response)
        guard let status = document.path("ItemOperations", "Status")?.stringValue() else {
            throw EASError.malformedResponse("ItemOperations: missing Status")
        }
        guard status == "1" else {
            throw EASError.permanent(status: response.status, detail: "ItemOperations status=\(status)")
        }
        let fetch = document.path("ItemOperations", "Response", "Fetch")
        if let fetchStatus = fetch?.child("Status")?.stringValue(), fetchStatus != "1" {
            // 6 = the FileReference is invalid or expired; keep the code in the detail.
            throw EASError.permanent(status: response.status, detail: "Fetch status=\(fetchStatus)")
        }
        let encoded = fetch?.path("Properties", "Data")?.stringValue()
            ?? document.path("ItemOperations", "Data")?.stringValue()
        guard let encoded else {
            throw EASError.malformedResponse("ItemOperations: missing Data")
        }
        guard let data = Data(base64Encoded: encoded) else {
            throw EASError.malformedResponse("ItemOperations: bad base64 payload")
        }
        return data
    }

    // MARK: SendMail

    /// Sends a raw RFC822 message. The gateway answers `200` with a zero-byte body on
    /// success, so the empty-body device heuristic must not apply here.
    @discardableResult
    public func send(mime: Data, clientID: String? = nil) async throws -> String {
        if policyKey == nil {
            try await provision()
        }
        let identifier = (clientID ?? UUID().uuidString).uppercased()
        let body = try codec.encode(.children("SendMail", [
            .text("ClientId", identifier),
            .empty("SaveInSentItems"),
            .opaque("Mime", mime),
        ]))
        _ = try await call("SendMail", body: body, treatEmptyBodyAsSuccess: true)
        return identifier
    }

    // MARK: Transport plumbing

    /// `emptyBodyError` classifies a `200` with a zero-byte body. It is the caller's call
    /// because the same wire signal means different things per command (see `ensureSuccess`).
    private func call(
        _ command: String,
        body: Data,
        policyKey overrideKey: String? = nil,
        extraParameters: [String: String] = [:],
        treatEmptyBodyAsSuccess: Bool = false,
        isWrite: Bool = false,
        emptyBodyError: EASError = .deviceNotRegistered,
        resourceTimeout: TimeInterval? = nil
    ) async throws -> EASHTTPResponse {
        var components = URLComponents(url: configuration.endpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "Cmd", value: command),
            URLQueryItem(name: "User", value: configuration.account),
            URLQueryItem(name: "DeviceId", value: configuration.deviceID),
            URLQueryItem(name: "DeviceType", value: configuration.deviceType),
        ]
        items.append(contentsOf: extraParameters.map { URLQueryItem(name: $0.key, value: $0.value) })
        components.queryItems = items
        let request = EASHTTPRequest(
            url: components.url!,
            method: "POST",
            headers: baseHeaders(policyKey: overrideKey ?? policyKey, includeContentType: true),
            body: body,
            resourceTimeout: resourceTimeout
        )
        let (response, elapsed) = try await perform(request)
        captureCookie(from: response)
        try ensureSuccess(
            response,
            elapsed: elapsed,
            command: command,
            treatEmptyBodyAsSuccess: treatEmptyBodyAsSuccess,
            isWrite: isWrite,
            emptyBodyError: emptyBodyError
        )
        return response
    }

    private func perform(_ request: EASHTTPRequest) async throws -> (EASHTTPResponse, TimeInterval) {
        let started = Date()
        do {
            let response = try await transport.send(request)
            return (response, Date().timeIntervalSince(started))
        } catch {
            throw EASError.transient(reason: "\(error)")
        }
    }

    private func baseHeaders(policyKey: String?, includeContentType: Bool) -> [String: String] {
        var headers: [String: String] = [
            "Authorization": configuration.authorizationHeader,
            "User-Agent": "Apple-iPhone18C4/2307.90",
            "MS-ASProtocolVersion": configuration.protocolVersion,
            "Accept-Language": "zh-CN,zh-Hans;q=0.9",
        ]
        if includeContentType {
            headers["Content-Type"] = "application/vnd.ms-sync.wbxml"
        }
        if let policyKey, !policyKey.isEmpty {
            headers["X-MS-PolicyKey"] = policyKey
        }
        if let cookie {
            headers["Cookie"] = cookie
        }
        return headers
    }

    private func captureCookie(from response: EASHTTPResponse) {
        guard let setCookie = response.header("set-cookie") else { return }
        let pair = setCookie.split(separator: ";").first.map(String.init) ?? setCookie
        if pair.contains("=") {
            cookie = pair
        }
    }

    private func decode(_ response: EASHTTPResponse) throws -> WBXMLNode {
        do {
            return try codec.decode(response.body)
        } catch {
            throw EASError.malformedResponse("WBXML: \(error)")
        }
    }

    /// A zero-byte `200` is the gateway's generic "request swallowed" answer, so the caller
    /// names its meaning: for `Sync` the sync state cannot be trusted (reset and rebuild),
    /// for state-free reads it still means the device was not let through.
    private func ensureSuccess(
        _ response: EASHTTPResponse,
        elapsed: TimeInterval,
        command: String,
        treatEmptyBodyAsSuccess: Bool = false,
        isWrite: Bool = false,
        emptyBodyError: EASError = .deviceNotRegistered
    ) throws {
        switch response.status {
        case 200:
            if response.body.isEmpty {
                // OPTIONS never carries a body; everything else must — except SendMail,
                // whose success contract is exactly "200 with zero bytes".
                if command != "OPTIONS" && !treatEmptyBodyAsSuccess {
                    throw emptyBodyError
                }
            }
            return
        case 401:
            // The gateway answers a rejected *write* with the device-not-registered
            // signal (spec §设计增量: 写 401 → deviceNotRegistered); reads keep authFailed.
            if isWrite {
                throw EASError.deviceNotRegistered
            }
            throw EASError.authFailed
        case 444:
            throw EASError.gatewayRejected
        case 449:
            throw EASError.policyRequired(
                status: 449,
                message: response.header("x-ms-aserror")
            )
        case 502:
            // The probe's signature: the gateway hangs ~20s and then answers 502 because
            // the request body's wire format was rejected. A fast 502 is a real outage.
            if elapsed >= longHangThreshold {
                throw EASError.protocolRejected(detail: "502 after \(Int(elapsed))s")
            }
            throw EASError.transient(reason: "HTTP 502")
        case 503:
            let retryAfter = response.header("retry-after").flatMap(Int.init)
            throw EASError.throttled(retryAfterSeconds: retryAfter)
        case 500..<600:
            throw EASError.transient(reason: "HTTP \(response.status)")
        default:
            throw EASError.permanent(status: response.status, detail: response.header("x-ms-aserror"))
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
