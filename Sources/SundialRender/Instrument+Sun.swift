import Foundation

// The Sun: the brass watch's engraved pivot, the glowing bloom of the other styles and the
// astrology instrument's Byzantine seal over either. Ported from SundialView.kt.

extension Instrument {
    func drawSun(_ canvas: Canvas, _ x: Double, _ y: Double, _ core: Double) {
        if brass && onFace { drawBrassSun(canvas, x, y, core) } else { drawSunBloom(canvas, x, y, core) }
        if zodiacProfile.enabled { drawByzantineSunSeal(canvas, x, y, core) }
    }

    /// The watch's centre pivot: a polished pearl with the Sun's rays engraved around it.
    func drawBrassSun(_ canvas: Canvas, _ x: Double, _ y: Double, _ core: Double) {
        sunRay.color = withAlpha(instrumentColor, 150)
        for i in 0..<32 {
            let a = Double(i) * 2 * .pi / 32.0
            let length = core * (i % 2 == 0 ? 3.1 : 2.2)
            sunRay.strokeWidth = max(devicePixels(0.6), core * (i % 2 == 0 ? 0.07 : 0.04))
            canvas.drawLine(x + cos(a) * core * 1.45, y + sin(a) * core * 1.45,
                            x + cos(a) * length, y + sin(a) * length, sunRay)
        }
        white.color = withAlpha(instrumentColor, 120)
        white.strokeWidth = max(devicePixels(0.6), core * 0.05)
        canvas.drawCircle(x, y, core * 3.35, white)
        fill.color = 0x6600_0000
        canvas.drawCircle(x + core * 0.12, y + core * 0.18, core * 1.12, fill)
        fill.shader = .radial(
            center: Point(x - core * 0.35, y - core * 0.4),
            radius: core * 1.5,
            colors: [Colors.white, 0xFFF4_F2EC, 0xFFC9_C6BE, 0xFF8E_8A80],
            stops: [0, 0.35, 0.78, 1])
        canvas.drawCircle(x, y, core * 1.08, fill)
        fill.shader = nil
        white.color = withAlpha(instrumentColor, 190)
        white.strokeWidth = max(devicePixels(0.6), core * 0.06)
        canvas.drawCircle(x, y, core * 1.1, white)
    }

    func drawSunBloom(_ canvas: Canvas, _ x: Double, _ y: Double, _ core: Double) {
        let hazeRadius = core * 7.8
        var haze = Paint()
        haze.shader = .radial(
            center: Point(x, y),
            radius: hazeRadius,
            colors: [0xF5FF_FDF0, 0xD8FF_D37A, 0x52F2_8B32, 0x16C8_5022, Colors.transparent],
            stops: [0, 0.10, 0.27, 0.56, 1])
        canvas.drawCircle(x, y, hazeRadius, haze)

        for i in 0..<36 {
            let a = Double(i) * 2 * .pi / 36.0
            let length = core * (i % 9 == 0 ? 6.2 : i % 3 == 0 ? 4.5 : 3.25)
            sunRay.color = i % 3 == 0 ? 0x48FF_D88D : 0x28FF_F4CF
            sunRay.strokeWidth = i % 9 == 0 ? max(devicePixels(1), core * 0.075) : max(devicePixels(0.6), core * 0.035)
            canvas.drawLine(
                x + cos(a) * core * 1.08, y + sin(a) * core * 1.08,
                x + cos(a) * length, y + sin(a) * length, sunRay)
        }

        white.style = .stroke
        white.strokeWidth = max(density * 0.7, core * 0.06)
        white.color = 0x42FF_D798
        canvas.drawCircle(x, y, core * 2.7, white)
        white.color = 0x24FF_B64C
        canvas.drawCircle(x, y, core * 4.25, white)
        canvas.drawArc(Rect(x - core * 3.35, y - core * 3.35, x + core * 3.35, y + core * 3.35), -62, 118, false, white)

        let ghostAxis = 132.0 * .pi / 180
        for (distance, scale) in [(3.25, 0.42), (5.1, 0.24)] {
            let gx = x + cos(ghostAxis) * core * distance
            let gy = y + sin(ghostAxis) * core * distance
            white.color = scale > 0.3 ? 0x38A9_E4FF : 0x28FF_B86B
            white.strokeWidth = max(devicePixels(0.6), core * 0.045)
            canvas.drawCircle(gx, gy, core * scale, white)
        }

        fill.shader = .radial(
            center: Point(x - core * 0.22, y - core * 0.25),
            radius: core * 1.45,
            colors: [Colors.white, 0xFFFF_F7D2, 0xFFFF_C65A],
            stops: [0, 0.58, 1])
        canvas.drawCircle(x, y, core, fill)
        fill.shader = nil
    }

    func drawByzantineSunSeal(_ canvas: Canvas, _ x: Double, _ y: Double, _ core: Double) {
        var engraving = Paint()
        engraving.color = 0xA68D_5517
        engraving.style = .fill
        for quarter in 0..<4 {
            canvas.save()
            canvas.rotate(Double(quarter) * 90, x, y)
            var path = Path()
            path.moveTo(x - core * 0.10, y - core * 0.06)
            path.lineTo(x - core * 0.25, y - core * 0.52)
            path.lineTo(x + core * 0.25, y - core * 0.52)
            path.lineTo(x + core * 0.10, y - core * 0.06)
            path.close()
            canvas.drawPath(path, engraving)
            canvas.restore()
        }
        engraving.color = 0xC8FF_F2C2
        for index in 0..<12 {
            let angle = Double(index) * 2.0 * .pi / 12.0
            canvas.drawCircle(x + cos(angle) * core * 0.80,
                              y + sin(angle) * core * 0.80, core * 0.045, engraving)
        }
        engraving.style = .stroke
        engraving.strokeWidth = max(0.6 * density, core * 0.045)
        engraving.color = 0x9B8B_571B
        canvas.drawCircle(x, y, core * 0.68, engraving)
    }
}
