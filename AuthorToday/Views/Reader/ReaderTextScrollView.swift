import SwiftUI
import UIKit

/// Own UITextView scroll surface — reliable offset tracking and restore (unlike SwiftUI ScrollView + PreferenceKey).
struct ReaderTextScrollView: UIViewRepresentable {
    let text: String
    let font: UIFont
    let textColor: UIColor
    let lineSpacing: CGFloat
    let contentInset: UIEdgeInsets
    /// 0...1 position within the chapter to restore once layout is ready.
    var restoreFraction: Double
    var restoreGeneration: Int
    var onScroll: (_ offsetY: Double, _ fraction: Double, _ charOffset: Int) -> Void
    /// Called when layout knows whether the chapter fits without scrolling.
    var onContentFits: ((_ fits: Bool) -> Void)? = nil
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll, onContentFits: onContentFits, onTap: onTap)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.showsVerticalScrollIndicator = true
        tv.textContainerInset = contentInset
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = false
        applyContent(to: tv)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        tv.addGestureRecognizer(tap)
        context.coordinator.textView = tv
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onContentFits = onContentFits
        context.coordinator.onTap = onTap
        context.coordinator.textLength = text.count

        let contentChanged = tv.attributedText?.string != text
            || abs((tv.font?.pointSize ?? 0) - font.pointSize) > 0.1
        if contentChanged {
            // Preserve place in chapter across text/font reflow. Setting attributedText
            // resets offset to 0 and would otherwise wipe saved progress via scroll callbacks.
            // Prefer the live offset over a stale restoreFraction from chapter open — otherwise
            // a reflow after reading to 100% snaps back to the old restore point (~30%).
            let maxYBefore = max(tv.contentSize.height - tv.bounds.height, 1)
            let preservedFraction = min(max(Double(tv.contentOffset.y) / Double(maxYBefore), 0), 1)
            context.coordinator.isProgrammaticScroll = true
            applyContent(to: tv)
            context.coordinator.isProgrammaticScroll = false
            let target = preservedFraction > 0.005 ? preservedFraction : restoreFraction
            if target > 0.005 {
                context.coordinator.pendingFraction = target
                context.coordinator.scheduleRestore(on: tv)
            } else {
                context.coordinator.scheduleFitsCheck(on: tv)
            }
        } else {
            tv.textContainerInset = contentInset
            context.coordinator.scheduleFitsCheck(on: tv)
        }

        if restoreGeneration != context.coordinator.appliedRestoreGeneration,
           restoreFraction > 0.005 {
            context.coordinator.pendingFraction = restoreFraction
            context.coordinator.appliedRestoreGeneration = restoreGeneration
            context.coordinator.scheduleRestore(on: tv)
        }
    }

    private func applyContent(to tv: UITextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        tv.attributedText = NSAttributedString(string: text, attributes: attrs)
        tv.typingAttributes = attrs
        tv.font = font
        tv.textColor = textColor
        tv.textContainerInset = contentInset
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onScroll: (Double, Double, Int) -> Void
        var onContentFits: ((Bool) -> Void)?
        var onTap: () -> Void
        var textLength: Int = 0
        var pendingFraction: Double = 0
        var appliedRestoreGeneration: Int = -1
        var isProgrammaticScroll = false
        weak var textView: UITextView?
        private var restoreAttempts = 0
        private var fitsAttempts = 0
        private var lastReportedFits: Bool?

        init(
            onScroll: @escaping (Double, Double, Int) -> Void,
            onContentFits: ((Bool) -> Void)?,
            onTap: @escaping () -> Void
        ) {
            self.onScroll = onScroll
            self.onContentFits = onContentFits
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isProgrammaticScroll else { return }
            let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 1)
            let y = Double(scrollView.contentOffset.y)
            let fraction = min(max(y / maxY, 0), 1)
            let charOffset = Int((Double(textLength) * fraction).rounded())
            onScroll(y, fraction, charOffset)
            reportFits(scrollView.contentSize.height - scrollView.bounds.height < 48)
        }

        func scheduleRestore(on tv: UITextView) {
            restoreAttempts = 0
            tryRestore(on: tv)
        }

        func scheduleFitsCheck(on tv: UITextView) {
            fitsAttempts = 0
            checkFits(on: tv)
        }

        private func checkFits(on tv: UITextView) {
            tv.layoutIfNeeded()
            let overflow = tv.contentSize.height - tv.bounds.height
            // Wait until layout has a real height.
            if tv.contentSize.height < 20, fitsAttempts < 20 {
                fitsAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak tv] in
                    guard let self, let tv else { return }
                    self.checkFits(on: tv)
                }
                return
            }
            reportFits(overflow < 48)
        }

        private func reportFits(_ fits: Bool) {
            guard lastReportedFits != fits else { return }
            lastReportedFits = fits
            onContentFits?(fits)
        }

        private func tryRestore(on tv: UITextView) {
            tv.layoutIfNeeded()
            let maxY = tv.contentSize.height - tv.bounds.height
            if maxY < 40, restoreAttempts < 20 {
                restoreAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak tv] in
                    guard let self, let tv else { return }
                    self.tryRestore(on: tv)
                }
                return
            }
            // Short chapter: nothing to restore, but still report "at end".
            if maxY <= 1 || pendingFraction <= 0.005 {
                pendingFraction = 0
                reportFits(maxY < 48)
                return
            }
            let y = CGFloat(pendingFraction) * max(maxY, 1)
            isProgrammaticScroll = true
            tv.setContentOffset(CGPoint(x: 0, y: min(max(y, 0), maxY)), animated: false)
            isProgrammaticScroll = false
            let appliedY = Double(tv.contentOffset.y)
            let appliedFraction = min(max(appliedY / max(Double(maxY), 1), 0), 1)
            let charOffset = Int((Double(textLength) * appliedFraction).rounded())
            onScroll(appliedY, appliedFraction, charOffset)
            pendingFraction = 0
            reportFits(false)
        }
    }
}
