import XCTest
@testable import EZCal

/// Manual per-calendar colors (`CalendarStore.setColor` / `resetColor`): precedence over the provider's
/// color, persistence, re-application on `loadCalendars()`, and recoloring already-fetched events.
@MainActor
final class CalendarColorOverrideTests: XCTestCase {
    private let keys = ["colorOverrides", "people", "icsSubscriptions", "hidden", "knownCalendars", "sourceOrder", "accounts"]
    private var saved: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for k in keys { saved[k] = UserDefaults.standard.object(forKey: k); UserDefaults.standard.removeObject(forKey: k) }
    }

    override func tearDown() {
        for k in keys { UserDefaults.standard.set(saved[k] ?? nil, forKey: k) }
        super.tearDown()
    }

    private let feed = ICSSubscription(url: URL(string: "https://example.com/a.ics")!, name: "Feed", colorHex: "#111111")

    private func makeStore() -> CalendarStore {
        let store = CalendarStore()
        store.accounts = [Account(email: "me@example.com", name: "Me")]
        store.people = []
        store.icsSubscriptions = [feed]
        return store
    }

    private func event(for source: Source) throws -> CalEvent {
        let json = """
        {"id":"e1","status":"confirmed","summary":"X","iCalUID":"e1@google.com",
         "start":{"dateTime":"2030-01-01T10:00:00Z"},"end":{"dateTime":"2030-01-01T11:00:00Z"}}
        """
        let g = try JSONDecoder().decode(GEvent.self, from: Data(json.utf8))
        return try XCTUnwrap(EventMapper.map(g, source: source))
    }

    func testOverrideBeatsProviderColorAfterLoadCalendars() async {
        let store = makeStore()
        store.icsSubscriptions = [feed]
        await store.loadCalendars()
        let src = store.calendars[0]
        XCTAssertEqual(src.colorHex, "#111111")

        store.setColor("#E5484D", for: src)
        XCTAssertEqual(store.calendars[0].colorHex, "#E5484D")

        await store.loadCalendars()   // provider still reports #111111
        XCTAssertEqual(store.calendars[0].colorHex, "#E5484D")
        XCTAssertEqual(store.defaultColor(for: store.calendars[0]), "#111111")
    }

    func testResetRestoresProviderColor() async {
        let store = makeStore()
        await store.loadCalendars()
        let src = store.calendars[0]
        store.setColor("#E5484D", for: src)
        XCTAssertTrue(store.hasColorOverride(src))

        store.resetColor(for: src)
        XCTAssertFalse(store.hasColorOverride(src))
        XCTAssertEqual(store.calendars[0].colorHex, "#111111")
        await store.loadCalendars()
        XCTAssertEqual(store.calendars[0].colorHex, "#111111")
    }

    func testPersistenceRoundTrip() async {
        let store = makeStore()
        await store.loadCalendars()
        store.setColor("#3E63DD", for: store.calendars[0])

        let fresh = CalendarStore()
        XCTAssertEqual(fresh.colorOverrides, [store.calendars[0].id: "#3E63DD"])
        await fresh.loadCalendars()
        XCTAssertEqual(fresh.calendars.first?.colorHex, "#3E63DD")
    }

    func testFetchedEventsAreRecoloredAndReset() async throws {
        let store = makeStore()
        await store.loadCalendars()
        let src = store.calendars[0]
        store.eventsBySource[src.id] = [try event(for: src)]
        store.rebuildDisplay()
        XCTAssertEqual(store.displayEvents.first?.colorHex, "#111111")

        store.setColor("#30A46C", for: src)
        XCTAssertEqual(store.displayEvents.first?.colorHex, "#30A46C")
        XCTAssertEqual(store.eventsBySource[src.id]?.first?.colorHex, "#30A46C")

        store.resetColor(for: src)
        XCTAssertEqual(store.displayEvents.first?.colorHex, "#111111")
    }

    func testOverridesLeaveOtherCalendarsAlone() async throws {
        let store = makeStore()
        let other = ICSSubscription(url: URL(string: "https://example.com/b.ics")!, name: "B", colorHex: "#222222")
        store.icsSubscriptions = [feed, other]
        await store.loadCalendars()
        store.setColor("#E5484D", for: store.calendars.first { $0.name == "Feed" }!)
        XCTAssertEqual(store.calendars.first { $0.name == "B" }?.colorHex, "#222222")
    }

    func testPersonOverlayOverrideKeepsBaseColorPersisted() {
        let store = makeStore()
        store.addPerson(name: "Bob", email: "b@x.com", temporary: false)
        let bob = store.people[0]
        let base = bob.colorHex
        store.setColor("#C2A000", for: bob)
        XCTAssertEqual(store.people[0].colorHex, "#C2A000")

        let fresh = CalendarStore()
        XCTAssertEqual(fresh.people.first?.colorHex, "#C2A000")   // override applied at launch
        fresh.resetColor(for: fresh.people[0])
        XCTAssertEqual(fresh.people.first?.colorHex, base)        // and the persisted base survived
    }
}
