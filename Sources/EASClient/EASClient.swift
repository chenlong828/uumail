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

public struct EASMessage: Equatable, Sendable {
    public var serverID: String
    public var subject: String?
    public var from: String?
    public var to: String?
    public var dateReceived: String?
    public var isRead: Bool?
    public var importance: Int?
    public var bodyPreview: String?

    public init(
        serverID: String,
        subject: String? = nil,
        from: String? = nil,
        to: String? = nil,
        dateReceived: String? = nil,
        isRead: Bool? = nil,
        importance: Int? = nil,
        bodyPreview: String? = nil
    ) {
        self.serverID = serverID
        self.subject = subject
        self.from = from
        self.to = to
        self.dateReceived = dateReceived
        self.isRead = isRead
        self.importance = importance
        self.bodyPreview = bodyPreview
    }
}

public struct SyncResult: Equatable, Sendable {
    public var added: [EASMessage]
    public var changed: [EASMessage]
    public var removedServerIDs: [String]
    public var syncKey: String
    public var moreAvailable: Bool
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

    public init(url: URL, method: String, headers: [String: String], body: Data?) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
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
        bodyPreviewCharacters: Int = 500
    ) async throws -> SyncResult {
        if policyKey == nil {
            try await provision()
        }
        // FilterType: 0 = all, 1..7 = 1d/3d/1w/2w/1m/3m/6m. Default is one month.
        var options: [WBXMLElement] = [.text("FilterType", String(filterType))]
        if bodyPreviewCharacters > 0 {
            options.append(.children("BodyPreference", [
                .text("Type", "1"),
                .text("TruncationSize", String(bodyPreviewCharacters)),
            ]))
        }
        let body = try codec.encode(.children("Sync", [
            .children("Collections", [
                .children("Collection", [
                    .text("SyncKey", syncKey),
                    .text("CollectionId", collectionID),
                    .text("WindowSize", String(window)),
                    .children("Options", options),
                ]),
            ]),
        ]))
        let response = try await call("Sync", body: body)
        let document = try decode(response)

        guard let syncNode = document.child("Sync"),
              let collection = syncNode.path("Collections", "Collection"),
              let status = collection.child("Status")?.stringValue()
        else {
            throw EASError.malformedResponse("Sync: missing Collection/Status")
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
            moreAvailable: syncNode.child("MoreAvailable") != nil
        )
    }

    private func parseMessage(_ command: WBXMLNode) -> EASMessage? {
        guard let serverID = command.child("ServerId")?.stringValue() else { return nil }
        let application = command.child("ApplicationData")
        func value(_ name: String) -> String? {
            application?.child(name)?.stringValue()
        }
        return EASMessage(
            serverID: serverID,
            subject: value("Subject"),
            from: value("From"),
            to: value("To"),
            dateReceived: value("DateReceived"),
            isRead: value("Read").flatMap { $0 == "1" },
            importance: value("Importance").flatMap(Int.init),
            bodyPreview: application?.path("Body", "Data")?.stringValue()
        )
    }

    // MARK: Body fetch

    /// Fetches one message body through ItemOperations. Type 2 is HTML; the gateway
    /// truncates at `truncationSize` characters and flags the body as truncated.
    public func fetchBody(
        collectionID: String,
        serverID: String,
        truncationSize: Int = 20_000
    ) async throws -> String {
        if policyKey == nil {
            try await provision()
        }
        let body = try codec.encode(.children("ItemOperations", [
            .children("Fetch", [
                .text("Store", "Mailbox"),
                .text("CollectionId", collectionID),
                .text("ServerId", serverID),
                .children("Options", [
                    .children("BodyPreference", [
                        .text("Type", "2"),
                        .text("TruncationSize", String(truncationSize)),
                    ]),
                ]),
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
        guard let data = fetch.path("Properties", "Body", "Data")?.stringValue() else {
            throw EASError.malformedResponse("ItemOperations: missing Body/Data")
        }
        return data
    }

    // MARK: Transport plumbing

    private func call(
        _ command: String,
        body: Data,
        policyKey overrideKey: String? = nil,
        extraParameters: [String: String] = [:]
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
            body: body
        )
        let (response, elapsed) = try await perform(request)
        captureCookie(from: response)
        try ensureSuccess(response, elapsed: elapsed, command: command)
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

    private func ensureSuccess(_ response: EASHTTPResponse, elapsed: TimeInterval, command: String) throws {
        switch response.status {
        case 200:
            if response.body.isEmpty {
                // OPTIONS never carries a body; everything else must.
                if command != "OPTIONS" {
                    throw EASError.deviceNotRegistered
                }
            }
            return
        case 401:
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
