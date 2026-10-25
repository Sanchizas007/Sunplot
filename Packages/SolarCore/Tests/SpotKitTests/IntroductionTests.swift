import Testing
@testable import SpotKit

/// Who is greeted with the tour. The rule is small, and getting it wrong in either direction
/// is visible: a person who has used the app for months welcomed to it again after an update,
/// or a person who has just installed it dropped on an empty screen with no explanation.
struct IntroductionTests {

    @Test("A new install opens with the tour")
    func newInstall() {
        #expect(Introduction.shouldShowAtLaunch(hasSeen: false, hasSpots: false))
    }

    @Test("Somebody who updates with spots already saved is not welcomed again")
    func existingUserIsLeftAlone() {
        #expect(!Introduction.shouldShowAtLaunch(hasSeen: false, hasSpots: true))
    }

    @Test("Once seen, never again at launch — whatever is on disk")
    func seenStaysSeen() {
        #expect(!Introduction.shouldShowAtLaunch(hasSeen: true, hasSpots: false))
        #expect(!Introduction.shouldShowAtLaunch(hasSeen: true, hasSpots: true))
    }
}
