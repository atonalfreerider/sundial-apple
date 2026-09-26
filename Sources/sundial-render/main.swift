import Foundation
import SundialRender
import SundialSVG

// sundial-render: draws the instrument through SVGCanvas and writes an SVG, and optionally a PNG
// rasterised by headless Chrome. It serves previews on Linux, store art, and side-by-side
// comparisons with the Android app's captures (render at the phone's pixel size and density).

let usage = """
    usage: sundial-render [options]

      --view helio|earth|galactic   the instrument view (default helio)
      --style NAME                  a CelestialStyle case, e.g. voidBlack, brassWatch (default voidBlack)
      --layout phone|watchRound|watchRect
      --width PX, --height PX       canvas size in pixels (default: the layout's size in dp × density)
      --density D                   pixels per dp (default 1)
      --instant ISO8601             the moment shown, e.g. 2026-10-14T16:20:00Z (default now);
                                    without an offset it is read in --zone
      --zone IANA                   the civil time zone (default the system's)
      --astrology                   turn the zodiac features on
      --birth-date yyyy-MM-dd       the zodiac profile's birth date
      --clock                       show the clock
      --horoscope TEXT              a reading for the horoscope card
      --ambient                     the watch's always-on rendering
      --southern                    southern hemisphere
      --assets DIR                  folder with earth_texture.png and sundial_condensed.ttf
                                    (default ./Assets, else the repository's Assets)
      --out FILE.svg                write the SVG here (default: standard output, unless --png)
      --png FILE.png                also rasterise with headless Chrome
    """

struct Options {
    var view = Instrument.ViewState.heliocentric
    var style = CelestialStyle.voidBlack
    var layout = InstrumentLayout.phone
    var width: Double?
    var height: Double?
    var density = 1.0
    var instantText: String?
    var zone = TimeZone.current
    var astrology = false
    var birthDate: LocalDate?
    var clock = false
    var horoscope: String?
    var ambient = false
    var southern = false
    var assets: URL?
    var out: String?
    var png: String?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sundial-render: \(message)\n".utf8))
    exit(2)
}

/// Lower case letters and digits only, so voidBlack, VOID_BLACK and "Void Black" all match.
func normalized(_ text: String) -> String {
    String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
}

func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var index = 0
    func next(_ flag: String) -> String {
        index += 1
        guard index < arguments.count else { fail("\(flag) needs a value") }
        return arguments[index]
    }
    while index < arguments.count {
        var argument = arguments[index]
        // --flag=value is the same as --flag value.
        var inline: String?
        if argument.hasPrefix("--"), let equals = argument.firstIndex(of: "=") {
            inline = String(argument[argument.index(after: equals)...])
            argument = String(argument[..<equals])
        }
        func value(_ flag: String) -> String { inline ?? next(flag) }
        func number(_ flag: String) -> Double {
            let text = value(flag)
            guard let number = Double(text), number.isFinite, number > 0 else { fail("\(flag): not a positive number: \(text)") }
            return number
        }
        switch argument {
        case "--view":
            switch normalized(value(argument)) {
            case "helio", "heliocentric", "solar": options.view = .heliocentric
            case "earth", "geocentric": options.view = .geocentric
            case "galactic", "galaxy": options.view = .galactic
            case let other: fail("--view: unknown view \(other) (helio, earth or galactic)")
            }
        case "--style":
            let wanted = normalized(value(argument))
            guard let style = CelestialStyle.allCases.first(where: {
                normalized(String(describing: $0)) == wanted || normalized($0.displayName) == wanted
            }) else {
                fail("--style: unknown style; one of \(CelestialStyle.allCases.map { String(describing: $0) }.joined(separator: ", "))")
            }
            options.style = style
        case "--layout":
            switch normalized(value(argument)) {
            case "phone": options.layout = .phone
            case "watchround", "round": options.layout = .watchRound
            case "watchrect", "rect": options.layout = .watchRect
            case let other: fail("--layout: unknown layout \(other) (phone, watchRound or watchRect)")
            }
        case "--width": options.width = number(argument)
        case "--height": options.height = number(argument)
        case "--density": options.density = number(argument)
        case "--instant": options.instantText = value(argument)
        case "--zone":
            let name = value(argument)
            guard let zone = TimeZone(identifier: name) else { fail("--zone: unknown time zone \(name)") }
            options.zone = zone
        case "--astrology": options.astrology = true
        case "--birth-date":
            let text = value(argument)
            guard let date = LocalDate.parse(text) else { fail("--birth-date: expected yyyy-MM-dd, got \(text)") }
            options.birthDate = date
        case "--clock": options.clock = true
        case "--horoscope": options.horoscope = value(argument)
        case "--ambient": options.ambient = true
        case "--southern": options.southern = true
        case "--assets": options.assets = URL(fileURLWithPath: value(argument), isDirectory: true)
        case "--out": options.out = value(argument)
        case "--png": options.png = value(argument)
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            fail("unknown option \(argument)\n\(usage)")
        }
        index += 1
    }
    return options
}

/// An ISO 8601 instant: with Z or an offset, or a local date-time (or date) read in [zone]. Read in
/// the proleptic Gregorian calendar, as java.time reads it (ISO8601DateFormatter turns Julian
/// before 1582-10-15, so the galactic view's early years would be ten or more days off).
func parseInstant(_ text: String, _ zone: TimeZone) -> Date? {
    let parts = text.split(separator: "T", maxSplits: 1).map(String.init)
    guard let first = parts.first, let date = LocalDate.parse(first) else { return nil }
    guard parts.count > 1 else { return ZonedDateTime.instant(date, LocalTime(0, 0), zone) }
    var time = Substring(parts[1])
    var offsetSeconds: Int?
    if time.hasSuffix("Z") || time.hasSuffix("z") {
        offsetSeconds = 0
        time = time.dropLast()
    } else if let sign = time.lastIndex(where: { $0 == "+" || $0 == "-" }) {
        let fields = time[time.index(after: sign)...].split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2, fields.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isASCII) }),
              let hours = Int(fields[0]), let minutes = Int(fields[1]) else { return nil }
        offsetSeconds = (time[sign] == "-" ? -1 : 1) * (hours * 3_600 + minutes * 60)
        time = time[..<sign]
    }
    var fraction = 0.0
    if let dot = time.firstIndex(of: ".") {
        let digits = time[time.index(after: dot)...]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Double("0." + digits)
        else { return nil }
        fraction = value
        time = time[..<dot]
    }
    guard let local = LocalTime.parse(String(time)) else { return nil }
    if let offsetSeconds {
        let seconds = Double(date.epochDay) * 86_400 + Double(local.secondOfDay) - Double(offsetSeconds)
        return Date(timeIntervalSince1970: seconds + fraction)
    }
    return ZonedDateTime.instant(date, local, zone).addingTimeInterval(fraction)
}

/// ./Assets, or an Assets folder beside the executable or above it (the repository's).
func defaultAssets() -> URL? {
    func hasAssets(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("earth_texture.png").path)
    }
    let local = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
    if hasAssets(local) { return local }
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    var directory = executable.resolvingSymlinksInPath().deletingLastPathComponent()
    while directory.path != "/" && !directory.path.isEmpty {
        let candidate = directory.appendingPathComponent("Assets")
        if hasAssets(candidate) { return candidate }
        directory = directory.deletingLastPathComponent()
    }
    return nil
}

/// BitmapFactory's inSampleSize, as Android decodes the Earth texture for a watch: every
/// [factor]th pixel in each direction, starting factor / 2 in (Skia's sampled decode).
func sampled(_ image: PixelImage, _ factor: Int) -> PixelImage {
    let width = factor > image.width ? 1 : image.width / factor
    let height = factor > image.height ? 1 : image.height / factor
    let start = factor / 2
    var pixels = [ARGB](repeating: 0, count: width * height)
    for y in 0..<height {
        let source = min(start + y * factor, image.height - 1) * image.width
        for x in 0..<width {
            pixels[y * width + x] = image.pixels[source + min(start + x * factor, image.width - 1)]
        }
    }
    return PixelImage(width: width, height: height, pixels: pixels)
}

/// Finds Chrome on the PATH (or $CHROME) and screenshots [svg] at [width] × [height].
func rasterise(_ svg: URL, _ png: URL, _ width: Int, _ height: Int) {
    let environment = ProcessInfo.processInfo.environment
    let names = [environment["CHROME"]].compactMap { $0 } + ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser"]
    let searchPath = (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
    let chrome = names.lazy.compactMap { name -> String? in
        if name.contains("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        return searchPath.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }.first
    guard let chrome else { fail("--png needs Google Chrome or Chromium on the PATH (or set CHROME)") }
    try? FileManager.default.removeItem(at: png)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: chrome)
    process.arguments = ["--headless=new", "--disable-gpu", "--hide-scrollbars", "--default-background-color=00000000",
                         "--window-size=\(width),\(height)", "--screenshot=\(png.path)", svg.absoluteString]
    let errors = Pipe()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors
    do { try process.run() } catch { fail("could not start \(chrome): \(error)") }
    let log = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: png.path) else {
        FileHandle.standardError.write(log)
        fail("Chrome did not write \(png.path) (exit \(process.terminationStatus))")
    }
}

// MARK: - Main

let options = parseOptions(Array(CommandLine.arguments.dropFirst()))
let instant: Date
if let text = options.instantText {
    guard let parsed = parseInstant(text, options.zone) else { fail("--instant: not an ISO 8601 instant: \(text)") }
    instant = parsed
} else {
    instant = Date()
}
guard let assets = options.assets ?? defaultAssets() else { fail("no Assets folder found; pass --assets") }

// The layout's usual size in dp: a Pixel phone, a round Wear OS watch, a 45 mm Apple Watch.
let defaultSize: (Double, Double)
switch options.layout {
case .phone: defaultSize = (412, 915)
case .watchRound: defaultSize = (228, 228)
case .watchRect: defaultSize = (198, 242)
}
let width = options.width ?? (defaultSize.0 * options.density).rounded()
let height = options.height ?? (defaultSize.1 * options.density).rounded()

let texture: PixelImage
do {
    let full = try PNG.decode(contentsOf: assets.appendingPathComponent("earth_texture.png"))
    // Android decodes the texture at half size on a watch.
    texture = options.layout.isWatch ? sampled(full, 2) : full
} catch {
    fail("could not read \(assets.appendingPathComponent("earth_texture.png").path): \(error)")
}

let instrument = Instrument(layout: options.layout, density: options.density, earthTexture: texture, style: options.style,
                            zodiacProfile: ZodiacProfile(enabled: options.astrology, birthDate: options.birthDate),
                            horoscope: options.horoscope, zone: options.zone, now: instant)
// A still: the clock and every animation stand at [instant].
instrument.currentDate = { instant }
instrument.uptime = { 0 }
instrument.freezeForCapture(instant: instant, state: options.view, style: options.style)
instrument.setClockVisible(options.clock)
instrument.setSouthernHemisphere(options.southern)
instrument.setAmbient(options.ambient)

let canvas = SVGCanvas(width: width, height: height, fonts: SVGFonts.load(assetsDirectory: assets))
instrument.draw(canvas)
let svg = canvas.svgString()

let svgURL: URL
if let out = options.out {
    svgURL = URL(fileURLWithPath: out)
} else if options.png != nil {
    svgURL = FileManager.default.temporaryDirectory.appendingPathComponent("sundial-render-\(ProcessInfo.processInfo.processIdentifier).svg")
} else {
    FileHandle.standardOutput.write(Data(svg.utf8))
    exit(0)
}
do { try svg.write(to: svgURL, atomically: true, encoding: .utf8) } catch { fail("could not write \(svgURL.path): \(error)") }
if options.out != nil { print(svgURL.path) }

if let png = options.png {
    let pngURL = URL(fileURLWithPath: png)
    rasterise(svgURL.absoluteURL, pngURL, Int(width.rounded(.up)), Int(height.rounded(.up)))
    if options.out == nil { try? FileManager.default.removeItem(at: svgURL) }
    print(pngURL.path)
}
