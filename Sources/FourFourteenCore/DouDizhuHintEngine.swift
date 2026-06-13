import Foundation

public enum DouDizhuHintEngine {
    public static func bestAction(state: DouDizhuState, for playerIndex: Int) -> DouDizhuAction? {
        guard state.phase == .playing,
              state.currentPlayerIndex == playerIndex
        else { return nil }

        let ai = DouDizhuAIPlayer()
        let legal = ai.legalPlayActions(from: state, for: playerIndex)
        guard !legal.isEmpty else { return nil }

        let chosen = ai.chooseAction(state: state, for: playerIndex)
        if legal.contains(chosen), !chosen.cards.isEmpty {
            return chosen
        }
        return legal.first { !$0.cards.isEmpty }
    }
}
