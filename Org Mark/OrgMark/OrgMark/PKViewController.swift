//
//  PKViewController.swift
//  Org Mark
//
//  Created by Yuan Fu on 2020/6/14.
//  Copyright © 2020 Yuan Fu. All rights reserved.
//

import UIKit
import PencilKit

class PKViewController: UIViewController, PKToolPickerObserver, PKCanvasViewDelegate {

    public var backTo: ViewController!
    public var drawingToShow: PKDrawing!

    @IBOutlet weak var undoButton: UIButton!
    @IBOutlet weak var redoButton: UIButton!
    @IBAction func undoButtonPressed(_ sender: UIButton) {
        undoManager?.undo()
        updateButtonState()
    }
    @IBAction func redoButtonPressed(_ sender: UIButton) {
        undoManager?.redo()
        updateButtonState()
    }
    
    private func updateButtonState() {
        if undoManager == nil {
            undoButton.isEnabled = false
            redoButton.isEnabled = false
        } else {
            undoButton.isEnabled = undoManager!.canUndo
            redoButton.isEnabled = undoManager!.canRedo
        }
    }
    
    @IBAction func DoneButtonTapped(_ sender: UIButton) {
        backTo.doneEditing(drawing: canvasView.drawing)
        dismiss(animated: true, completion: nil)
    }
    @IBOutlet weak var canvasView: PKCanvasView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        canvasView.allowsFingerDrawing = false
        canvasView.delegate = self
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSUndoManagerDidUndoChange, object: nil, queue: nil, using: { _ in self.updateButtonState() })
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSUndoManagerDidRedoChange, object: nil, queue: nil, using: { _ in self.updateButtonState() })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvasView.drawing = drawingToShow
        canvasView.maximumZoomScale = 10
        canvasView.bouncesZoom = true
        updateButtonState()
        // Set up the tool picker, using the window of our parent because our view has not been added to a window yet.
        if let window = view.window,
            let toolPicker = PKToolPicker.shared(for: window) {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.setVisible(true, forFirstResponder: self)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }
        
    }
    
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        updateButtonState()
    }
}
