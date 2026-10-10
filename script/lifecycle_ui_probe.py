"""Build a disposable host from the real app source without changing product code."""


def lifecycle_source(source):
    store = 'let initialStore = EventStore(automaticallyLoad: false)'
    scene = '.defaultSize(width: 800, height: 520)'
    if source.count(store) != 1 or source.count('EventStore(') != 1 or source.count(scene) != 1:
        raise ValueError('Production app entrypoint changed; refuse a QA host that may use real data')
    source = source.replace('repositoryProvider: { try SharedContainer.repository() }', 'repositoryProvider: { EventRepository(fileURL: LifecycleProbeRepository.root.appendingPathComponent("data/events.json")) }')
    return source.replace(store, 'let initialStore = LifecycleProbeRepository.makeStore()', 1).replace(
        scene, scene + '\n        .commands { LifecycleProbeCommands() }', 1)
