import ImageIO
import KitbagCore
import QuickLook
import QuickLookThumbnailing
import SwiftUI

/// The photos and files kept with a note, in a row under the text. A tap opens one in Quick Look; holding offers to
/// share or remove it.
struct AttachmentStrip: View {
  @Environment(NoteStore.self) private var store

  let noteID: UUID
  let attachments: [NoteAttachment]
  @Binding var preview: URL?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 12) {
        ForEach(attachments) { attachment in
          let url = store.url(for: attachment, in: noteID)
          AttachmentTile(attachment: attachment, url: url)
            .onTapGesture { preview = url }
            .contextMenu {
              Button {
                preview = url
              } label: {
                Label {
                  Text("Open", tableName: "Notes")
                } icon: {
                  Image(systemName: "eye")
                }
              }
              ShareLink(item: url) {
                Label {
                  Text("Share", tableName: "Notes")
                } icon: {
                  Image(systemName: "square.and.arrow.up")
                }
              }
              Button(role: .destructive) {
                store.removeAttachment(attachment.id, from: noteID)
              } label: {
                Label {
                  Text("Remove attachment", tableName: "Notes")
                } icon: {
                  Image(systemName: "trash")
                }
              }
            }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .background(.bar)
  }
}

/// One attachment: a picture or the file's preview, and its name below.
struct AttachmentTile: View {
  let attachment: NoteAttachment
  let url: URL

  @State private var thumbnail: UIImage?

  private let side: CGFloat = 76

  var body: some View {
    VStack(spacing: 4) {
      ZStack {
        RoundedRectangle(cornerRadius: 12).fill(.quaternary)
        if let thumbnail {
          if attachment.isImage {
            Image(uiImage: thumbnail).resizable().scaledToFill()
          } else {
            Image(uiImage: thumbnail).resizable().scaledToFit()
          }
        } else {
          Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
        }
      }
      .frame(width: side, height: side)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5))
      Text(attachment.name)
        .font(.caption2).lineLimit(2).multilineTextAlignment(.center).frame(width: side)
      Text(attachment.byteCount.formatted(.byteCount(style: .file)))
        .font(.caption2).foregroundStyle(.tertiary)
    }
    .task(id: attachment.id) { thumbnail = await Thumbnails.image(for: attachment, at: url, side: side) }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }

  private var symbol: String {
    switch (attachment.storedName as NSString).pathExtension.lowercased() {
    case "pdf": "doc.richtext"
    case "zip", "gz", "tar": "doc.zipper"
    case "txt", "md", "rtf": "doc.text"
    case "mp3", "m4a", "wav": "waveform"
    case "mov", "mp4", "m4v": "film"
    default: attachment.isImage ? "photo" : "doc"
    }
  }
}

/// Small pictures of attachments, made off the main thread. A picture is cut down with Image I/O, which does not load
/// the whole image; other files ask Quick Look for the preview it would show.
enum Thumbnails {
  static func image(for attachment: NoteAttachment, at url: URL, side: CGFloat) async -> UIImage? {
    let scale = 3.0
    if attachment.isImage {
      return await Task.detached(priority: .utility) {
        let options: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: side * scale,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
      }.value
    }
    let request = QLThumbnailGenerator.Request(
      fileAt: url, size: CGSize(width: side, height: side), scale: scale, representationTypes: .thumbnail)
    return await withCheckedContinuation { continuation in
      QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
        continuation.resume(returning: representation?.uiImage)
      }
    }
  }
}
