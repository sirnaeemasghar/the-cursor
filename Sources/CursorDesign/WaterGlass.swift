import SwiftUI

public enum CursorPalette {
    public static let aqua = Color(red: 0.49, green: 0.94, blue: 0.91)
    public static let ink = Color(red: 0.035, green: 0.10, blue: 0.16)
}

/// Original cursor-and-ripple mark, shared by the two app interfaces.
public struct CursorMark: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = [
            .init(x: 0.27, y: 0.19), .init(x: 0.78, y: 0.57),
            .init(x: 0.56, y: 0.62), .init(x: 0.46, y: 0.84),
            .init(x: 0.34, y: 0.78), .init(x: 0.44, y: 0.57),
            .init(x: 0.22, y: 0.57)
        ]
        return Path { path in
            path.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
            path.closeSubpath()
        }
    }
}

public struct CursorLogo: View {
    public var size: CGFloat
    public init(size: CGFloat = 44) { self.size = size }
    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.77, blue: 0.81),
                    Color(red: 0.08, green: 0.38, blue: 0.65), Color(red: 0.07, green: 0.18, blue: 0.38)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().stroke(.white.opacity(0.19), lineWidth: max(0.7, size * 0.012))
                .frame(width: size * 0.70, height: size * 0.70).offset(x: size * 0.07, y: size * 0.10)
            Circle().stroke(.white.opacity(0.10), lineWidth: max(0.5, size * 0.008))
                .frame(width: size * 0.95, height: size * 0.95).offset(x: size * 0.07, y: size * 0.10)
            CursorMark().fill(.white)
                .shadow(color: .black.opacity(0.23), radius: size * 0.04, x: 0, y: size * 0.03)
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        .accessibilityLabel("The Cursor logo")
    }
}

public struct WaterBackdrop: View {
    public init() {}
    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(red: 0.03, green: 0.10, blue: 0.17).opacity(0.83),
                    Color(red: 0.03, green: 0.17, blue: 0.23).opacity(0.72)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color.cyan.opacity(0.24), .clear], center: .topTrailing,
                    startRadius: 0, endRadius: max(proxy.size.width, proxy.size.height) * 0.85)
                RadialGradient(colors: [Color(red: 0.12, green: 0.68, blue: 0.60).opacity(0.21), .clear],
                    center: .bottomLeading, startRadius: 0, endRadius: proxy.size.height * 0.7)
                ForEach(0..<4) { index in
                    Ellipse().stroke(LinearGradient(colors: [.white.opacity(0.07), .clear, .cyan.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        .frame(width: proxy.size.width * (1.0 + Double(index) * 0.32),
                               height: proxy.size.height * (0.35 + Double(index) * 0.10))
                        .rotationEffect(.degrees(-24))
                        .position(x: proxy.size.width * 0.82, y: proxy.size.height * 0.92)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

public struct GlassCard<Content: View>: View {
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}

public struct CreatorCredit: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 7) {
            Text("Built with Love ❤️ by Naeem Asghar")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link(destination: URL(string: "https://github.com/sirnaeemasghar")!) {
                Label("GitHub profile", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .medium))
            }.buttonStyle(.bordered).controlSize(.small)
                .accessibilityLabel("Naeem Asghar’s GitHub profile")
        }.frame(maxWidth: .infinity)
    }
}
