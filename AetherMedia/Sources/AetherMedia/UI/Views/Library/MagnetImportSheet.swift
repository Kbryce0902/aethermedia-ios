import SwiftUI
import UIKit

@MainActor
public struct MagnetImportSheet: View {
    public let onMagnetImported: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var magnetText = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var importTask: Task<Void, Never>?
    public init(onMagnetImported: @escaping (String) async throws -> Void) { self.onMagnetImported = onMagnetImported }
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Paste a v1 magnet link or SHA1 info-hash to add it to your Real-Debrid cloud.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    TextEditor(text: $magnetText).frame(height: 140).padding(8)
                        .liquidGlass(style: .card, cornerRadius: 14)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    if let hash = SourceStream.extractHash(from: magnetText) {
                        Label("Hash: \(hash.prefix(12))…", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.orange).font(.footnote) }
                    Button { if let text = UIPasteboard.general.string { magnetText = text } } label: {
                        Label("Paste Clipboard", systemImage: "doc.on.clipboard").frame(minHeight: 44)
                    }
                    Button {
                        guard let magnet = SourceStream.normalizedMagnet(magnetText) else { return }
                        isImporting = true
                        errorMessage = nil
                        importTask = Task {
                            do {
                                try await onMagnetImported(magnet)
                                try Task.checkCancellation()
                                dismiss()
                            } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
                            isImporting = false
                        }
                    } label: {
                        HStack { if isImporting { ProgressView() }; Text(isImporting ? "Adding…" : "Add to Cloud") }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent)
                        .disabled(SourceStream.normalizedMagnet(magnetText) == nil || isImporting)
                }.padding(20)
            }
            .navigationTitle("Import Magnet").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onDisappear { importTask?.cancel() }
        }
    }
}
