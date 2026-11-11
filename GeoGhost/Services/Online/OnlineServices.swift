import Foundation

/// Everything that talks to the online backend, built once from the configuration.
struct OnlineServices: Sendable {
    let config: OnlineConfig
    let identity: OnlineSession
    let database: PostgrestClient

    init(config: OnlineConfig) {
        self.config = config
        identity = OnlineSession(auth: SupabaseAuthClient(config: config))
        database = PostgrestClient(config: config, identity: identity)
    }
}
