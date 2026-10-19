import SwiftUI
import UIKit

/// A scroll view that zooms the way Photos and Maps do: pinching zooms around the point between the fingers, a double tap
/// zooms in and back out, and it pans while zoomed. The content is laid out again at the zoomed size rather than stretched,
/// so text and lines stay sharp at any zoom.
///
/// SwiftUI's own `MagnifyGesture` next to a `ScrollView` cannot do this: it changes the size but not where the page sits
/// under the fingers, and it fights the scroll gesture, which made the page jump.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
  /// The zoom, 1 being the width of the screen. Changing it (the buttons) zooms around the middle of what is shown.
  @Binding var zoom: CGFloat
  var range: ClosedRange<CGFloat> = 1...4
  /// Height over width of the content, which is as wide as the screen at zoom 1.
  let aspectRatio: CGFloat
  /// The content at a size. It is not in the SwiftUI environment of the view around it, so anything it needs from there
  /// has to be passed in.
  @ViewBuilder let content: (CGSize) -> Content

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> ZoomScrollView {
    let scrollView = ZoomScrollView()
    let coordinator = context.coordinator
    coordinator.scrollView = scrollView
    scrollView.backgroundColor = .clear
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.alwaysBounceHorizontal = false
    scrollView.alwaysBounceVertical = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.addSubview(coordinator.hosting.view)
    coordinator.hosting.view.backgroundColor = .clear

    let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinch(_:)))
    pinch.delegate = coordinator
    scrollView.addGestureRecognizer(pinch)
    let double = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.doubleTap(_:)))
    double.numberOfTapsRequired = 2
    double.cancelsTouchesInView = false
    double.delegate = coordinator
    scrollView.addGestureRecognizer(double)

    scrollView.onLayout = { [weak coordinator] in coordinator?.layoutChanged() }
    return scrollView
  }

  func updateUIView(_ scrollView: ZoomScrollView, context: Context) {
    context.coordinator.update(with: self)
  }

  @MainActor
  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var parent: ZoomableScrollView
    let hosting: UIHostingController<Content>
    weak var scrollView: ZoomScrollView?
    private var zoom: CGFloat = 1
    private var startZoom: CGFloat = 1
    /// The point of the content, unzoomed, that a pinch started on.
    private var anchor = CGPoint.zero
    private var width: CGFloat = 0

    init(_ parent: ZoomableScrollView) {
      self.parent = parent
      hosting = UIHostingController(rootView: parent.content(CGSize(width: 1, height: parent.aspectRatio)))
      hosting.safeAreaRegions = []
    }

    /// Draws again with new content, or moves to the zoom a button asked for.
    func update(with parent: ZoomableScrollView) {
      self.parent = parent
      if abs(parent.zoom - zoom) > 0.001, let scrollView {
        let middle = CGPoint(x: scrollView.bounds.midX - scrollView.bounds.minX, y: scrollView.bounds.height / 2)
        apply(zoom: parent.zoom, keeping: unzoomed(middle), under: middle)
      } else {
        apply(zoom: zoom, keeping: nil, under: nil)
      }
    }

    /// The width changed (a turn of the phone): the page is as wide as the screen at zoom 1.
    func layoutChanged() {
      guard let scrollView, abs(scrollView.bounds.width - width) > 0.5 else { return }
      apply(zoom: zoom, keeping: nil, under: nil)
    }

    private func unzoomed(_ viewPoint: CGPoint) -> CGPoint {
      guard let scrollView else { return .zero }
      return CGPoint(
        x: (scrollView.contentOffset.x + viewPoint.x) / zoom, y: (scrollView.contentOffset.y + viewPoint.y) / zoom)
    }

    /// Lays the content out at `zoom`, and scrolls so that the point of the content `keeping` stays under `viewPoint`.
    private func apply(zoom newZoom: CGFloat, keeping contentPoint: CGPoint?, under viewPoint: CGPoint?) {
      guard let scrollView, scrollView.bounds.width > 0 else { return }
      width = scrollView.bounds.width
      zoom = min(max(newZoom, parent.range.lowerBound), parent.range.upperBound)
      let size = CGSize(width: width * zoom, height: width * zoom * parent.aspectRatio)
      hosting.rootView = parent.content(size)
      hosting.view.frame = CGRect(origin: .zero, size: size)
      scrollView.contentSize = size
      // A page that is shorter than the screen sits in the middle of it, not at the top.
      let spare = max((scrollView.bounds.height - size.height) / 2, 0)
      scrollView.contentInset = UIEdgeInsets(top: spare, left: 0, bottom: spare, right: 0)
      var offset = scrollView.contentOffset
      if let contentPoint, let viewPoint {
        offset = CGPoint(x: contentPoint.x * zoom - viewPoint.x, y: contentPoint.y * zoom - viewPoint.y)
      }
      scrollView.contentOffset = CGPoint(
        x: min(max(offset.x, 0), max(size.width - scrollView.bounds.width, 0)),
        y: min(max(offset.y, -spare), max(size.height - scrollView.bounds.height + spare, -spare)))
    }

    @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
      guard let scrollView else { return }
      let location = recognizer.location(in: scrollView)
      let viewPoint = CGPoint(x: location.x - scrollView.bounds.minX, y: location.y - scrollView.bounds.minY)
      switch recognizer.state {
      case .began:
        startZoom = zoom
        anchor = unzoomed(viewPoint)
      case .changed:
        apply(zoom: startZoom * recognizer.scale, keeping: anchor, under: viewPoint)
        parent.zoom = zoom
      default:
        parent.zoom = zoom
      }
    }

    @objc func doubleTap(_ recognizer: UITapGestureRecognizer) {
      guard let scrollView else { return }
      let location = recognizer.location(in: scrollView)
      let viewPoint = CGPoint(x: location.x - scrollView.bounds.minX, y: location.y - scrollView.bounds.minY)
      let target = zoom > parent.range.lowerBound + 0.05 ? parent.range.lowerBound : min(2.5, parent.range.upperBound)
      apply(zoom: target, keeping: unzoomed(viewPoint), under: viewPoint)
      parent.zoom = zoom
    }

    /// The pinch and the double tap work together with the scroll view's own pan and with taps inside the content.
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool { true }
  }
}

/// A scroll view that says when it was laid out again, so that a change of width can redraw the content.
final class ZoomScrollView: UIScrollView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}
