/// Ice's reference rule asked from outside Ice (plan
/// 2026-10-07-icebar-menu-frame-fix, section 11): a process that is not Ice
/// reads Ice's three control items as ordinary items, so they are found by
/// their identifiers and left out -- all three, as `CheckPlan.make` never
/// offers one of Ice's own items as a reference.
public struct ExternalReferenceCheck: Equatable, Sendable {
    public let dividerMinX: Double?
    public let iceIconMidX: Double?
    /// Every item that is not one of Ice's own.
    public let others: [DiscoveredItem]
    /// `CheckPlan.geometricReferenceCandidates` over `others`; empty without
    /// the hidden divider.
    public let references: [DiscoveredItem]

    public init(items: [DiscoveredItem], own: OwnIdentifiers) {
        let ownIdentifiers = [own.visible, own.hidden, own.alwaysHidden]
        let others = items.filter { !ownIdentifiers.contains($0.key.identifier) }
        let dividerMinX = items.first { $0.key.identifier == own.hidden }?.frame?.minX
        let iceIconMidX = items.first { $0.key.identifier == own.visible }?.frame?.midX
        self.dividerMinX = dividerMinX
        self.iceIconMidX = iceIconMidX
        self.others = others
        self.references = dividerMinX.map { CheckPlan.geometricReferenceCandidates(items: others, dividerMinX: $0, iceIconMidX: iceIconMidX) } ?? []
    }
}
