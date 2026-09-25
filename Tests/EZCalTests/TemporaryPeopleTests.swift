import XCTest
@testable import EZCal

/// Overlay behavior behind `P` / `⇧P` and Esc-to-clear (`CalendarStore.addPerson` / `clearTemporaryPeople`).
@MainActor
final class TemporaryPeopleTests: XCTestCase {
    private func makeStore() -> CalendarStore {
        let store = CalendarStore()
        store.accounts = [Account(email: "me@example.com", name: "Me")]
        store.people = []
        return store
    }

    func testTemporaryAddsAreClearedTogether() {
        let store = makeStore()
        store.addPerson(name: "A", email: "a@x.com", temporary: true)
        store.addPerson(name: "B", email: "b@x.com", temporary: true)
        XCTAssertEqual(store.people.count, 2)
        XCTAssertTrue(store.hasTemporaryPeople)

        store.clearTemporaryPeople()
        XCTAssertTrue(store.people.isEmpty)
        XCTAssertFalse(store.hasTemporaryPeople)
    }

    func testClearKeepsPermanentPeople() {
        let store = makeStore()
        store.addPerson(name: "Perm", email: "p@x.com", temporary: false)
        store.addPerson(name: "Temp", email: "t@x.com", temporary: true)

        store.clearTemporaryPeople()
        XCTAssertEqual(store.people.map(\.calendarId), ["p@x.com"])
    }

    func testPermanentAddPromotesExistingOverlay() {
        let store = makeStore()
        store.addPerson(name: "A", email: "a@x.com", temporary: true)
        store.addPerson(name: "A", email: "a@x.com", temporary: false)

        XCTAssertFalse(store.hasTemporaryPeople)
        store.clearTemporaryPeople()
        XCTAssertEqual(store.people.count, 1)
    }

    func testRemovingOverlayForgetsIt() {
        let store = makeStore()
        store.addPerson(name: "A", email: "a@x.com", temporary: true)
        store.removePerson(store.people[0])
        XCTAssertFalse(store.hasTemporaryPeople)
        XCTAssertTrue(store.people.isEmpty)
    }
}

@MainActor
final class PersonColorTests: XCTestCase {
    func testNewOverlayAvoidsColorsInUse() {
        let store = CalendarStore()
        store.accounts = [Account(email: "me@example.com", name: "Me")]
        store.people = []
        store.addPerson(name: "A", email: "a@x.com", temporary: true)
        store.addPerson(name: "B", email: "b@x.com", temporary: true)
        let colors = store.people.map(\.colorHex)
        XCTAssertEqual(Set(colors).count, 2)
        store.clearTemporaryPeople()
    }
}
