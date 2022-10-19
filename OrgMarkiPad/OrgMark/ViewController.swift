//
//  ViewController.swift
//  OrgMark
//
//  Created by Yuan Fu on 2020/6/15.
//  Copyright © 2020 Yuan Fu. All rights reserved.
//

import UIKit
import PencilKit
import os
import QuickLook
import PDFKit
import QuickLookThumbnailing

class ViewController: UIViewController, ServerDelegate {
    
    private var fileRecieved = false
    private var fileSent = false
    private var imageSent = false
    private var workingOnCanvas = false
    private var fileName: String?
    private var fileData: Data?
    private var fileType: String?
    private var imageData: Data?
    private var server: Server!
    
    func didRecieveFile(file: Data, type: String, name: String) {
        
        if workingOnCanvas {
            if fileName != name {
                server.disconnect()
            } // If name equals, let it wait for us to finish editing the file.
        } else {
            if fileRecieved && fileName == name {
                do {
                    // It's the file we have. Maybe we are resuming from a disconnection.
                    if !fileSent && fileData != nil && !workingOnCanvas {
                        os_log("Resume sending file")
                        try server.sendFile(file: fileData!, type: fileType!, name: fileName!, tag: 0)
                    } else if !imageSent && imageData != nil && !workingOnCanvas {
                        os_log("Resume sending image")
                        try server.sendFile(file: imageData!, type: "png", name: fileName!, tag: 1)
                    } // If we are editing, wait for edit to finish.
                } catch { didFail(error: nil) }
            } else {
                fileRecieved = true
                fileName = name
                fileData = file
                fileType = type
                if type == "pkdrawing" {
                    showCanvas()
                } else if type == "pdf" {
                    showPreview()
                }
            }
        }
    }
    
    private func showPreview() {
        os_log("Show preview")
        let preview = QLPreviewController()
        preview.delegate = self
        preview.dataSource = self
        workingOnCanvas = true
        present(preview, animated: true, completion: nil)
    }
    
    private func showCanvas() {
        let drawing: PKDrawing
        if fileData!.count != 0 {
            do {
                drawing = try PKDrawing(data: fileData!)
                os_log("Loaded file into drawing")
            } catch {
                let alert = UIAlertController(title: "Oops", message: "File data corrupted.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"), style: .default, handler: {_ in }))
                self.present(alert, animated: true, completion: nil)
                return
            }
        } else { drawing = PKDrawing() }
        
        let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle: nil)
        let canvas = storyBoard.instantiateViewController(withIdentifier: "canvas") as! PKViewController
        
        canvas.drawingToShow = drawing
        canvas.modalPresentationStyle = .fullScreen
        canvas.backTo = self
        workingOnCanvas = true
        present(canvas, animated: true, completion: nil)
    }
    
    /*
     * User tapped the Done button on our canvas. Generate file and image data.
     */
    public func doneEditing(drawing: PKDrawing) {
        os_log("Finished editing, send the file")
        workingOnCanvas = false
        let file = drawing.dataRepresentation()
        fileData = file
        let image = drawing.image(from: drawing.bounds, scale: 1.0)
        imageData = image.pngData()
        // Send file and image.
        sendFile()
    }
    
    /*
     * User tapped the Done button. Genreate file and image data.
     */
    public func donePreviewing() {
        // fileData is set in preview delegate.
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = temporaryDirectoryURL.appendingPathComponent("sample.pdf")

        let size: CGSize = CGSize(width: 60, height: 90)
        let scale = UIScreen.main.scale
        
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
        let generator = QLThumbnailGenerator.shared
        
        generator.generateBestRepresentation(for: request, completion: { (thumbnail, error) in
            if thumbnail == nil || error != nil {
                os_log("Can't generate thumbnail")
                self.imageData = Data(count: 0)
            } else {
                self.imageData = thumbnail!.uiImage.pngData()
            }
            // We have everthing, send file.
            self.sendFile()
        })
    }
    
    /*
     * Send the file after we've set fileData and imageData.
     */
    public func sendFile() {
        do {
            if server.closed {
                server = Server(asServer: self)
            } else {
                // Name doens't matter for image.
                try server.sendFile(file: fileData!, type: fileType!, name: fileName!, tag: 0)
            }
        }  catch {
            // Failed to send file, treat as disconnect
            didDisconnect(error: nil)
        }
    }
    
    func didWriteFile(tag: Int) {
        do {
            switch tag {
            case 0:
                os_log("File sent, now send image")
                fileSent = true
                // (fileName for image doesn't matter)
                try server.sendFile(file: imageData!, type: "png", name: fileName!, tag: 1)
            case 1:
                os_log("Image sent")
                imageSent = true
                done()
            default:
                return
            }
        } catch {
            os_log("Error in didWriteFile")
        }
    }
    
    private func done() {
        os_log("Done")
        // Reset state
        fileRecieved = false
        fileSent = false
        imageSent = false
        workingOnCanvas = false
        fileData = nil
        imageData = nil
    }
    
    func didDisconnect(error: Error?) {
        // We hope the client will come back, so don't reset state.
    }
    
    func didStopListening(error: Error?) {
        os_log("Stopped listening, server closed")
    }
    
    func didFail(error: Error?) {
        // Something went wrong, try to restart.
        server.close()
        server = Server(asServer: self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        server = Server(asServer: self)
    }
    
}

// MARK: - Preview delegate

extension ViewController: QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = temporaryDirectoryURL.appendingPathComponent("sample.pdf")
        
        if fileData!.count == 0 {
            let path = Bundle.main.path(forResource: "blank", ofType: "pdf")
            let url = URL(fileURLWithPath: path!)
            return url as QLPreviewItem
        } else {
            guard let pdf = PDFDocument(data: fileData!) else {
                os_log("Can't generate pdf")
                return url as QLPreviewItem
            }
            pdf.write(to: url)
        }
        
        return url as QLPreviewItem
    }
    
    func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode {
        return .createCopy
    }
    
    func previewController(_ controller: QLPreviewController,
    didSaveEditedCopyOf previewItem: QLPreviewItem,
    at modifiedContentsURL: URL) {
        guard let data = PDFDocument(url: modifiedContentsURL)?.dataRepresentation() else { return }
        fileData = data as Data
    }
    
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        // Checkpoint 2: If we disconnect, we can resume from this state (ready to send).
        os_log("User tapped Done, send the file back")
        donePreviewing()
    }
}
