import EASAdapter
import EASClient
import MailDomain

/// The two gateway ports a composition root needs. `write` is deliberately non-optional:
/// a production build has no "read-only" degradation path.
public struct GatewayEndpoints: Sendable {
    public var read: any MailGateway
    public var write: any MailWriteGateway

    public init(read: any MailGateway, write: any MailWriteGateway) {
        self.read = read
        self.write = write
    }
}

/// Builds the gateway endpoints for one configuration. Assembly tests substitute a fake;
/// production always uses `PlatformGateway.make`.
public typealias GatewayFactory = @Sendable (ServerConfiguration) -> GatewayEndpoints

/// The only place that constructs the production gateway (spec §7).
enum PlatformGateway {
    static func make(_ configuration: ServerConfiguration) -> GatewayEndpoints {
        let easConfiguration = ConfigurationSource.easConfiguration(configuration)
        let adapter = EASAdapter(
            client: EASClient(
                configuration: easConfiguration,
                transport: URLSessionTransport(configuration: easConfiguration)
            )
        )
        // The same adapter instance serves both ports; assembly tests assert this shape.
        return GatewayEndpoints(read: adapter, write: adapter)
    }
}
