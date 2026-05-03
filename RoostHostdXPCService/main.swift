import Foundation
import RoostHostdCore

final class HostdXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service = HostdXPCService()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: RoostHostdXPCProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

let delegate = HostdXPCListenerDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
