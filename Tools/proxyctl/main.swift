import Foundation

let usage = """
usage: proxyctl status
       proxyctl set <host> <port> [--current]
       proxyctl pac <url> [--current]
       proxyctl off [--current]
       proxyctl profiles
       proxyctl use <profile> [--current]

By default changes apply to every saved network; --current limits them to the active one.
"""

func printStatus() throws {
    print("effective: \(ProxyManager.effectiveProxy())")
    for network in try ProxyManager.networks() {
        print("\(network.isCurrent ? "*" : " ") \(network.name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(network.summary)")
    }
}

var args = Array(CommandLine.arguments.dropFirst())
let scope: ProxyScope = args.contains("--current") ? .currentNetwork : .allNetworks
args.removeAll { $0 == "--current" }

do {
    switch (args.first, args.count) {
    case ("status", 1):
        try printStatus()
    case ("set", 3):
        guard let port = Int(args[2]) else { throw ProxyManager.Failure.invalid("Port must be a number") }
        let count = try ProxyManager.apply(ProxyConfig(kind: .manual, host: args[1], port: port), scope: scope)
        print("updated \(count) service(s)")
        try printStatus()
    case ("pac", 2):
        let count = try ProxyManager.apply(ProxyConfig(kind: .pac, pacURL: args[1]), scope: scope)
        print("updated \(count) service(s)")
        try printStatus()
    case ("profiles", 1):
        let store = try ProfileStore.load() ?? ProfileStore()
        for profile in store.profiles {
            print("\(profile.id == store.selectedID ? "*" : " ") \(profile.name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(profile.config.summary)")
        }
    case ("use", 2):
        guard let profile = try ProfileStore.load()?.profile(named: args[1]) else {
            throw ProxyManager.Failure.invalid("No profile named \(args[1])")
        }
        let count = try ProxyManager.apply(profile.config, scope: scope)
        print("updated \(count) service(s) with \(profile.name)")
        try printStatus()
    case ("off", 1):
        let count = try ProxyManager.apply(nil, scope: scope)
        print("updated \(count) service(s)")
        try printStatus()
    default:
        print(usage)
        exit(2)
    }
} catch {
    FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
