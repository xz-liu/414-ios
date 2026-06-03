import Foundation

public enum HintEngine {
    public static func bestAction(state: GameState, for playerIndex: Int) -> PlayerAction? {
        guard state.prompt.playerIndex == playerIndex else { return nil }
        let ai = AIPlayer()
        let legal = ai.legalActions(from: state, for: playerIndex)
        guard !legal.isEmpty else { return nil }
        let chosen = ai.chooseAction(state: state, for: playerIndex)
        if legal.contains(chosen), chosen.cards.isEmpty == false {
            return chosen
        }
        return legal.first { !$0.cards.isEmpty }
    }
}
