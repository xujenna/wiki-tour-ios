import SwiftUI
import UIKit
import CoreText
import CoreImage
import CoreImage.CIFilterBuiltins

/// Fonts bundled as asset-catalog data, registered once at launch. Borel is an SIL Open Font License
/// font (license in resources/fonts). Brandon Grotesque and Brandon Text are commercial fonts,
/// bundled at the owner's request for this unpublished app; check their licenses before any wider release.
enum BundledFonts {
    static let script = "Borel-Regular"
    static let display = "BrandonGrotesque-Bold"
    static let displayBlack = "BrandonGrotesque-Black"
    static let textRegular = "BrandonText-Regular"
    static let textBold = "BrandonText-Bold"
    static let textBlack = "BrandonText-Black"

    /// Borel lacks some accented letters (č, ć, š, ž). Drawing those in another font looks broken,
    /// so they are written as their base letter, the way people often type them ("Vracar").
    static func scriptSafe(_ text: String) -> String {
        guard let font = UIFont(name: script, size: 12) else { return text }
        let ctFont = font as CTFont
        return String(text.map { character -> Character in
            let utf16 = Array(String(character).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: utf16.count)
            if CTFontGetGlyphsForCharacters(ctFont, utf16, &glyphs, utf16.count) { return character }
            let base = String(character).applyingTransform(.stripDiacritics, reverse: false) ?? String(character)
            return base.count == 1 ? Character(base) : character
        })
    }

    static func register() {
        for name in [script, display, displayBlack, textRegular, textBold, textBlack] {
            guard let data = NSDataAsset(name: name)?.data as CFData?,
                  let provider = CGDataProvider(data: data),
                  let font = CGFont(provider) else { continue }
            CTFontManagerRegisterGraphicsFont(font, nil)
        }
    }
}

extension Font {
    /// Brandon Text in place of the system font, scaling with Dynamic Type like the style it replaces.
    static func brandon(_ size: CGFloat, bold: Bool = false, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(bold ? BundledFonts.textBold : BundledFonts.textRegular, size: size, relativeTo: style)
    }
}

/// Text at an exact line height, for mock specs tighter than the font's own: Brandon Grotesque's
/// natural leading is about 1.43× its size (22.9 pt at 16 pt), and SwiftUI can only add space
/// between lines, never remove it. A UILabel with a fixed line height matches the spec.
struct MockText: UIViewRepresentable {
    let text: String
    let font: String
    let size: CGFloat
    let lineHeight: CGFloat
    var color: UIColor = UIColor(red: 46 / 255, green: 46 / 255, blue: 46 / 255, alpha: 1)
    var alignment: NSTextAlignment = .natural
    var lineLimit = 0
    var shadowRadius: CGFloat = 0
    var identifier: String?

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let uiFont = UIFont(name: font, size: size) ?? .systemFont(ofSize: size, weight: .bold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping
        label.attributedText = NSAttributedString(string: text, attributes: [
            .font: uiFont, .kern: size * 0.01, .foregroundColor: color, .paragraphStyle: paragraph,
            // Centers the glyphs in the tighter line.
            .baselineOffset: (lineHeight - uiFont.lineHeight) / 4])
        label.numberOfLines = lineLimit
        label.lineBreakMode = .byTruncatingTail
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = shadowRadius
        label.layer.shadowOpacity = shadowRadius > 0 ? 1 : 0
        label.layer.shadowOffset = .zero
        label.accessibilityIdentifier = identifier
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? .greatestFiniteMagnitude
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: proposal.width ?? fitted.width, height: fitted.height)
    }
}

/// An empty state in Brandon; the system's ContentUnavailableView always uses the system font.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).mockFont(BundledFonts.displayBlack, size: 22)
            Text(message).mockFont(BundledFonts.textRegular, size: 15, lineHeight: 20)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40).padding(.horizontal, 24)
    }
}

extension View {
    /// A bundled font at a mock's size, 1% letter spacing, and (optionally) its line height. The app's
    /// rounded font design is cleared, since it would otherwise replace the custom font.
    func mockFont(_ name: String, size: CGFloat, lineHeight: CGFloat? = nil) -> some View {
        let natural = UIFont(name: name, size: size)?.lineHeight ?? size * 1.2
        return fontDesign(nil)
            .font(.custom(name, size: size))
            .tracking(size * 0.01)
            .lineSpacing(lineHeight.map { max(0, $0 - natural) } ?? 0)
    }
}

/// The postcard photo treatment from the Figma mock (node 36:489): black and white, lightened and
/// flattened so the lettering stays legible. Figma's adjustments (saturation −100%, contrast −47%,
/// tint +18%, highlights −97%, shadows −100%) were matched with Core Image against Figma's own
/// export of the same photo; the remaining difference averages about 7 levels out of 255.
enum PostcardPhotoStyle {
    private static let context = CIContext()

    static func apply(to image: UIImage) -> UIImage {
        guard let input = CIImage(image: image) else { return image }
        let color = CIFilter.colorControls()
        color.inputImage = input
        color.saturation = 0
        color.contrast = 0.65
        let tone = CIFilter.highlightShadowAdjust()
        tone.inputImage = color.outputImage
        tone.highlightAmount = 0.2
        tone.shadowAmount = 0.2
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = tone.outputImage
        matrix.rVector = CIVector(x: 1.792, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 1.792, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1.792, w: 0)
        matrix.biasVector = CIVector(x: -0.334, y: -0.334, z: -0.334, w: 0)
        guard let output = matrix.outputImage?.cropped(to: input.extent),
              let cgImage = context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

/// The web app's subtle halftone: two offset grids of dots, forming a diagonal lattice. The postcard
/// uses dark gray dots so they do not wash out the white lettering on its black-and-white photo; the
/// loading screen uses dark blue dots like the app icon's sky.
struct HalftoneOverlay: View {
    var color: Color = Color(white: 0.18).opacity(0.35)
    var spacing: CGFloat = 3
    var dotSize: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for offset in [0, spacing / 2] {
                for x in stride(from: offset, through: size.width, by: spacing) {
                    for y in stride(from: offset, through: size.height, by: spacing) {
                        dots.addEllipse(in: CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize))
                    }
                }
            }
            context.fill(dots, with: .color(color))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The welcome postcard for a newly suggested tour (Figma 25:486): the first stop's Wikipedia
/// photo, "Welcome to" the city and state, and the tour's length with a start button.
struct PostcardView: View {
    let photoLandmark: Landmark?
    let city: String
    let region: String
    let summary: String
    let onStart: () -> Void
    let onDismiss: () -> Void

    @State private var photo: UIImage?
    /// The mock's warm off-white (#F1EFEE) for the card and the lettering.
    private static let paper = Color(red: 241 / 255, green: 239 / 255, blue: 238 / 255)
    private static let ink = Color(red: 46 / 255, green: 46 / 255, blue: 46 / 255)

    var body: some View {
        GeometryReader { geometry in
            // The mock's card is 386 pt wide on a 402 pt screen; everything scales with it.
            let scale = min(1.15, (geometry.size.width - 16) / 386)
            card
                .frame(width: 386, height: 280)
                .scaleEffect(scale)
                .frame(width: 386 * scale, height: 280 * scale)
                .rotationEffect(.degrees(-4.5))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 330)
        .contentShape(Rectangle())
        .onTapGesture(perform: onStart)
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height > 40 { onDismiss() }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Welcome to \(city), \(region). \(summary)")
        .accessibilityHint("Starts the walking tour. Swipe down to dismiss.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Dismiss", onDismiss)
        .accessibilityIdentifier("welcomePostcard")
        // The app sets a rounded design on all text, which would replace the postcard's fonts.
        .fontDesign(nil)
        .task(id: photoLandmark?.id) { await loadPhoto() }
    }

    private var card: some View {
        VStack(spacing: 0) {
            ZStack {
                Self.paper
                photoLayer
                    .frame(width: 362, height: 226)
                    .clipped()
                lettering
                    .frame(width: 362, height: 226)
            }
            .frame(height: 250)
            HStack {
                Text(summary)
                    .font(.custom(BundledFonts.textBold, size: 14))
                    .tracking(0.14)
                Spacer()
                Text("START →")
                    .font(.custom(BundledFonts.textBlack, size: 14))
                    .tracking(0.14)
            }
            .foregroundStyle(Self.ink)
            .padding(.horizontal, 14)
            .frame(height: 30, alignment: .top)
        }
        .background(Self.paper) // One surface, so no seam shows between the photo and the strip.
    }

    private var photoLayer: some View {
        ZStack {
            Color(red: 0.27, green: 0.32, blue: 0.38)
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: 362, height: 226)
            }
            HalftoneOverlay()
        }
        .clipped()
    }

    private var lettering: some View {
        ZStack {
            Text("WELCOME TO")
                .font(.custom(BundledFonts.display, size: 20))
                .tracking(0.2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 18).padding(.top, 16)
            cityTitle
                .rotationEffect(.degrees(-29.2))
            Text(region.uppercased())
                .font(.custom(BundledFonts.display, size: 28))
                .tracking(0.28)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: 230, alignment: .trailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 14).padding(.bottom, 12)
        }
        .foregroundStyle(Self.paper)
    }

    /// Borel with a larger first letter, as in the mock; long names shrink to fit.
    private var cityTitle: some View {
        let title = BundledFonts.scriptSafe(city)
        let first = title.prefix(1)
        let rest = title.dropFirst()
        return (Text(first).font(.custom(BundledFonts.script, size: 80))
                + Text(rest).font(.custom(BundledFonts.script, size: 70)))
            .tracking(0.7)
            .lineLimit(1)
            .minimumScaleFactor(0.35)
            .frame(width: 340)
            .offset(y: 10)
    }

    private func loadPhoto() async {
        guard let landmark = photoLandmark else { photo = nil; return }
        if let asset = landmark.previewImage, let image = UIImage(named: asset) {
            photo = PostcardPhotoStyle.apply(to: image)
            return
        }
        guard let url = landmark.imageURL,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        let styled = await Task.detached(priority: .userInitiated) { PostcardPhotoStyle.apply(to: image) }.value
        if !Task.isCancelled { photo = styled }
    }
}
