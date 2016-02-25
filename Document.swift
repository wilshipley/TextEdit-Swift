//
//  Document.swift
//  TextEdit
//
//  Created by William Shipley on 2/23/16.
//
//

import Cocoa

extension Document {
    
    // MARK: internal properties
    // Dictionary which maps Cocoa text system document identifiers (as declared in AppKit/NSAttributedString.h) to document types declared in TextEdit's Info.plist.

    // FIXME: We can't comment this in until we can make it private, so we have to mave all the code that uses it into Swift first:
    #if WAITING_FOR_OTHER_CODE
    internal static let SimpleTextType = "com.apple.traditional-mac-plain-text"
    internal static let Word97Type = "com.microsoft.word.doc"
    internal static let Word2007Type = "org.openxmlformats.wordprocessingml.document"
    internal static let Word2003XMLType = "com.microsoft.word.wordml"
    internal static let OpenDocumentTextType = "org.oasis-open.opendocument.text"
    internal static let textDocumentTypeToTextEditDocumentTypeMappingTable: [String : String] = [
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
    #endif
    
    
    // MARK: internal methods
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
    
}

