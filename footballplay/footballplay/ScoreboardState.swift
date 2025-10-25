import Foundation
import Combine

final class ScoreboardState: ObservableObject {
    @Published var homeTeamName: String = "熱血踢球隊"
    @Published var awayTeamName: String = "TFA 阿寶亮斯"
    @Published var homeScore: Int = 0
    @Published var awayScore: Int = 0
    @Published var currentSet: Int = 1
}
