import Foundation

extension Task where Success: Sendable, Failure == Never {
    func receive(on actor: MainActor.Type, _ body: @escaping @MainActor (Success) -> Void) {
        Task<Void, Never> {
            let value = await self.value
            await MainActor.run {
                body(value)
            }
        }
    }
}
