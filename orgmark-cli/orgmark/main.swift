//
//  main.swift
//  orgmark
//
//  Created by Yuan Fu on 2020/6/13.
//  Copyright © 2020 Yuan Fu. All rights reserved.
//

import Foundation
import CoreBluetooth
import ArgumentParser


enum CmdError: Error {
    case parseError
}

struct Command: ParsableCommand {
    static let configuration = CommandConfiguration(
    abstract: "Send drawing to iPad to edit.")
    
    @Argument(help: "The drawing file. If --new option is set, this is the file that we save to.")
    var filePath: String
    
    @Option(name: [.customLong("width"), .customShort("w")],
            help: "Max width of the exported image in pixels.")
    var width: Int?
    
    @Option(name: [.customLong("height"), .customShort("h")],
            help: "Max height of the exported image in pixels.")
    var height: Int?

    @Flag(name: [.customLong("new"), .customShort("n")], help: "Create new drawing.")
    var create: Bool
    
    mutating func run() throws {
        let path = NSString(string: filePath).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        
        do {
            let controller = try Controller(url: url, create: create, width: width, height: height)
            controller.run()
            RunLoop.main.run()
        } catch {
            print("Can't read file: \(url.relativeString)")
        }
    }
}

Command.main()
