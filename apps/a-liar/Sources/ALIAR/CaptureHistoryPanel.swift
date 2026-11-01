import Foundation
import SwiftUI
import ALIARCore

struct CaptureHistoryPanel: View {
    @ObservedObject var lab: LabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("CAPTURE HISTORY", systemImage: "photo.on.rectangle.angled")
                    .font(.headline.monospaced())
                Spacer()
                Text("\(lab.captureHistory.count) photographs")
                    .font(.subheadline.monospaced()).foregroundStyle(.secondary)
            }
            Text("Every successful manual and PGC photograph is logged locally. Old JPEG files may expire, but their log entries remain.")
                .font(.callout).foregroundStyle(.secondary)
            if let warning = lab.historyWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.callout)
            }
            if lab.captureHistory.isEmpty {
                Text("No photos captured yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lab.captureHistory) { record in
                            HStack(spacing: 12) {
                                Text(record.capturedAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.callout.monospaced()).frame(width: 185, alignment: .leading)
                                Text(record.role.rawValue.uppercased())
                                    .font(.callout.monospaced().bold()).frame(width: 85, alignment: .leading)
                                Text(record.origin == .manual ? "MANUAL" : "PGC")
                                    .font(.caption.monospaced()).frame(width: 65, alignment: .leading)
                                Text(record.dimensions.label)
                                    .font(.caption.monospaced()).frame(width: 105, alignment: .leading)
                                Text("\(record.byteCount) bytes")
                                    .font(.caption.monospaced()).frame(width: 100, alignment: .leading)
                                if let session = record.session {
                                    Text("session \(session)").font(.caption.monospaced())
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 0)
                                if lab.isHistoryPhotoAvailable(record) {
                                    Button("Reveal") { lab.revealHistoryPhoto(record) }
                                } else {
                                    Text("JPEG expired").foregroundStyle(.tertiary).font(.caption)
                                }
                            }
                            .frame(minHeight: 38)
                            Divider()
                        }
                    }
                }
                .frame(height: min(280, CGFloat(lab.captureHistory.count * 39 + 10)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}
