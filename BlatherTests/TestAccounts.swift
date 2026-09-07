import Foundation
@testable import Blather

@discardableResult
func makeTestAccount(
    _ database: AppDatabase,
    network: Network,
    suffix: String = "1",
    state: ConnectionState = .connected
) throws -> ConnectionInfo {
    let id = "\(network.rawValue)-account-\(suffix)"
    try database.connections.upsert(
        accountId: id,
        network: network,
        providerAccountId: "\(network.rawValue)-provider-\(suffix)",
        state: state,
        accountLabel: "@\(network.rawValue)-\(suffix)",
        meta: [:]
    )
    return try database.connections.get(id)!
}
