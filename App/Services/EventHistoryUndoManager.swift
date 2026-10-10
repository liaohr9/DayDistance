import Foundation

/// One application-owned history, separate from native text-field undo managers.
/// Gate before Foundation consumes a group; rejecting an undo callback is too late.
final class EventHistoryUndoManager: UndoManager, @unchecked Sendable {
    var shouldPerformHistory: @MainActor () -> Bool = { false }
    private var clearAfterOperation = false

    override init() {
        super.init()
        groupsByEvent = false
    }

    override var canUndo: Bool {
        let hasHistory = super.canUndo
        return MainActor.assumeIsolated { hasHistory && shouldPerformHistory() }
    }

    override var canRedo: Bool {
        let hasHistory = super.canRedo
        return MainActor.assumeIsolated { hasHistory && shouldPerformHistory() }
    }

    override func undo() {
        guard MainActor.assumeIsolated({ shouldPerformHistory() }), super.canUndo else { return }
        super.undo()
        clearInvalidatedHistory()
    }

    override func redo() {
        guard MainActor.assumeIsolated({ shouldPerformHistory() }), super.canRedo else { return }
        super.redo()
        clearInvalidatedHistory()
    }

    /// Foundation finishes creating its inverse group after a callback returns.
    /// A failed CAS must also discard that group, so clear after the operation.
    func invalidateHistory() {
        if isUndoing || isRedoing { clearAfterOperation = true }
        else { removeAllActions() }
    }

    private func clearInvalidatedHistory() {
        guard clearAfterOperation else { return }
        clearAfterOperation = false
        removeAllActions()
    }
}
