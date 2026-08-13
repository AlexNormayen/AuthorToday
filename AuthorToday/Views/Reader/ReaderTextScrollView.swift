import SwiftUI
import UIKit

/// Own UITextView scroll surface — reliable offset tracking and restore (unlike SwiftUI ScrollView + PreferenceKey).
struct ReaderTextScrollView: UIViewRepresentable {
    let text: String
    /// Chapter name prepended at the top of `text` — rendered bold.
    var chapterHeading: String = ""
    let font: UIFont
    let textColor: UIColor
    let lineSpacing: CGFloat
    let contentInset: UIEdgeInsets
    /// 0...1 position within the chapter to restore once layout is ready.
    var restoreFraction: Double
    /// Preferred restore anchor — stable across chrome/inset reflow.
    var restoreCharOffset: Int = 0
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
        context.coordinator.lastInset = contentInset
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onContentFits = onContentFits
        context.coordinator.onTap = onTap
        context.coordinator.textLength = text.count

        let contentChanged = tv.attributedText?.string != text
            || abs((tv.font?.pointSize ?? 0) - font.pointSize) > 0.1
        let insetChanged = tv.textContainerInset != contentInset

        if contentChanged {
            // Preserve place in chapter across text/font reflow. Setting attributedText
            // resets offset to 0 and would otherwise wipe saved progress via scroll callbacks.
            let maxYBefore = max(tv.contentSize.height - tv.bounds.height, 1)
            let preservedFraction = min(max(Double(tv.contentOffset.y) / Double(maxYBefore), 0), 1)
            let preservedChar = context.coordinator.approximateCharOffset(in: tv) ?? 0
            context.coordinator.isProgrammaticScroll = true
            applyContent(to: tv)
            context.coordinator.isProgrammaticScroll = false
            let targetFraction = max(preservedFraction, restoreFraction > 0.005 ? restoreFraction : 0)
            let targetChar = max(preservedChar, restoreCharOffset)
            if targetFraction > 0.005 || targetChar > 40 {
                context.coordinator.queueRestore(
                    fraction: targetFraction,
                    charOffset: targetChar,
                    on: tv
                )
            } else {
                context.coordinator.scheduleFitsCheck(on: tv)
            }
        } else if insetChanged {
            // Chrome show/hide changes insets and maxY — keep the same reading place.
            let maxYBefore = max(tv.contentSize.height - tv.bounds.height, 1)
            let preservedFraction = min(max(Double(tv.contentOffset.y) / Double(maxYBefore), 0), 1)
            let preservedChar = context.coordinator.approximateCharOffset(in: tv) ?? 0
            tv.textContainerInset = contentInset
            context.coordinator.lastInset = contentInset
            let targetFraction = max(preservedFraction, restoreFraction > 0.005 ? restoreFraction : 0)
            let targetChar = max(preservedChar, restoreCharOffset)
            if targetFraction > 0.005 || targetChar > 40 {
                context.coordinator.queueRestore(
                    fraction: targetFraction,
                    charOffset: targetChar,
                    on: tv
                )
            } else {
                context.coordinator.scheduleFitsCheck(on: tv)
            }
        } else {
            context.coordinator.scheduleFitsCheck(on: tv)
        }

        if restoreGeneration != context.coordinator.appliedRestoreGeneration,
           restoreFraction > 0.005 || restoreCharOffset > 40 {
            context.coordinator.appliedRestoreGeneration = restoreGeneration
            context.coordinator.queueRestore(
                fraction: restoreFraction,
                charOffset: restoreCharOffset,
                on: tv
            )
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
        let attributed = NSMutableAttributedString(string: text, attributes: attrs)
        if let headingRange = Self.headingRange(in: text, preferredHeading: chapterHeading) {
            let bold = font.boldReaderHeading()
            let headingParagraph = NSMutableParagraphStyle()
            headingParagraph.lineSpacing = lineSpacing
            headingParagraph.paragraphSpacing = max(lineSpacing + 4, 10)
            attributed.addAttributes(
                [
                    .font: bold,
                    .foregroundColor: textColor,
                    .paragraphStyle: headingParagraph
                ],
                range: headingRange
            )
        }
        // Do not set tv.font / tv.textColor after attributedText — that resets run fonts
        // and strips the bold chapter heading.
        tv.typingAttributes = attrs
        tv.textContainerInset = contentInset
        tv.attributedText = attributed
    }

    /// UTF-16 range of the chapter title at the start of reader text.
    private static func headingRange(in text: String, preferredHeading: String) -> NSRange? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let preferred = preferredHeading.trimmingCharacters(in: .whitespacesAndNewlines)

        if !preferred.isEmpty {
            let prefLen = (preferred as NSString).length
            if ns.length >= prefLen {
                let prefix = ns.substring(to: prefLen)
                if prefix == preferred
                    || prefix.caseInsensitiveCompare(preferred) == .orderedSame {
                    return NSRange(location: 0, length: prefLen)
                }
            }
        }

        // First paragraph as heading when it matches the chapter title (or looks like one).
        let firstEnd: Int = {
            let full = text as NSString
            let blank = full.range(of: "\n\n")
            if blank.location != NSNotFound { return blank.location }
            let nl = full.range(of: "\n")
            if nl.location != NSNotFound { return nl.location }
            return min(full.length, 180)
        }()
        guard firstEnd > 0, firstEnd <= 180 else { return nil }
        let first = ns.substring(to: firstEnd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { return nil }

        if !preferred.isEmpty {
            if first.caseInsensitiveCompare(preferred) == .orderedSame {
                return NSRange(location: 0, length: firstEnd)
            }
            return nil
        }

        // No explicit title — still bold a short "Глава …" first line.
        let lower = first.lowercased()
        if lower.hasPrefix("глава") || lower.hasPrefix("chapter") {
            return NSRange(location: 0, length: firstEnd)
        }
        return nil
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onScroll: (Double, Double, Int) -> Void
        var onContentFits: ((Bool) -> Void)?
        var onTap: () -> Void
        var textLength: Int = 0
        var pendingFraction: Double = 0
        var pendingCharOffset: Int = 0
        var appliedRestoreGeneration: Int = -1
        var isProgrammaticScroll = false
        /// True while we are still hunting for a stable layout + target offset.
        private(set) var isRestoring = false
        var lastInset: UIEdgeInsets = .zero
        weak var textView: UITextView?
        private var restoreAttempts = 0
        private var fitsAttempts = 0
        private var lastReportedFits: Bool?
        private var lastContentHeight: CGFloat = 0
        private var stableHeightHits = 0
        private var verifyWorkItem: DispatchWorkItem?

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
            // Suppress noisy intermediate offsets while layout restore is in flight.
            if isRestoring { return }
            let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 1)
            let y = Double(scrollView.contentOffset.y)
            let fraction = min(max(y / maxY, 0), 1)
            let charOffset = approximateCharOffset(in: scrollView as? UITextView)
                ?? Int((Double(textLength) * fraction).rounded())
            onScroll(y, fraction, charOffset)
            reportFits(scrollView.contentSize.height - scrollView.bounds.height < 48)
        }

        func queueRestore(fraction: Double, charOffset: Int, on tv: UITextView) {
            pendingFraction = max(fraction, 0)
            pendingCharOffset = max(charOffset, 0)
            restoreAttempts = 0
            stableHeightHits = 0
            lastContentHeight = 0
            isRestoring = true
            verifyWorkItem?.cancel()
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
            let height = tv.contentSize.height

            // Wait for a usable scroll range.
            if maxY < 40, restoreAttempts < 30 {
                restoreAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak tv] in
                    guard let self, let tv else { return }
                    self.tryRestore(on: tv)
                }
                return
            }

            // Wait until content height stops changing (layout settled).
            if abs(height - lastContentHeight) > 2 {
                lastContentHeight = height
                stableHeightHits = 0
                restoreAttempts += 1
                if restoreAttempts < 30 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak tv] in
                        guard let self, let tv else { return }
                        self.tryRestore(on: tv)
                    }
                    return
                }
            } else {
                stableHeightHits += 1
                if stableHeightHits < 2, restoreAttempts < 30 {
                    restoreAttempts += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak tv] in
                        guard let self, let tv else { return }
                        self.tryRestore(on: tv)
                    }
                    return
                }
            }

            // Short chapter: nothing to restore, but still report "at end".
            if maxY <= 1 || (pendingFraction <= 0.005 && pendingCharOffset <= 40) {
                pendingFraction = 0
                pendingCharOffset = 0
                isRestoring = false
                reportFits(maxY < 48)
                return
            }

            applyPendingOffset(on: tv, maxY: maxY, notify: false)

            // Re-check after a beat — late font/metrics can still grow contentSize.
            let targetFraction = pendingFraction
            let targetChar = pendingCharOffset
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv else { return }
                tv.layoutIfNeeded()
                let newMaxY = tv.contentSize.height - tv.bounds.height
                guard newMaxY > 1 else {
                    self.finishRestore(on: tv, maxY: max(newMaxY, 1))
                    return
                }
                self.pendingFraction = targetFraction
                self.pendingCharOffset = targetChar
                self.applyPendingOffset(on: tv, maxY: newMaxY, notify: true)
                self.finishRestore(on: tv, maxY: newMaxY)
            }
            verifyWorkItem?.cancel()
            verifyWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }

        private func applyPendingOffset(on tv: UITextView, maxY: CGFloat, notify: Bool) {
            var y: CGFloat
            if pendingCharOffset > 40, let charY = offsetY(forCharacter: pendingCharOffset, in: tv) {
                y = min(max(charY, 0), maxY)
            } else {
                y = CGFloat(pendingFraction) * max(maxY, 1)
                y = min(max(y, 0), maxY)
            }
            isProgrammaticScroll = true
            tv.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            isProgrammaticScroll = false
            if notify {
                let appliedY = Double(tv.contentOffset.y)
                let appliedFraction = min(max(appliedY / max(Double(maxY), 1), 0), 1)
                let charOffset = approximateCharOffset(in: tv)
                    ?? Int((Double(textLength) * appliedFraction).rounded())
                onScroll(appliedY, appliedFraction, charOffset)
            }
        }

        private func finishRestore(on tv: UITextView, maxY: CGFloat) {
            pendingFraction = 0
            pendingCharOffset = 0
            isRestoring = false
            reportFits(maxY < 48)
        }

        /// Map a character index to a content offset that puts that character near the top.
        func offsetY(forCharacter charOffset: Int, in tv: UITextView) -> CGFloat? {
            let textCount = tv.text.count
            guard textCount > 0 else { return nil }
            let index = min(max(charOffset, 0), textCount - 1)
            let nsIndex = (tv.text as NSString).substring(to: index).utf16.count
            let range = NSRange(location: nsIndex, length: 0)
            let glyphRange = tv.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = tv.layoutManager.boundingRect(forGlyphRange: glyphRange, in: tv.textContainer)
            rect.origin.x += tv.textContainerInset.left
            rect.origin.y += tv.textContainerInset.top
            // Keep a little context above the anchor.
            return max(rect.minY - 8, 0)
        }

        func approximateCharOffset(in tv: UITextView?) -> Int? {
            guard let tv, textLength > 0 else { return nil }
            let point = CGPoint(
                x: tv.bounds.midX,
                y: tv.contentOffset.y + tv.textContainerInset.top + 12
            )
            var fraction: CGFloat = 0
            let index = tv.layoutManager.characterIndex(
                for: CGPoint(x: point.x - tv.textContainerInset.left, y: point.y - tv.textContainerInset.top),
                in: tv.textContainer,
                fractionOfDistanceBetweenInsertionPoints: &fraction
            )
            if index != NSNotFound, index >= 0 {
                return min(index, textLength)
            }
            let maxY = max(tv.contentSize.height - tv.bounds.height, 1)
            let frac = min(max(Double(tv.contentOffset.y) / Double(maxY), 0), 1)
            return Int((Double(textLength) * frac).rounded())
        }
    }
}

private extension UIFont {
    func withTraits(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits)) else {
            return nil
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }

    /// Bold face for chapter titles — prefer a real bold of the same family, else heavy system.
    func boldReaderHeading() -> UIFont {
        if let bold = withTraits(.traitBold),
           bold.fontDescriptor.symbolicTraits.contains(.traitBold) {
            return bold
        }
        // Serif readers still look fine with a heavy system weight for the title only.
        if let serif = UIFont.systemFont(ofSize: pointSize, weight: .bold)
            .fontDescriptor
            .withDesign(.serif) {
            return UIFont(descriptor: serif, size: pointSize)
        }
        return UIFont.systemFont(ofSize: pointSize, weight: .bold)
    }
}