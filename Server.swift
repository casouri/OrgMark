//
//  Server.swift
//  Org Mark
//
//  Created by Yuan Fu on 2020/6/15.
//  Copyright © 2020 Yuan Fu. All rights reserved.
//

import Foundation
import CocoaAsyncSocket
import os

enum ServerError: Error {
    case ArgumentOutOfBound
    case Busy
}

struct File {
    var data: Data?
    var size: Int?
    var type: String?
    var tag: Int
    var name: String?
    
    private func pad(data: Data, to size: Int) throws -> Data {
        guard size >= data.count else { throw ServerError.ArgumentOutOfBound }
        let pad = Data(count: size - data.count)
        var data = data
        data.append(pad)
        return data
    }
    
    func sizeData() throws -> Data {
        return try pad(data: String(size!).data(using: .utf8)!, to: 128)
    }
    
    func typeData() throws -> Data {
        return try pad(data: type!.data(using: .utf8)!, to: 128)
    }
}

protocol ServerDelegate {
    func didRecieveFile(file: Data, type: String, name: String)
    func didWriteFile(tag: Int)
    func didDisconnect(error: Error?)
    func didFail(error: Error?)
    func didStopListening(error: Error?)
}

extension ServerDelegate {
    func didStopListenint(error: Error?) {
        return
    }
}

class Server: NSObject, NetServiceDelegate, NetServiceBrowserDelegate, GCDAsyncSocketDelegate {
    private var service: NetService?
    private var browser: NetServiceBrowser?
    
    private var listeningSocket: GCDAsyncSocket?
    private var port: Int?
    private var currentSendFile: File?
    private var currentRecieveFile: File?
    private var controller: ServerDelegate
    
    private var otherSide: GCDAsyncSocket?
    private var generalTimeout: TimeInterval = 1
    
    public var closed = false
    private var resolving = false
    private var publishing = false
    private var searching = false
    
    init(asServer delegate: ServerDelegate) {
        controller = delegate
        listeningSocket = GCDAsyncSocket(delegate: nil, delegateQueue: DispatchQueue.main)
        super.init()
        listeningSocket?.delegate = self
        
        do {
            try listeningSocket!.accept(onPort: 0)
            os_log("Listening on port %d", listeningSocket!.localPort)
            service = NetService(domain: "local.", type: "_orgmark._tcp.", name: "", port: Int32(listeningSocket!.localPort))

            service!.includesPeerToPeer = true
            service!.delegate = self
            publishing = true
            service!.publish()
            closed = false
        } catch {
            os_log("Can't accept socket: %s", error.localizedDescription)
            controller.didFail(error: nil)
        }
    }
    
    init(asClient delegate: ServerDelegate) {
        controller = delegate
        browser = NetServiceBrowser()
        super.init()
        browser!.delegate = self
        os_log("Searching for service")
        searching = true
        browser!.searchForServices(ofType: "_orgmark._tcp", inDomain: "local.")
    }

    public func close() {
        closed = true
        os_log("Closing")
        if service != nil {
            service!.stop()
            publishing = false
            service = nil
        }
        if listeningSocket != nil {
            listeningSocket!.disconnect()
        }
        if let otherSide = otherSide {
            otherSide.disconnect()
        }
    }
    
    public func disconnect() {
        os_log("Disconnecting upon request")
        if let otherSide = otherSide {
            otherSide.disconnect()
        }
    }
    
    // MARK: - Send file, socket
    
    public func sendFile(file: Data, type: String, name: String, tag: Int) throws {
        if currentSendFile != nil { throw ServerError.Busy }
        currentSendFile = File(data: file, size: file.count, type: type, tag: tag, name: name)
        if otherSide != nil { reallySendFile() }
    }
    
    private func reallySendFile() {
        if let file = currentSendFile {
            os_log("Sending file %d of size %d", file.tag, file.size!)
            otherSide!.write((String(file.size!)+"\n\n").data(using: .utf8), withTimeout: generalTimeout, tag: 0)
        }
    }
    
    func socket(_ sock: GCDAsyncSocket, didWriteDataWithTag tag: Int) {
        guard let file = currentSendFile,
            let otherSide = otherSide else { return }
        switch tag {
        case 0:
            os_log("Send type: %s", file.type!)
            otherSide.write((file.type!+"\n\n").data(using: .utf8), withTimeout: generalTimeout, tag: 1)
        case 1:
            os_log("Send name: %s", file.name!)
            otherSide.write((file.name!+"\n\n").data(using: .utf8), withTimeout: generalTimeout, tag: 2)
        case 2:
            if file.size! != 0 {
                os_log("Send file chunk")
                otherSide.write(file.data, withTimeout: generalTimeout, tag: 3)
            } else {
                currentSendFile = nil
                controller.didWriteFile(tag: file.tag)
            }
        case 3:
            currentSendFile = nil
            controller.didWriteFile(tag: file.tag)
        default:
            return
        }
    }
    
    // MARK: - Send file, Bonjour
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        // Bonjour seems to call this more than once.
        guard !closed && resolving else { return }
        resolving = false

        os_log("Resolved address, connecting")
        do {
            otherSide = GCDAsyncSocket(delegate: self, delegateQueue: DispatchQueue.main)
            try otherSide!.connect(to: sender)
            os_log("Connected")
            reallySendFile()
        } catch {
            os_log("Can't connect to the service %@", sender)
            controller.didFail(error: nil)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard !closed && searching else { return }
        searching = false
        
        os_log("Found service, resolving address")
        self.service = service
        service.delegate = self
        resolving = true
        service.resolve(withTimeout: generalTimeout)
    }
    
    func netServiceDidStop(_ sender: NetService) {
        guard !closed else { return }
        if publishing {
            os_log("Service stopped publishing")
            controller.didFail(error: nil)
        } else if resolving {
            os_log("Service stopped resovling")
            controller.didFail(error: nil)
        } // Otherwise, we don't care.
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        guard !closed && resolving else { return }
        os_log("Couldn't resolve address")
        controller.didFail(error: nil)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        guard !closed && searching else { return }

        os_log("Error when searching for service: %s", errorDict["errorCode"]?.debugDescription ?? "?")
        controller.didFail(error: nil)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard !closed else { return }
        os_log("Service removed")
        controller.didFail(error: nil)
    }
    
    // MARK: - Recieve file, socket
    
    public func readFile(timeout: TimeInterval?) throws {
        try newFile(timeout: timeout)
    }
    
    private func newFile(timeout: TimeInterval?) throws {
        guard currentRecieveFile == nil else { throw ServerError.Busy }
        currentRecieveFile = File(tag: 0)
        otherSide!.readData(to: "\n\n".data(using: .utf8), withTimeout: timeout ?? generalTimeout, tag: 0)
    }

    func socket(_ sock: GCDAsyncSocket, didAcceptNewSocket newSocket: GCDAsyncSocket) {
        os_log("Accepted incoming connection")
        guard otherSide == nil else { os_log("Busy, rejected"); return}
        otherSide = newSocket
        do { try newFile(timeout: nil) }
        catch { os_log("Busy, can't recieve new file"); return }
    }

    func socket(_ sock: GCDAsyncSocket, didRead data: Data, withTag tag: Int) {
        switch tag {
        case 0:
            guard let string = String(data: data, encoding: .utf8) else { return }
            guard let size = Int(string.dropLast(2)) else {
                os_log("Can't decode file size: %s", string)
                controller.didFail(error: nil)
                return
            }
            os_log("Recieved file size: %d", size)
            currentRecieveFile!.data = Data(capacity: size)
            currentRecieveFile!.size = size
            otherSide!.readData(to: "\n\n".data(using: .utf8), withTimeout: generalTimeout, tag: 1)
        case 1:
            guard let type = String(data: data, encoding: .utf8) else {
                os_log("Can't decode file type")
                controller.didFail(error: nil)
                return
            }
            os_log("Recieved file type: %s", type)
            currentRecieveFile!.type = String(type.dropLast(2))
            otherSide!.readData(to: "\n\n".data(using: .utf8), withTimeout: generalTimeout, tag: 2)
        case 2:
            guard let name = String(data: data, encoding: .utf8) else {
                os_log("Can't decode file name")
                controller.didFail(error: nil)
                return
            }
            os_log("Recieved file name: %s", name)
            currentRecieveFile!.name = String(name.dropLast(2))
            if currentRecieveFile!.size == 0 {
                let type = currentRecieveFile!.type!
                let name = currentRecieveFile!.name!
                currentRecieveFile = nil
                controller.didRecieveFile(file: Data(count: 0), type: type, name: name)
                
            } else {
                otherSide!.readData(toLength: UInt(currentRecieveFile!.size!), withTimeout: generalTimeout, tag: 3)
            }
        case 3:
            os_log("Recieved file chunk")
            let type = currentRecieveFile!.type!
            let name = currentRecieveFile!.name!
            currentRecieveFile = nil
            controller.didRecieveFile(file: data, type: type, name: name)
        default:
            return
        }
    }

    // MARK: - Recieve file, Bonjour
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        // We don't check for publishing because we want the service to be always on, if not,
        // delagate needs to recover from it.
        guard !closed else { return }
        os_log("Service down")
        controller.didFail(error: nil)
    }
    
    func netServiceDidPublish(_ sender: NetService) {
        guard !closed && publishing else { return }
        publishing = false
        os_log("Published service as %s on %d", sender.name, sender.port)
    }

    // MARK: - Socket error
    
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        guard !closed else { return }
        if let msg = err?.localizedDescription {
            os_log("Socket disconnected: %s", msg)
        } else {
            os_log("Socket disconnected")
        }
        if sock == listeningSocket {
            controller.didStopListening(error: err)
        } else if sock == otherSide {
            otherSide = nil
            currentRecieveFile = nil
            currentSendFile = nil
            controller.didDisconnect(error: err)
        } // Other than this two sockets, we don't care.
    }
    
}
