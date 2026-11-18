/// Plan 2026-11-18-cover-stale-and-lost, D1. The cover draws one capture of
/// what lies below a bar. A capture is right for its moment only: taken while
/// the desktop fades, dims or moves, it stays wrong for as long as nothing
/// asks for another (the owner's Sidecar bar, 2026-11-18: the wallpaper at
/// half brightness under three panels). So a background is confirmed by later
/// captures instead of trusted, and this rule is the only place that says
/// whether a bar's background is to be captured now and why.
///
/// A new background is compared 12 s and 60 s after it. An unequal comparison
/// starts again 12 s later; from the fourth in a row the steps are 300 s
/// apart, for as long as the background keeps moving. Only an equal comparison
/// ends that run: a signal's capture neither refills the short steps nor puts
/// a confirmation off.
public struct CoverBackgroundTrust: Equatable, Sendable {
    /// Why a capture is due, in the order they are asked.
    public enum Reason: String, Equatable, Sendable {
        /// No image of the bar's size is held.
        case size
        /// The Space, light or dark, or the wallpaper's stamp changed.
        case key
        /// A notification or the windows under the strip said so.
        case stale
        /// The image is `refreshEvery` old.
        case refresh
        /// A step of the confirmation is due.
        case confirm

        /// A signal says the background changed; the others compare it with the one held.
        var isSignal: Bool {
            self == .size || self == .key || self == .stale
        }
    }

    /// A background is taken again after this long whatever the signals say.
    public static let refreshEvery = 1800.0
    /// The first confirmation: the capture budget's rest, the earliest a later session may start.
    static let firstConfirmation = CoverCaptureBudget.rest
    /// The second confirmation, after the first found the background equal.
    static let secondConfirmation = 48.0
    /// Between the comparisons of a background that keeps moving.
    static let movingConfirmation = 300.0
    /// The unequal comparisons in a row that are still followed 12 s later.
    static let quickRuns = 4
    /// A background that two comparisons found equal.
    static let confirmedStep = 2

    /// When the image held was captured.
    private(set) var capturedAt: Double?
    /// When the next confirmation is due; none once the background is confirmed.
    private(set) var confirmDue: Double?
    /// The comparisons that found the background equal, up to `confirmedStep`.
    public private(set) var step = 0
    /// The comparisons in a row that found it unequal.
    public private(set) var unequalRun = 0
    /// The captures in a row that returned nothing, and when the last one did.
    private(set) var failedRun = 0
    private(set) var failedAt: Double?
    /// When a capture that did not show the bar transparent was not believed
    /// (`believes`); none once a capture was.
    private(set) var doubtedAt: Double?

    public init() {}

    /// How long after an unequal comparison the next one is due.
    static func wait(_ unequalRun: Int) -> Double {
        unequalRun < quickRuns ? firstConfirmation : movingConfirmation
    }

    /// How long after a capture that returned nothing the next is tried:
    /// without an image the members are drawn, so it never gives up.
    static func retry(_ failedRun: Int) -> Double {
        switch failedRun {
        case ...2: firstConfirmation
        case 3: 60
        default: movingConfirmation
        }
    }

    /// Why the bar's background is to be captured now, if it is.
    /// - Parameters:
    ///   - hasUsableImage: an image of the bar's pixel size is held.
    ///   - keyEqual: the background key is the one of the image held.
    ///   - stale: something said the background may have changed.
    public func reason(now: Double, hasUsableImage: Bool, keyEqual: Bool, stale: Bool) -> Reason? {
        if failedRun > 0, let failedAt, now - failedAt < Self.retry(failedRun) { return nil }
        // The budget alone allows a second session within the same second: it would be of the same moment.
        if let doubtedAt, now - doubtedAt < Self.firstConfirmation { return nil }
        guard hasUsableImage, let capturedAt else { return .size }
        if !keyEqual { return .key }
        if stale { return .stale }
        if now - capturedAt >= Self.refreshEvery { return .refresh }
        if let confirmDue, now >= confirmDue { return .confirm }
        return nil
    }

    /// The trust after a capture made at `now` for `reason`; `equal` is
    /// whether it equals the image held before it (asked of a refresh and a
    /// confirmation only). The new image always replaces the held one.
    public func captured(reason: Reason, equal: Bool, at now: Double) -> CoverBackgroundTrust {
        var next = self
        next.capturedAt = now
        next.failedRun = 0
        next.failedAt = nil
        next.doubtedAt = nil
        if reason.isSignal {
            // A new background: its steps begin again, but a deadline already
            // running is not pushed back, only kept 12 s after this strip, so
            // the two compared are never of one moment.
            next.step = 0
            next.confirmDue = max(now + Self.firstConfirmation, min(confirmDue ?? .infinity, now + Self.wait(unequalRun)))
        } else if equal {
            next.step = min(step + 1, Self.confirmedStep)
            next.unequalRun = 0
            next.confirmDue = next.step < Self.confirmedStep ? now + Self.secondConfirmation : nil
        } else {
            next.step = 0
            next.unequalRun = unequalRun + 1
            next.confirmDue = now + Self.wait(next.unequalRun)
        }
        return next
    }

    /// Whether a capture is taken for what it shows (plan D7). One that does
    /// not show the bar transparent, while the image held did, is a passing
    /// moment more often than a changed bar: Mission Control closing over the
    /// bar reads so (MEASURED 2026-11-18, 19:14:28: the panels went for 11 s).
    /// It is not believed once; the next capture is, whatever it shows.
    public func believes(transparent: Bool, heldTransparent: Bool) -> Bool {
        transparent || !heldTransparent || doubtedAt != nil
    }

    /// The trust after a capture made at `now` was not believed: nothing of
    /// the image changes, so the reason it was taken for asks again, 12 s on.
    public func doubted(at now: Double) -> CoverBackgroundTrust {
        var next = self
        next.doubtedAt = now
        return next
    }

    /// The trust after the image calls returned nothing at `now`: the image
    /// held, its steps and the deadline stay.
    public func captureFailed(at now: Double) -> CoverBackgroundTrust {
        var next = self
        next.failedRun = failedRun + 1
        next.failedAt = now
        return next
    }
}
