import KitbagCore
import SwiftUI

/// One class on one line: a colour dot, the time, the course and the room. A class that is over is dimmed.
struct ClassLine: View {
  let slot: Timetable.Slot
  var isOver = false

  var body: some View {
    HStack(spacing: 10) {
      Circle().fill(slot.course.color.blockColor).frame(width: 12, height: 12)
        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
      Text("\(slot.meeting.start.twelveHourText)–\(slot.meeting.end.twelveHourText)")
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 88, alignment: .leading)
      Text(slot.course.code).font(.subheadline.weight(.medium))
      Spacer(minLength: 8)
      Text(slot.meeting.location).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
    }
    .opacity(isOver ? 0.4 : 1)
    .accessibilityElement(children: .combine)
  }
}
