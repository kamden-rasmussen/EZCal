import AppIntents
import WidgetKit

/// One calendar in the widget's edit sheet. The list comes from the app-group cache the app writes after each refresh.
struct CalendarEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Calendar"
    static var defaultQuery = CalendarQuery()

    var id: String
    var name: String
    var group: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: group.isEmpty ? nil : "\(group)")
    }
}

struct CalendarQuery: EntityQuery {
    private var all: [CalendarEntity] {
        (WidgetShared.read()?.calendars ?? []).map { CalendarEntity(id: $0.id, name: $0.name, group: $0.group) }
    }

    func entities(for identifiers: [String]) async throws -> [CalendarEntity] {
        all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CalendarEntity] { all }
}

/// Edit Widget → pick the calendars it follows. Leaving it empty follows every calendar.
struct SelectCalendarsIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Calendars"
    static var description = IntentDescription("Choose which calendars this widget shows. Leave empty for all calendars.")

    @Parameter(title: "Calendars")
    var calendars: [CalendarEntity]?

    var selectedIDs: Set<String> { Set((calendars ?? []).map(\.id)) }
}
