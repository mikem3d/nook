import CoreGraphics

/// Mirrors Assets/themes/<id>/theme.json. See docs/ART.md for the art contract.
/// Everything beyond the character and the scene list is optional, so a half-finished theme still runs.
struct Theme: Decodable {
    struct Anim: Decodable {
        let row: Int
        let frames: Int
        let fps: Double
        let looping: Bool
    }

    struct Character: Decodable {
        let sheet: String
        let frame: [Int]
        let columns: Int
        let rows: Int
        /// Bottom-centre of the character in canvas pixels, from bottom-left. A scene may override it.
        let feet: [CGFloat]
        let animations: [String: Anim]
    }

    /// One recolouring of the character: "rrggbb" to "rrggbb", applied to the sheet and the portrait.
    struct Avatar: Decodable {
        let id: String
        let name: String
        let swap: [String: String]
    }

    /// The head-only sprite of the minimised orb: one frame per agent state, by `AgentState` raw value.
    struct Portrait: Decodable {
        let sheet: String
        let frame: [Int]
        let states: [String: Int]
    }

    /// A sprite with a fixed place: bottom-left in canvas (or orb) pixels, from the bottom-left.
    struct Piece: Decodable {
        let sprite: String
        let position: [CGFloat]
    }

    /// What an edge shows when a neighbour touches it (`open`) and when none does (`sealed`).
    struct Connector: Decodable {
        let open: Piece?
        let sealed: Piece?
    }

    struct Frame: Decodable {
        let overlay: String?
        /// Keyed by edge: "top", "bottom", "left", "right".
        let connectors: [String: Connector]?
    }

    /// Frames side by side in one sheet, looping.
    struct Strip: Decodable {
        let sheet: String
        let frame: [Int]
        let frames: Int
        let fps: Double
        let position: [CGFloat]
    }

    struct Orb: Decodable {
        let back: String?
        let ring: String?
        let portraitPosition: [CGFloat]?
        /// Drawn light; the engine multiplies it by the state colour.
        let gem: Piece?
        /// Full-orb overlay blinked while the agent waits for permission.
        let alert: String?
        let work: Strip?
    }

    /// A vital-sign sprite: `states` frames side by side. Its name decides what it shows.
    struct Prop: Decodable {
        let name: String
        let sheet: String
        let frame: [Int]
        let states: Int
        let position: [CGFloat]
        /// Draw order: background 0, character 1, foreground 2.
        let z: CGFloat
    }

    /// A prop that is a button (docs/ART.md, "Hotspots"). The sheet has one column per `levels`
    /// and two rows: idle on top, hover below.
    struct Hotspot: Decodable {
        /// Small sprites inside the frame, placed from the frame's bottom-left.
        struct Digits: Decodable {
            let sheet: String
            let frame: [Int]
            let position: [CGFloat]
        }

        /// What the click means; the engine knows `tasks` and `calendar`.
        let id: String
        /// The tooltip.
        let name: String
        let sheet: String
        let frame: [Int]
        let levels: Int
        /// The clickable part of the frame, [x, y, w, h] from its bottom-left; nil: all of it.
        let hit: [CGFloat]?
        let position: [CGFloat]
        let z: CGFloat
        /// Overlay shown while the hotspot has news.
        let news: Piece?
        /// Ten digits side by side, for a hotspot that shows a number (today's date).
        let digits: Digits?
    }

    /// Where one scene hangs a theme hotspot. Hotspots a scene does not list are absent from it.
    struct Spot: Decodable {
        let id: String
        let position: [CGFloat]
        let z: CGFloat?
    }

    /// Where one scene puts a theme prop. Props a scene does not list are absent from it.
    struct Placement: Decodable {
        let name: String
        let position: [CGFloat]
        let z: CGFloat?
    }

    /// Optional travel: the sprite glides from `position` to `to` in `seconds`, once every `every` seconds.
    struct Path: Decodable {
        let to: [CGFloat]
        let seconds: Double
        let every: Double
    }

    struct Ambient: Decodable {
        let name: String
        let sheet: String
        let frame: [Int]
        let frames: Int
        let fps: Double
        let position: [CGFloat]
        let z: CGFloat
        let path: Path?
    }

    struct Scene: Decodable {
        let id: String
        let name: String
        let bg: String
        let fg: String
        let feet: [CGFloat]?
        /// nil: every theme prop at its default place.
        let props: [Placement]?
        /// nil: every theme hotspot at its default place.
        let hotspots: [Spot]?
        let ambient: [Ambient]?
        /// Replaces a default animation in this scene, for example "type": "hammer".
        let animations: [String: String]?
    }

    let id: String
    let name: String
    /// The theme's shared colours as "rrggbb". The art tools enforce it; the engine only reads it in tests.
    let palette: [String]?
    let character: Character
    let avatars: [Avatar]?
    let portrait: Portrait?
    let frame: Frame?
    let orb: Orb?
    let props: [Prop]?
    let hotspots: [Hotspot]?
    let scenes: [Scene]
}
