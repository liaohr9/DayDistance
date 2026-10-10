#!/usr/bin/env python3
"""Run production scenes on disposable data; never touch the installed repository."""
import argparse, os, plistlib, shutil, subprocess, tempfile
from pathlib import Path
p = Path(__file__).resolve().parent.parent
args = argparse.ArgumentParser()
args.add_argument('--language', choices=['zh-Hans','en'], default='zh-Hans')
args.add_argument('--showcase', action='store_true', help='Public screenshots with fictional events only')
args.add_argument('--empty', action='store_true')
args.add_argument('--custom-reminder', action='store_true', help='Disposable event with a custom reminder, no notifications sent')
args.add_argument('--permission-refresh', action='store_true', help='Disposable permission state file, no real permission or notifications')
args.add_argument('--high-contrast', action='store_true', help='Render production UI with increased contrast')
args.add_argument('--trace-keys', action='store_true', help='Diagnostic: log list key routing')
args.add_argument('--trace-sort', action='store_true', help='Diagnostic: log native menu lifecycle and focus')
args.add_argument('--freeze-timeline', action='store_true', help='Diagnostic: pause production TimelineView updates on disposable data')
args = args.parse_args()
env = dict(os.environ)
env.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')
with tempfile.TemporaryDirectory(prefix='daydistance-public-', suffix='.noindex') as folder:
    root = Path(folder)
    app = root/'日距公开版验证.app'; contents = app/'Contents'; (contents/'MacOS').mkdir(parents=True)
    source = (p/'App/DayDistanceApp.swift').read_text().replace('struct DayDistanceApp:', 'struct PublicFeatureQAApp:').replace('DayDistanceApp.main()', 'PublicFeatureQAApp.main()').replace('let initialStore = EventStore(automaticallyLoad: false)', 'let initialStore = EventStore(repository: PublicFeatureQA.repository, automaticallyLoad: false)').replace('repositoryProvider: { try SharedContainer.repository() }', 'repositoryProvider: { PublicFeatureQA.repository }')
    source = source.replace('CommandGroup(replacing: .help) {', 'CommandGroup(replacing: .help) { Button("Menu Bar Preview") { openWindow(id: "qaMenu") }')
    source = source.replace('Settings { PreferencesView(dockIcons: applicationDelegate.dockIcons, reminders: reminders, background: backgroundReminders) }', 'Window("Menu Bar Preview", id: "qaMenu") { MenuBarView(store: store, openMain: activateMain, create: { activateMain(); store.newEvent() }) }\n        Settings { PreferencesView(dockIcons: applicationDelegate.dockIcons, reminders: reminders, background: backgroundReminders) }')
    source = source.replace('EventReminderService(repositoryProvider: { PublicFeatureQA.repository })', 'EventReminderService(client: PublicFeatureQA.notificationClient, repositoryProvider: { PublicFeatureQA.repository })')
    source = source.replace('BackgroundReminderController()', 'BackgroundReminderController(client: PublicFeatureQA.backgroundClient)')
    source = source.replace('await reminders.authorizeIfNeeded()', 'nil')
    source = source.replace('await reminders.sync(events: store.events.filter(\\.isActive))', 'await reminders.sync(events: [])')
    if args.empty:
        source = source.replace('hasShownWidgetHint', 'hasShownWidgetHintEmptyQA')
    source += '''\nimport UserNotifications
@MainActor final class PublicQANotifications: EventNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus { .notDetermined }
    func requestAuthorization() async throws -> Bool { false }
    func pendingRequests() async -> [UNNotificationRequest] { [] }
    func add(_ request: UNNotificationRequest) async throws { throw NSError(domain: "QA", code: 1) }
    func removePending(identifiers: [String]) { }
}
@MainActor final class PublicQABackgroundClient: BackgroundReminderClient {
    var status = BackgroundReminderStatus.off
    func register() async throws { status = .requiresApproval }
    func unregister() async throws { status = .off }
    func openSettings() { }
}
@MainActor enum PublicFeatureQA {
    static let backgroundClient = PublicQABackgroundClient()
    static let notificationClient = PublicQANotifications()
    static var repository: EventRepository {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let repository = EventRepository(fileURL: root.appendingPathComponent("data/events.json"))
        if !FileManager.default.fileExists(atPath: repository.fileURL.path) {
            let now = Date()
            let events = [CountdownEvent(id: UUID(uuidString:"00000000-0000-0000-0000-000000000001")!, title:"QA Upcoming", targetDate:now.addingTimeInterval(86400)),
                          CountdownEvent(id: UUID(uuidString:"00000000-0000-0000-0000-000000000002")!, title:"QA Past", targetDate:now.addingTimeInterval(-10*86400))]
            try! repository.save(events, replacing: [])
        }
        return repository
    }
}\n'''
    if args.showcase:
        source = source.replace('let events = [CountdownEvent', 'let originalEvents = [CountdownEvent')
        source = source.replace('try! repository.save(events, replacing: [])', 'let date = { (y: Int, m: Int, d: Int) in Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 9))! }\n            let events = [\n                CountdownEvent(title:"京都之旅", targetDate:date(2026,11,8), isAllDay:true, calendarDay:CalendarDay(date:date(2026,11,8)), isPinned:true, symbol:"airplane", colorKey:"amber"),\n                CountdownEvent(title:"第一场马拉松", targetDate:date(2026,11,15), isAllDay:true, calendarDay:CalendarDay(date:date(2026,11,15)), symbol:"flag", colorKey:"sage"),\n                CountdownEvent(title:"我的生日", targetDate:date(2026,12,24), isAllDay:true, calendarDay:CalendarDay(date:date(2026,12,24)), repeatYearly:true, symbol:"gift", colorKey:"violet"),\n                CountdownEvent(title:"开始学习钢琴", targetDate:date(2024,5,20), includesStartDay:true, isAllDay:true, calendarDay:CalendarDay(date:date(2024,5,20)), symbol:"sun.max", colorKey:"blue")\n            ]\n            try! repository.save(events, replacing: [])')
    if args.permission_refresh:
        (root/'permission-state.txt').write_text('denied')
        source = source.replace('func authorizationStatus() async -> UNAuthorizationStatus { .notDetermined }', '\n    var pending: [String: UNNotificationRequest] = [:]\n    func authorizationStatus() async -> UNAuthorizationStatus {\n        let file = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("permission-state.txt")\n        let value = try? String(contentsOf: file, encoding: .utf8)\n        return value?.trimmingCharacters(in: .whitespacesAndNewlines) == "authorized" ? .authorized : .denied\n    }')
        source = source.replace('func pendingRequests() async -> [UNNotificationRequest] { [] }', 'func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }').replace('func add(_ request: UNNotificationRequest) async throws { throw NSError(domain: "QA", code: 1) }', 'func add(_ request: UNNotificationRequest) async throws { pending[request.identifier] = request }').replace('func removePending(identifiers: [String]) { }', 'func removePending(identifiers: [String]) { for id in identifiers { pending.removeValue(forKey: id) } }')
        source = source.replace('let events = [CountdownEvent', 'var events = [CountdownEvent').replace('try! repository.save(events, replacing: [])', 'events[0].dailyReminderTime = CalendarTime(hour: 9, minute: 0); try! repository.save(events, replacing: [])')
    if args.custom_reminder:
        source = source.replace('let events = [CountdownEvent', 'var events = [CountdownEvent').replace('try! repository.save(events, replacing: [])', 'events[0].reminder = .custom; events[0].reminderTime = CalendarTime(hour: 9, minute: 30); events[0].reminderDaysBefore = 0; try! repository.save(events, replacing: [])')
    if args.empty:
        source = source.replace('try! repository.save(events, replacing: [])' , 'try! repository.save([], replacing: [])')
    host = root/'PublicApp.swift'; host.write_text(source)
    sources = sorted((p/'Shared/Core').glob('*.swift')) + sorted((p/'Shared/Presentation').glob('*.swift')) + [p/'Shared/Platform/SharedContainer.swift', p/'App/Stores/EventStore.swift'] + sorted((p/'App/Views').glob('*.swift')) + sorted((p/'App/Services').glob('*.swift')) + sorted((p/'App/Intents').glob('*.swift')) + [host]
    if args.freeze_timeline or args.trace_sort or args.trace_keys:
        original = p/'App/Views/ContentView.swift'
        frozen = root/'ContentView.swift'
        diagnostic = original.read_text()
        if args.trace_keys:
            diagnostic = diagnostic.replace('guard store.isLoaded, !isPresentingModal,\n', 'print("KEY_ROUTE", key.characters, eventListFocused, String(describing: NSApp.keyWindow?.firstResponder)); fflush(stdout)\n        guard store.isLoaded, !isPresentingModal,\n')
        if args.freeze_timeline:
            diagnostic = diagnostic.replace('TimelineView(.animation(minimumInterval: 1, paused: isPresentingModal))', 'TimelineView(.explicit([Date()]))')
        if args.trace_sort:
            diagnostic = diagnostic.replace('button.isBordered = false', 'print("SORT_MAKE", Date(), ObjectIdentifier(button)); fflush(stdout)\n        button.isBordered = false')
            diagnostic = diagnostic.replace('context.coordinator.selection = $selection', 'print("SORT_UPDATE", Date(), ObjectIdentifier(button), NSApp.isActive, context.coordinator.isTracking); fflush(stdout)\n        context.coordinator.selection = $selection')
            diagnostic = diagnostic.replace('func menuWillOpen(_ menu: NSMenu) {', 'func menuWillOpen(_ menu: NSMenu) { print("SORT_OPEN", Date(), NSApp.isActive); fflush(stdout);')
            diagnostic = diagnostic.replace('func menuDidClose(_ menu: NSMenu) {', 'func menuDidClose(_ menu: NSMenu) { print("SORT_CLOSE", Date(), NSApp.isActive); fflush(stdout);')
        frozen.write_text(diagnostic)
        sources = [frozen if path == original else path for path in sources]
    if args.high_contrast:
        original = p/'App/Views/EventRow.swift'
        contrasting = root/'EventRow.swift'
        contrasting.write_text(original.read_text().replace('@Environment(\\.colorSchemeContrast) private var contrast', 'private let contrast: ColorSchemeContrast = .increased'))
        sources = [contrasting if path == original else path for path in sources]
    binary = contents/'MacOS/PublicFeatureQA'
    subprocess.run(['xcrun','swiftc','-parse-as-library','-target','arm64-apple-macos14.0',*map(str,sources),'-o',str(binary)],env=env,check=True,timeout=120)
    # Isolate AppStorage as well as events so an earlier QA dismissal cannot
    # suppress a later first-run check or change shipping preferences.
    bundle_id = 'local.daydistance.publicqa.' + root.name.removesuffix('.noindex')
    (contents/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':bundle_id,'CFBundleExecutable':binary.name,'CFBundleName':'日距公开版验证','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.8.1','CFBundleVersion':'24','CFBundleDevelopmentRegion':'zh-Hans','CFBundleLocalizations':['en','zh-Hans'],'LSMinimumSystemVersion':'14.0'}))
    shutil.copytree(p/'Shared/Core/Resources',contents/'Resources')
    shutil.copytree(p/'Resources/DockIcons',contents/'Resources/DockIcons')
    subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
    print('PUBLIC_QA: '+str(app),flush=True)
    print('DATA: '+str(root/'data/events.json'),flush=True)
    process = subprocess.Popen([str(binary),str(root),'-AppleLanguages',f'({args.language})','-AppleLocale','en_US' if args.language=='en' else 'zh_CN'])
    try:
        code=process.wait()
        if code: raise subprocess.CalledProcessError(code,str(binary))
    finally:
        if process.poll() is None:
            process.terminate();process.wait(timeout=5)
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-u',str(app)],check=False)
