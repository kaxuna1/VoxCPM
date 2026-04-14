import AppKit

class WaveformRenderer {
    private var levels: [CGFloat] = Array(repeating: 0, count: 5)
    private var index = 0

    func addLevel(_ level: CGFloat) {
        levels[index % levels.count] = level
        index += 1
    }

    func reset() {
        levels = Array(repeating: 0, count: levels.count)
        index = 0
    }

    func renderIcon(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        let barCount = levels.count
        let barWidth: CGFloat = 2
        let gap: CGFloat = 1.5
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
        let startX = (size - totalWidth) / 2
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = size - 4

        for (i, level) in levels.enumerated() {
            let barHeight = minHeight + (maxHeight - minHeight) * level
            let x = startX + CGFloat(i) * (barWidth + gap)
            let y = (size - barHeight) / 2

            let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            NSColor.systemRed.setFill()
            path.fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
