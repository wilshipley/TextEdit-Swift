//
//  Document.swift
//  TextEdit
//
//  Created by William Shipley on 2/23/16.
//
//

import Cocoa

public extension Document {
    
    // MARK: NSDocument
    
    override public var shouldRunSavePanelWithAccessoryView: Bool { return isRichText } // For plain-text documents, we add our own accessory view for selecting encodings. The plain text case does not require a format popup.

    override public func fileWrapperOfType(typeName: String) throws -> NSFileWrapper { // Returns an object that represents the document to be written to file.
        
        var documentAttributes: [String : AnyObject] = [
            NSPaperSizeDocumentAttribute: NSValue(size: paperSize),
            NSReadOnlyDocumentAttribute: NSNumber(integer: readOnly ? 1 : 0),
            NSHyphenationFactorDocumentAttribute: NSNumber(float: hyphenationFactor),
            NSLeftMarginDocumentAttribute: NSNumber(double: Double(printInfo.leftMargin)),
            NSRightMarginDocumentAttribute: NSNumber(double: Double(printInfo.rightMargin)),
            NSBottomMarginDocumentAttribute: NSNumber(double: Double(printInfo.bottomMargin)),
            NSTopMarginDocumentAttribute: NSNumber(double: Double(printInfo.topMargin)),
            NSViewModeDocumentAttribute: NSNumber(integer: hasMultiplePages ? 1 : 0),
            NSUsesScreenFontsDocumentAttribute: NSNumber(bool: usesScreenFonts),
        ]
        
        if viewSize != .zero {
            documentAttributes[NSViewSizeDocumentAttribute] = NSValue(size: viewSize)
        }

        
        // TextEdit knows how to save all these types, including their super-types. It does not know how to save any of their potential subtypes. Hence, the conformance check is the reverse of the usual pattern.
        let documentType: String = {
            let workspace = NSWorkspace.sharedWorkspace()
            // kUTTypePlainText also handles kUTTypeText and has to come before the other types so we will use the least specialized type
            // For example, kUTTypeText is an ancestor of kUTTypeText and kUTTypeRTF but we should use kUTTypeText because kUTTypeText is an ancestor of kUTTypeRTF.
            if workspace.type(kUTTypePlainText as String, conformsToType: typeName) { return NSPlainTextDocumentType }
            else if workspace.type(kUTTypeRTF as String, conformsToType: typeName) { return NSRTFTextDocumentType }
            else if workspace.type(kUTTypeRTFD as String, conformsToType: typeName) { return NSRTFDTextDocumentType }
            else if workspace.type(Document.SimpleTextType, conformsToType: typeName) { return NSMacSimpleTextDocumentType }
            else if workspace.type(Document.Word97Type, conformsToType: typeName) { return NSDocFormatTextDocumentType }
            else if workspace.type(Document.Word2007Type, conformsToType: typeName) { return NSOfficeOpenXMLTextDocumentType }
            else if workspace.type(Document.Word2003XMLType, conformsToType: typeName) { return NSWordMLTextDocumentType }
            else if workspace.type(Document.OpenDocumentTextType, conformsToType: typeName) { return NSOpenDocumentTextDocumentType }
            else if workspace.type(kUTTypeHTML as String, conformsToType: typeName) { return NSHTMLTextDocumentType }
            else if workspace.type(kUTTypeWebArchive as String, conformsToType: typeName) { return NSWebArchiveTextDocumentType }
            else {
                NSException(name: NSInvalidArgumentException, reason: typeName + " is not a recognized document type.", userInfo: nil).raise()
                return NSPlainTextDocumentType // notreached
            }
        }()

        documentAttributes[NSDocumentTypeDocumentAttribute] = documentType
        if hasMultiplePages && scaleFactor != 1.0 {
            documentAttributes[NSViewZoomDocumentAttribute] = NSNumber(double: Double(scaleFactor) * 100.0)
        }
        documentAttributes[NSBackgroundColorDocumentAttribute] = backgroundColor
        
        var stringEncoding: NSStringEncoding?
        switch documentType {
        case NSPlainTextDocumentType:
            stringEncoding = encoding
            if (currentSaveOperation == .SaveOperation || currentSaveOperation == .SaveAsOperation) && (documentEncodingForSaving != UInt(NoStringEncoding)) {
                stringEncoding = documentEncodingForSaving
            }
            if stringEncoding == UInt(NoStringEncoding) {
                stringEncoding = suggestedDocumentEncoding()
            }
            documentAttributes[NSCharacterEncodingDocumentAttribute] = NSNumber(unsignedInteger: stringEncoding!)
            
        case NSHTMLTextDocumentType, NSWebArchiveTextDocumentType:
            var excludedElements = [String]()
            
            let defaults = NSUserDefaults.standardUserDefaults()
            if !defaults.boolForKey(UseXHTMLDocType) {
                excludedElements.append("XML")
            }
            if !defaults.boolForKey(UseTransitionalDocType) {
                excludedElements.appendContentsOf(["APPLET", "BASEFONT", "CENTER", "DIR", "FONT", "ISINDEX", "MENU", "S", "STRIKE", "U"])
            }
            if !defaults.boolForKey(UseEmbeddedCSS) {
                excludedElements.append("STYLE")
                if !defaults.boolForKey(UseInlineCSS) {
                    excludedElements.append("SPAN")
                }
            }
            if !defaults.boolForKey(PreserveWhitespace) {
                excludedElements.appendContentsOf(["Apple-converted-space", "Apple-converted-tab", "Apple-interchange-newline"])
            }
            documentAttributes[NSExcludedElementsDocumentAttribute] = excludedElements
            documentAttributes[NSCharacterEncodingDocumentAttribute] = defaults.objectForKey(HTMLEncoding)
            documentAttributes[NSPrefixSpacesDocumentAttribute] = NSNumber(integer: 2)
            
        default:
            break
        }

        // Set the text layout orientation for each page
        documentAttributes[NSTextLayoutSectionsAttribute] = (windowControllers.first as? DocumentWindowController)?.layoutOrientationSections()
        
        // Set the document properties, generically, going through key value coding
        self.dynamicType.documentPropertyToAttributeNameMappings.forEach { (property, attributeName) in
            if let value = valueForKey(property) {
                switch value {
                case let array as Array<AnyObject>:
                    if !array.isEmpty {
                        documentAttributes[attributeName] = array
                    }
                case let string as String:
                    if !string.isEmpty {
                        documentAttributes[attributeName] = string
                    }
                default:
                    documentAttributes[attributeName] = value
                }
            }
        }
        
        // finally, generate the actual NSFileWrapper
        let fileWrapper: NSFileWrapper
        let range = NSMakeRange(0, textStorage.length)
        if documentType == NSRTFDTextDocumentType
            || (documentType == NSPlainTextDocumentType && !openedIgnoringRichText) {	// We obtain a file wrapper from the text storage for RTFD (to produce a directory), or for true plain-text documents (to write out encoding in extended attributes)
                fileWrapper = try textStorage.fileWrapperFromRange(range, documentAttributes: documentAttributes) // returns NSFileWrapper

        } else {
            let data = try textStorage.dataFromRange(range, documentAttributes: documentAttributes) // returns NSData
            fileWrapper = NSFileWrapper(regularFileWithContents: data)
        }
        
        // and possibly set the string encoding
        if documentType == NSPlainTextDocumentType && (currentSaveOperation == .SaveOperation || currentSaveOperation == .SaveAsOperation) {
            encoding = stringEncoding!
        }
        
        return fileWrapper
    }

    override public func saveToURL(url: NSURL, ofType typeName: String, forSaveOperation saveOperation: NSSaveOperationType, completionHandler: (NSError?) -> Void) {
        /* When we save, we send a notification so that views that are currently coalescing undo actions can break that. This is done for two reasons, one technical and the other HI oriented.
        
        Firstly, since the dirty state tracking is based on undo, for a coalesced set of changes that span over a save operation, the changes that occur between the save and the next time the undo coalescing stops will not mark the document as dirty. Secondly, allowing the user to undo back to the precise point of a save is good UI.
        
        In addition we overwrite this method as a way to tell that the document has been saved successfully. If so, we set the save time parameters in the document.
        */

        windowControllers.forEach {
            // Note that we do the breakUndoCoalescing call even during autosave, which means the user's undo of long typing will take them back to the last spot an autosave occured. This might seem confusing, and a more elaborate solution may be possible (cause an autosave without having to breakUndoCoalescing), but since this change is coming late in Leopard, we decided to go with the lower risk fix.
            ($0 as? DocumentWindowController)?.breakUndoCoalescing()
        }
        
        performAsynchronousFileAccessUsingBlock { fileAccessCompletionHandler in
            self.currentSaveOperation = saveOperation
            super.saveToURL(url, ofType: typeName, forSaveOperation: saveOperation) { error in
                self.encodingForSaving = UInt(NoStringEncoding) // This is set during prepareSavePanel:, but should be cleared for future save operation without save panel
                fileAccessCompletionHandler()
                completionHandler(error)
            }
        }
    }

    override public func checkAutosavingSafety() throws {
        try super.checkAutosavingSafety()

        if fileURL == nil {
            return
        }
        // If the document is converted or lossy but can't be saved in its file type, we will need to save it in a different location or duplicate it anyway.  Therefore, we should tell the user that a writable type is required instead.
        if fileType != nil && (writableTypesForSaveOperation(.SaveAsOperation, ignoreTemporaryState: true) as! [String]).indexOf(fileType!) == nil {
           throw errorInTextEditDomainWithCode(TextEditSaveErrorWritableTypeRequired)
        } else if converted {
            throw errorInTextEditDomainWithCode(TextEditSaveErrorConvertedDocument)
        } else if lossy {
            throw errorInTextEditDomainWithCode(TextEditSaveErrorLossyDocument)
        }
    }
    
    override public func prepareSavePanel(savePanel: NSSavePanel) -> Bool {
        // If the document is a converted version of a document that existed on disk, set the default directory to the directory in which the source file (converted file) resided at the time the document was converted. If the document is plain text, we additionally add an encoding popup.
        if isRichText {
            return true
        }
        
        let addExtensionToNewPlainTextFiles = NSUserDefaults.standardUserDefaults().boolForKey(AddExtensionToNewPlainTextFiles)
        // If no encoding, figure out which encoding should be default in encoding popup, set as document encoding.
        let string = textStorage.string
        encodingForSaving = (encoding == UInt(NoStringEncoding) || !string.canBeConvertedToEncoding(encoding)) ? suggestedDocumentEncoding() : encoding
        
        var encodingPopup: NSPopUpButton?
        var extensionCheckbox: NSButton?
        let accessoryView = DocumentController.encodingAccessory(encodingForSaving, includeDefaultEntry: false, encodingPopUp: &encodingPopup, checkBox: &extensionCheckbox)
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        savePanel.accessoryView = accessoryView
        
        // Set up the checkbox
        extensionCheckbox?.title = NSLocalizedString("If no extension is provided, use \\U201c.txt\\U201d.", comment: "Checkbox indicating that if the user does not specify an extension when saving a plain text file, .txt will be used")
        extensionCheckbox?.toolTip = NSLocalizedString("Automatically append \\U201c.txt\\U201d to the file name if no known file name extension is provided.", comment: "Tooltip for checkbox indicating that if the user does not specify an extension when saving a plain text file, .txt will be used")
        extensionCheckbox?.state = addExtensionToNewPlainTextFiles ? 1 : 0
        extensionCheckbox?.action = "appendPlainTextExtensionChanged:"
        extensionCheckbox?.target = self
        
        if (addExtensionToNewPlainTextFiles) {
            savePanel.allowedFileTypes = [kUTTypePlainText as String]
            savePanel.allowsOtherFileTypes = true
        } else {
            // NSDocument defaults to setting the allowedFileType to kUTTypePlainText, which gives the fileName a ".txt" extension. We want don't want to append the extension for Untitled documents.
            // First we clear out the allowedFileType that NSDocument set. We want to allow anything, so we pass 'nil'. This will prevent NSSavePanel from appending an extension.
            //    [savePanel setAllowedFileTypes:nil];
            // If this document was previously saved, use the URL's name.
            var fileName: AnyObject?
            if let fileURL = fileURL {
                do {
                    try fileURL.getResourceValue(&fileName, forKey:NSURLNameKey)
                }
                catch { }
            }
            // If the document has not yet been saved, or we couldn't find the fileName, then use the displayName.
            savePanel.nameFieldStringValue = (fileName as? String) ?? displayName
        }
        
        // Further set up the encoding popup
        if encodingPopup != nil && encodingPopup!.numberOfItems * string.characters.count < 5000000 {	// Otherwise it's just too slow; would be nice to make this more dynamic. With large docs and many encodings, the items just won't be validated.
            for itemIndex in 0 ..< encodingPopup!.numberOfItems {
                // NOTE: the last two items in the popup are NOT string encodings, they are a separator and a "Customize..." item, so we don't want to iterate over them
                if let menuItem = encodingPopup!.itemAtIndex(itemIndex), let menuItemStringEncoding = (menuItem.representedObject?.unsignedIntegerValue as NSStringEncoding?) {
                    switch menuItemStringEncoding {
                    case UInt(NoStringEncoding), NSUnicodeStringEncoding, NSUTF8StringEncoding, NSNonLossyASCIIStringEncoding: // Hardwire some encodings known to allow any content
                        menuItem.enabled = true
                    case let convertableEncoding where string.canBeConvertedToEncoding(convertableEncoding):
                        menuItem.enabled = true
                    default:
                        menuItem.enabled = false
                    }
                }
            }
        }
        encodingPopup?.action = "encodingPopupChanged:"
        encodingPopup?.target = self
    
        return true
    }


    // MARK: internal methods
    func readFromURL(url: NSURL, ofType typeName: String, encoding desiredEncoding: NSStringEncoding, ignoreRTF: Bool, ignoreHTML: Bool) throws {
        var options = [String : AnyObject]()
        
        fileTypeToSet = nil
        
        undoManager?.disableUndoRegistration()
        
        options[NSBaseURLDocumentOption] = url
        if desiredEncoding != UInt(NoStringEncoding) {
            options[NSCharacterEncodingDocumentOption] = desiredEncoding
        }
        encoding = desiredEncoding
        
        // generalize the passed-in type to a type we support.  for instance, generalize "public.xml" to "public.txt"
        var readableTypeName = self.dynamicType.readableTypeForType(typeName) ?? (kUTTypeText as String)
        
        // check type to see if we should load the document as plain. Note that this check isn't always conclusive, which is why we do another check below, after the document has been loaded (and correctly categorized).
        let workspace = NSWorkspace.sharedWorkspace() // question: why use NSWorkspace here for UTs and UTTypeConformsTo() elsewhere?
        if (ignoreRTF && (workspace.type(readableTypeName, conformsToType:kUTTypeRTF as String) || workspace.type(readableTypeName, conformsToType: Document.Word2003XMLType as String)))
            || (ignoreHTML && workspace.type(readableTypeName, conformsToType:kUTTypeHTML as String))
            || openedIgnoringRichText {
                options[NSDocumentTypeDocumentOption] = NSPlainTextDocumentType // Force plain
                readableTypeName = kUTTypeText as String
                openedIgnoringRichText = true
        }
        
        //
        // load the actual file
        //
        var documentAttributes: NSDictionary?
        textStorage.mutableString.setString("")
        do {
            // Remove the layout managers while loading the text; mutableCopy retains the array so the layout managers aren't released
            let layoutManagersRemovedDuringLoadingForSpeed = textStorage.layoutManagers
            textStorage.layoutManagers.forEach { textStorage.removeLayoutManager($0) }
            textStorage.beginEditing()
            defer {
                textStorage.endEditing()
                layoutManagersRemovedDuringLoadingForSpeed.forEach { textStorage.addLayoutManager($0) } // Add the layout managers back
            }
            
            try textStorage.readFromURL(url, options: options, documentAttributes: &documentAttributes, error: ())
            
            var documentType = (documentAttributes?[NSDocumentTypeDocumentAttribute] as? String) ?? (kUTTypeText as String)
            
            // First check to see if the document was rich and should have been loaded as plain
            if (options[NSDocumentTypeDocumentOption] as? String) != NSPlainTextDocumentType
                && ((ignoreHTML && documentType == NSHTMLTextDocumentType) || (ignoreRTF && (documentType == NSRTFTextDocumentType || documentType == NSWordMLTextDocumentType)))
            {
                // load again, this time with FEELING
                textStorage.endEditing()
                textStorage.mutableString.setString("")
                options[NSDocumentTypeDocumentOption] = NSPlainTextDocumentType
                readableTypeName = kUTTypeText as String
                openedIgnoringRichText = true
                
                textStorage.beginEditing()
                try! textStorage.readFromURL(url, options: options, documentAttributes: &documentAttributes, error: ()) // didn't fail first time, so won't fail this time
                documentType = (documentAttributes?[NSDocumentTypeDocumentAttribute] as? String) ?? (kUTTypeText as String)
            }
            
            if let newFileType = Document.textDocumentTypeToTextEditDocumentTypeMappingTable[documentType] {
                readableTypeName = newFileType
            } else {
                readableTypeName = kUTTypeRTF as String // Hmm, a new type in the Cocoa text system. Treat it as rich. ??? Should set the converted flag too?
            }
            if !Document.isRichTextType(readableTypeName) { // give plain text documents the default font
                applyDefaultTextAttributes(false)
            }
            
            fileType = readableTypeName
            // If we're reverting, NSDocument will set the file type behind out backs. This enables restoring that type.
            fileTypeToSet = readableTypeName
        }
        
        // set up window according to 'documentAttributes'
        let encodingValue = documentAttributes?[NSCharacterEncodingDocumentAttribute] as? NSNumber
        encoding = encodingValue?.unsignedIntegerValue ?? UInt(NoStringEncoding)
        
        if let convertedDocumentValue = documentAttributes?[NSConvertedDocumentAttribute] {
            converted = convertedDocumentValue.integerValue > 0 // Indicates filtered
            lossy = convertedDocumentValue.integerValue < 0 // Indicates lossily loaded
        }
        
        // If the document has a stored value for view mode, use it. Otherwise wrap to window.
        if let viewModeValue = documentAttributes?[NSViewModeDocumentAttribute] as? NSNumber {
            hasMultiplePages = viewModeValue.integerValue == 1
            if let zoomValue = documentAttributes?[NSViewZoomDocumentAttribute] as? NSNumber {
                scaleFactor = CGFloat(zoomValue.doubleValue) / 100.0
            }
        } else {
            hasMultiplePages = false
        }
        
        // printinfo
        willChangeValueForKey("printInfo")
        if let leftMarginValue = documentAttributes?[NSLeftMarginDocumentAttribute] as? NSNumber { printInfo.leftMargin = CGFloat(leftMarginValue.doubleValue) }
        if let rightMarginValue = documentAttributes?[NSRightMarginDocumentAttribute] as? NSNumber { printInfo.rightMargin = CGFloat(rightMarginValue.doubleValue) }
        if let bottomMarginValue = documentAttributes?[NSBottomMarginDocumentAttribute] as? NSNumber { printInfo.bottomMargin = CGFloat(bottomMarginValue.doubleValue) }
        if let topMarginValue = documentAttributes?[NSTopMarginDocumentAttribute] as? NSNumber { printInfo.topMargin = CGFloat(topMarginValue.doubleValue) }
        didChangeValueForKey("printInfo")
        
        // window / paper size
        let documentViewSize = (documentAttributes?[NSViewSizeDocumentAttribute] as? NSValue)?.sizeValue
        var documentPaperSize = (documentAttributes?[NSPaperSizeDocumentAttribute] as? NSValue)?.sizeValue
        if documentPaperSize == .zero { documentPaperSize = nil } // Protect against some old documents with 0 paper size
        
        if let documentViewSize = documentViewSize {
            viewSize = documentViewSize
            if let documentPaperSize = documentPaperSize { paperSize = documentPaperSize }

            // no ViewSize...
        } else if var documentPaperSize = documentPaperSize { // see if PaperSize should be used as ViewSize; if so, we also have some tweaking to do on it
            
            // pre MacOSX versions of TextEdit wrote out the view (window) size in PaperSize. If we encounter a non-MacOSX RTF file, and it's written by TextEdit, use PaperSize as ViewSize
            if let documentVersion = (documentAttributes?[NSCocoaVersionDocumentAttribute] as? NSNumber)?.integerValue where documentVersion < 100 {	// Indicates old RTF file; value described in AppKit/NSAttributedString.h
                if documentPaperSize.width > 0 && documentPaperSize.height > 0 && !hasMultiplePages {
                    let oldEditPaddingCompensation: CGFloat = 12.0
                    documentPaperSize.width -= oldEditPaddingCompensation
                    viewSize = documentPaperSize
                }
            } else {
                paperSize = documentPaperSize
            }
        }

        hyphenationFactor =  (documentAttributes?[NSHyphenationFactorDocumentAttribute] as? NSNumber)?.floatValue ?? 0
        backgroundColor = (documentAttributes?[NSBackgroundColorDocumentAttribute] as? NSColor) ?? NSColor.whiteColor()
        
        // Set the document properties, generically, going through key value coding
        self.dynamicType.documentPropertyToAttributeNameMappings.forEach { (property, attributeName) in
            setValue(documentAttributes?[attributeName] as? String, forKey: property)	// OK to set nil to clear
        }
        
        readOnly = ((documentAttributes?[NSReadOnlyDocumentAttribute] as? NSNumber)?.integerValue ?? 0) > 0
        originalOrientationSections = documentAttributes?[NSTextLayoutSectionsAttribute] as? [NSDictionary]
        usesScreenFonts = isRichText ? ((documentAttributes?[NSUsesScreenFontsDocumentAttribute] as? NSNumber)?.boolValue ?? false) : true
        
        undoManager?.enableUndoRegistration()
    }
    
    
    
    // MARK: private methods
    internal class func readableTypeForType(type: String) -> String? {
        // There is a partial order on readableTypes given by UTTypeConformsTo. We linearly extend the partial order to a total order using <.
        // Therefore we can compute the ancestor with greatest level (furthest from root) by linear search in the resulting array.
        // Why do we have to do this?  Because type might conform to multiple readable types, such as "public.rtf" and "public.text" and "public.data"
        // and we want to find the most specialized such type.
        return topologicallySortedReadableTypes.filter { UTTypeConformsTo(type, $0) }.first
    }
    private static let topologicallySortedReadableTypes: [String] = Document.readableTypes().sort {
        if $0 == $1 || UTTypeConformsTo($1, $0) { return false }
        if UTTypeConformsTo($0, $1) { return true }
        return ObjectIdentifier($0) < ObjectIdentifier($1) // ensure sort is stable even for unrelated types
    }
    
    
    internal class func isRichTextType(typeName: String) -> Bool {
        // We map all plain text documents to public.text.  Therefore a document is rich iff its type is not public.text.
        return typeName != (kUTTypeText as String)
    }
    

//    // MARK: private properties
//    private var currentSaveOperation: NSSaveOperationType? // So we can know whether to use documentEncodingForSaving or documentEncoding in -fileWrapperOfType:error:

    
    
    
    // MARK: private static properties

    // Document properties management
    private static let documentPropertyToAttributeNameMappings: [String : String] = [ // Table mapping document property keys "company", etc, to text system document attribute keys (NSCompanyDocumentAttribute, etc)
        "company": NSCompanyDocumentAttribute,
        "author": NSAuthorDocumentAttribute,
        "keywords": NSKeywordsDocumentAttribute,
        "copyright": NSCopyrightDocumentAttribute,
        "title": NSTitleDocumentAttribute,
        "subject": NSSubjectDocumentAttribute,
        "comment": NSCommentDocumentAttribute,
    ]
    private static let knownDocumentProperties = documentPropertyToAttributeNameMappings.keys
    
    // Dictionary which maps Cocoa text system document identifiers (as declared in AppKit/NSAttributedString.h) to document types declared in TextEdit's Info.plist.
    private static let textDocumentTypeToTextEditDocumentTypeMappingTable: [String : String] = [
        NSPlainTextDocumentType : kUTTypeText as String,
        NSRTFTextDocumentType : kUTTypeRTF as String,
        NSRTFDTextDocumentType : kUTTypeRTFD as String,
        NSMacSimpleTextDocumentType : SimpleTextType,
        NSHTMLTextDocumentType : kUTTypeHTML as String,
        NSDocFormatTextDocumentType : Word97Type,
        NSOfficeOpenXMLTextDocumentType : Word2007Type,
        NSWordMLTextDocumentType : Word2003XMLType,
        NSOpenDocumentTextDocumentType : OpenDocumentTextType,
        NSWebArchiveTextDocumentType : kUTTypeWebArchive as String,
    ]
    private static let SimpleTextType = "com.apple.traditional-mac-plain-text"
    private static let Word97Type = "com.microsoft.word.doc"
    private static let Word2007Type = "org.openxmlformats.wordprocessingml.document"
    private static let Word2003XMLType = "com.microsoft.word.wordml"
    private static let OpenDocumentTextType = "org.oasis-open.opendocument.text"
    
}

