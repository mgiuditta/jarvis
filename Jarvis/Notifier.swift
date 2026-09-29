import UserNotifications

/// Banner when a long answer ends while the user is in another app. Clicking it reopens the conversation.
@MainActor final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onClick: (() -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks for the permission on the first banner, not at launch: most users never wait long enough to need one.
    func post(_ text: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Jarvis ha risposto"
            content.body = text
            do { try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
            catch { Log.write("notifica: \(error)") }
        }
    }

    // nonisolated: the parameters aren't Sendable, so it can't be a main-actor witness; it hops instead
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { onClick?() }
    }
}
