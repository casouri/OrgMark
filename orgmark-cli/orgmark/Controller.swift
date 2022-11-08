//
//  Controller.swift
//  orgmark
//
//  Created by Yuan Fu on 2020/6/15.
//  Copyright © 2020 Yuan Fu. All rights reserved.
//

import Foundation
import os
import SwiftImage

class Controller: ServerDelegate {
    
    private var fileSent = false
    private var fileRecieved = false
    private var imageRecieved = false
    private var imageData: Data?
    private var fileData: Data?
    
    
    private var url: URL
    private var create: Bool
    private var width: Int?
    private var height: Int?
    private var server: Server!
    private var file: Data
    private var type: String
    private var supportedTypes = ["pkdrawing", "pdf"]
    
    init(url: URL, create: Bool, width: Int?, height: Int?) throws {
        self.url = url
        self.create = create
        self.width = width
        self.height = height
        if !create { file = try Data(contentsOf: url) }
        else { file = Data(count: 0) }
        type = url.pathExtension
        if !supportedTypes.contains(type) {
            print("We don't support \(type) extension")
        }
    }
    
    public func run() {
        do {
            os_log("Start")
            server = Server(asClient: self)
            try server.sendFile(file: file, type: type, name: url.path, tag: 0)
        } catch {
            os_log("Error sending file")
        }
    }
    
    func didRecieveFile(file: Data, type: String, name: String) {
        if !fileRecieved {
            fileRecieved = true
            fileData = file
            os_log("Read image")
            do { try server.readFile(timeout: nil) }
            catch { return }
        } else if !imageRecieved {
            imageRecieved = true
            imageData = file
            server.close()
            writeFile()
        }
    }
    
    func didWriteFile(tag: Int) {
        if tag == 0 {
            os_log("Sent file")
            fileSent = true
            os_log("Start reading")
            do { try server.readFile(timeout: 6000) }
            catch { return }
        }
    }
    
    func didDisconnect(error: Error?) {
        recover()
    }
    
    func didFail(error: Error?) {
        recover()
    }
    
    private func recover() {
        os_log("Try to reconnect")
        do { sleep(3) }
        // All done? No biggie.
        if fileSent && fileRecieved && imageRecieved {
            writeFile()
        } else {
            // Not done? Try again.
            server.close()
            run()
        }
    }
    
    private func writeFile() {
        do {
            guard let data = fileData,
                let imageData = imageData else { exit(-1) }
            
            try data.write(to: url)
            
            let imageURL = url.deletingPathExtension().appendingPathExtension("png")
            
            if width == nil && height == nil {
                try imageData.write(to: imageURL)
            } else if let image = Image<RGBA<UInt8>>(data: imageData) {
                let imageWidth = Float(image.width)
                let imageHeight = Float(image.height)
                let maxWidth = width ?? 999999
                let maxHeight = height ?? 999999
                let ratio = min(Float(maxWidth)/imageWidth, Float(maxHeight)/imageHeight, 1)
                let width = Int(imageWidth * ratio)
                let height = Int(imageHeight * ratio)
                try image.resizedTo(width: width, height: height).data(using: .png)?.write(to: imageURL)
            } else {
                try imageData.write(to: imageURL)
            }
            exit(0)
            
        } catch {
            print("Failed to write file")
            exit(-1)
        }
    }
    
    func didStopListening(error: Error?) {
        // We don't care.
        return
    }
}
