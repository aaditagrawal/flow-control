import CoreGraphics

struct KeyboardCanvasLayout {
    static let keyUnit: CGFloat = 48
    static let minimumKeyWidth: CGFloat = 36
    static let keyHeight: CGFloat = 43
    static let keySpacing: CGFloat = 6
    static let rowSpacing: CGFloat = 8
    static let chassisPadding: CGFloat = 20
    static let chassisRimWidth: CGFloat = 8
    static let chassisCornerRadius: CGFloat = 26
    static let chassisInnerCornerRadius: CGFloat = 19
    static let canvasPadding: CGFloat = 24
    static let maximumFitScale: CGFloat = 1.35

    static var keyboardSize: CGSize {
        let width = KeyboardLayout.rows.map(rowWidth).max() ?? 0
        let rowCount = CGFloat(KeyboardLayout.rows.count)
        let height = rowCount * keyHeight + max(0, rowCount - 1) * rowSpacing
        return CGSize(width: width, height: height)
    }

    static var paddedKeyboardSize: CGSize {
        CGSize(
            width: chassisSize.width + canvasPadding * 2,
            height: chassisSize.height + canvasPadding * 2
        )
    }

    static var chassisSize: CGSize {
        CGSize(
            width: keyboardSize.width + chassisPadding * 2,
            height: keyboardSize.height + chassisPadding * 2
        )
    }

    static func rowWidth(_ row: [PhysicalKey]) -> CGFloat {
        let keys = row.reduce(CGFloat.zero) { partial, key in
            partial + max(minimumKeyWidth, CGFloat(key.width) * keyUnit)
                + CGFloat(key.spacerBefore) * keyUnit
        }
        let gaps = CGFloat(max(0, row.count - 1)) * keySpacing
        return keys + gaps
    }

    static func fittingScale(in availableSize: CGSize) -> CGFloat {
        guard availableSize.width > 0, availableSize.height > 0 else { return 1 }
        let widthScale = availableSize.width / paddedKeyboardSize.width
        let heightScale = availableSize.height / paddedKeyboardSize.height
        return min(widthScale, heightScale, maximumFitScale)
    }
}
