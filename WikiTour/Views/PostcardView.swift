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
    static let textBold = "BrandonText-Bold"
    static let textBlack = "BrandonText-Black"

    static func register() {
        for name in [script, display, textBold, textBlack] {
            guard let data = NSDataAsset(name: name)?.data as CFData?,
                  let provider = CGDataProvider(data: data),
                  let font = CGFont(provider) else { continue }
            CTFontManagerRegisterGraphicsFont(font, nil)
        }
    }
}

/// The postcard photo treatment from the Figma mock (node 23:387), which lightens and flattens the
/// photo so the lettering stays legible. Figma's adjustments (contrast −27%, saturation −50%,
/// tint +18%, highlights −97%, shadows −100%) were matched with Core Image against Figma's own
/// export of the same photo; the remaining difference averages about 7 levels out of 255.
enum PostcardPhotoStyle {
    private static let context = CIContext()

    static func apply(to image: UIImage) -> UIImage {
        guard let input = CIImage(image: image) else { return image }
        let color = CIFilter.colorControls()
        color.inputImage = input
        color.saturation = 0.5
        let tone = CIFilter.highlightShadowAdjust()
        tone.inputImage = color.outputImage
        tone.highlightAmount = 1
        tone.shadowAmount = 0.2
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = tone.outputImage
        matrix.rVector = CIVector(x: 0.767, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 0.739, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0.740, w: 0)
        matrix.biasVector = CIVector(x: 0.042, y: 0.029, z: 0.044, w: 0)
        guard let output = matrix.outputImage,
              let cgImage = context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

/// The web app's subtle halftone: two offset grids of dots, forming a diagonal lattice. The postcard
/// uses the app's accent pink so it does not wash out white lettering; the loading screen uses dark
/// blue dots like the app icon's sky.
struct HalftoneOverlay: View {
    var color: Color = TourStyle.accent.opacity(0.35)
    var spacing: CGFloat = 4
    var dotSize: CGFloat = 1.5

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
    private static let paper = Color(red: 1, green: 249 / 255, blue: 249 / 255)
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
            // The mock's 10% light-blue wash, then the web app's halftone.
            Color(red: 0.613, green: 0.794, blue: 1).opacity(0.1)
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
        let first = city.prefix(1)
        let rest = city.dropFirst()
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
