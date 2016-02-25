//
//  Document.swift
//  TextEdit
//
//  Created by William Shipley on 2/23/16.
//
//

import Cocoa

extension Document {
    
    // MARK: NSDocument
    
    
    
    
    // MARK: internal methods
    func readFromURL(url: NSURL, ofType typeName: String, encoding: NSStringEncoding, ignoreRTF: Bool, ignoreHTML: Bool) throws {
        var options = [String : AnyObject]()
        
        fileTypeToSet = nil
        
        undoManager?.disableUndoRegistration()
        
        options[NSBaseURLDocumentOption] = url
        if encoding != UInt(NoStringEncoding) {
            options[NSCharacterEncodingDocumentOption] = encoding
        }
        setEncoding(encoding)
        
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
            
            var docType = (documentAttributes?[NSDocumentTypeDocumentAttribute] as? String) ?? (kUTTypeText as String)
            
            // First check to see if the document was rich and should have been loaded as plain
            if (options[NSDocumentTypeDocumentOption] as? String) != NSPlainTextDocumentType
                && ((ignoreHTML && docType == NSHTMLTextDocumentType) || (ignoreRTF && (docType == NSRTFTextDocumentType || docType == NSWordMLTextDocumentType)))
            {
                // load again, this time with FEELING
                textStorage.endEditing()
                textStorage.mutableString.setString("")
                options[NSDocumentTypeDocumentOption] = NSPlainTextDocumentType
                readableTypeName = kUTTypeText as String
                openedIgnoringRichText = true
                
                textStorage.beginEditing()
                try! textStorage.readFromURL(url, options: options, documentAttributes: &documentAttributes, error: ()) // didn't fail first time, so won't fail this time
                docType = (documentAttributes?[NSDocumentTypeDocumentAttribute] as? String) ?? (kUTTypeText as String)
            }
            
            if let newFileType = Document.textDocumentTypeToTextEditDocumentTypeMappingTable[docType] {
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
        setEncoding(encodingValue?.unsignedIntegerValue ?? UInt(NoStringEncoding))
        
        if let convertedDocumentValue = documentAttributes?[NSConvertedDocumentAttribute] {
            setConverted(convertedDocumentValue.integerValue > 0)	// Indicates filtered
            setLossy(convertedDocumentValue.integerValue < 0)	// Indicates lossily loaded
        }
        
        // If the document has a stored value for view mode, use it. Otherwise wrap to window.
        if let viewModeValue = documentAttributes?[NSViewModeDocumentAttribute] as? NSNumber {
            hasMultiplePages = viewModeValue.integerValue == 1
            if let zoomValue = documentAttributes?[NSViewZoomDocumentAttribute] as? NSNumber {
                setScaleFactor(CGFloat(zoomValue.doubleValue) / 100.0)
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
    

    
    // MARK: private properties

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

