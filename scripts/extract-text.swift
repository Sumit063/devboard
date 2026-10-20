// Prints the plain text of a PDF using PDFKit (ships with macOS, no dependencies).
// Usage: swift scripts/extract-text.swift resume.pdf
import Foundation
import PDFKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: extract-text.swift <file.pdf>\n".data(using: .utf8)!)
    exit(2)
}
guard let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1])), let text = doc.string, !text.isEmpty else {
    FileHandle.standardError.write("Could not read text from that PDF (is it a scanned image?).\n".data(using: .utf8)!)
    exit(1)
}
print(text)
