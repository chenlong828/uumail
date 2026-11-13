import EASAdapter
import EASClient
import MailDomain

/// Builds the gateway for one configuration. The composition roots take one of these so
/// assembly tests can substitute a fake; production always uses `PlatformGateway.make`.
public typealias GatewayFactory = @Sendable (ServerConfiguration) -> any MailGateway

/// The only place that constructs the production gateway (spec §7).
enum PlatformGateway {
    static func make(_ configuration: ServerConfiguration) -> any MailGateway {
        let easConfiguration = ConfigurationSource.easConfiguration(configuration)
        return EASAdapter(
            client: EASClient(
                configuration: easConfiguration,
                transport: URLSessionTransport(configuration: easConfiguration)
            )
        )
    }
}
