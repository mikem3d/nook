import CoreGraphics

/// A hotspot's clickable rectangle in canvas pixels (origin bottom left), and its tooltip.
struct HotspotArea: Equatable {
    let id: String
    let name: String
    let rect: CGRect
}

/// What a hotspot shows: how full it is, whether something changed since it was last opened, and
/// the number written on it (the calendar's date).
struct HotspotState: Equatable {
    var level = 0
    var news = false
    var number: Int?
}

/// Where a click or the mouse lands on an agent window, hotspots included. Pure geometry in view
/// points, so it can be unit tested.
enum HotspotHit {
    enum Target: Equatable {
        case chrome(WindowChrome.Hit)
        case hotspot(String)
    }

    /// The front-most hotspot under `point`; `areas` are listed front to back.
    static func hotspot(at point: CGPoint, scale: CGFloat, in areas: [HotspotArea]) -> String? {
        guard scale > 0 else { return nil }
        let p = CGPoint(x: point.x / scale, y: point.y / scale)
        return areas.first { $0.rect.contains(p) }?.id
    }

    /// The header always wins over a hotspot that strays under it. Hotspots are inert on an orb and
    /// on a window dimmed by another agent being active: there a click means what it always meant.
    static func target(_ point: CGPoint, in size: CGSize, minimised: Bool, dimmed: Bool, areas: [HotspotArea]) -> Target {
        let chrome = WindowChrome.hit(point, in: size, minimised: minimised)
        let scale = size.width / RoomScene.W
        guard chrome == .body, !dimmed, point.y <= size.height - RoomScene.bar * scale,
              let id = hotspot(at: point, scale: scale, in: areas) else { return .chrome(chrome) }
        return .hotspot(id)
    }
}
