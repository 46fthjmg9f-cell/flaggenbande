import SwiftUI
import Foundation

extension ContentView {
    var friendNames: [String] {
        friendNamesRawValue
            .split(separator: "|")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    var onlineDisplayName: String {
        OnlineStatsService.normalizedName(onlinePlayerName, fallback: gameCenterAlias.isEmpty ? L("Nicht gesetzt", "Not set") : gameCenterAlias)
    }

    var deduplicatedOnlineLeaderboard: [OnlinePlayerStats] {
        var playersByKey: [String: OnlinePlayerStats] = [:]
        let newestFirst = onlineLeaderboard.sorted { $0.updatedAt > $1.updatedAt }

        for player in newestFirst {
            let key = onlineDeduplicationKey(for: player)
            if let existingPlayer = playersByKey[key] {
                playersByKey[key] = preferredOnlinePlayer(existingPlayer, player)
            } else {
                playersByKey[key] = player
            }
        }

        return playersByKey.values.sorted {
            let firstStats = $0.stats(for: selectedSubject)
            let secondStats = $1.stats(for: selectedSubject)
            if firstStats.totalPracticed == secondStats.totalPracticed {
                return firstStats.accuracy > secondStats.accuracy
            }
            return firstStats.totalPracticed > secondStats.totalPracticed
        }
    }

    var friendLeaderboard: [OnlinePlayerStats] {
        let normalizedFriends = Set(friendNames.map { normalizedFriendToken($0) })
        return deduplicatedOnlineLeaderboard.filter { player in
            gameCenterFriendIDs.contains(player.gameCenterPlayerID) ||
            normalizedFriends.contains(normalizedFriendToken(player.playerName)) ||
            normalizedFriends.contains(normalizedFriendToken(player.gameCenterAlias)) ||
            normalizedFriends.contains(normalizedFriendToken(player.friendCode))
        }
    }

    var gameCenterFriendPlayers: [OnlinePlayerStats] {
        let manualFriendIDs = Set(friendNames.compactMap { onlinePlayer(forFriend: $0)?.id })
        return friendLeaderboard
            .filter { gameCenterFriendIDs.contains($0.gameCenterPlayerID) && !manualFriendIDs.contains($0.id) }
            .sorted { $0.displayName < $1.displayName }
    }

    func onlinePlayer(forFriend friend: String) -> OnlinePlayerStats? {
        let token = normalizedFriendToken(friend)
        return deduplicatedOnlineLeaderboard.first { player in
            normalizedFriendToken(player.playerName) == token ||
            normalizedFriendToken(player.gameCenterAlias) == token ||
            normalizedFriendToken(player.friendCode) == token ||
            normalizedFriendToken(player.displayName) == token
        }
    }

    func openFriendStatsFromFriendList(_ player: OnlinePlayerStats) {
        isShowingFriendList = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            selectedOnlineGlobePlayer = player
        }
    }

    var scopedOnlineLeaderboard: [OnlinePlayerStats] {
        selectedOnlineScope == .friends ? friendLeaderboard : deduplicatedOnlineLeaderboard
    }

    var scopedFlaggenrunLeaderboard: [OnlinePlayerStats] {
        let source = selectedOnlineScope == .friends ? friendLeaderboard : deduplicatedOnlineLeaderboard
        return source.sorted {
            if $0.leagueBestScore == $1.leagueBestScore {
                return $0.stats(for: selectedSubject).learnedThisWeek > $1.stats(for: selectedSubject).learnedThisWeek
            }
            return $0.leagueBestScore > $1.leagueBestScore
        }
    }

    var scopedBestLearningStreakLeaderboard: [OnlinePlayerStats] {
        let source = selectedOnlineScope == .friends ? friendLeaderboard : deduplicatedOnlineLeaderboard
        return source.sorted {
            if $0.bestLearningStreak == $1.bestLearningStreak {
                return $0.stats(for: selectedSubject).learnedThisWeek > $1.stats(for: selectedSubject).learnedThisWeek
            }
            return $0.bestLearningStreak > $1.bestLearningStreak
        }
    }

    var friendFlaggenscoreLeaderboard: [OnlinePlayerStats] {
        friendLeaderboard.sorted {
            let firstScore = onlineFlaggenbossScore(for: $0)
            let secondScore = onlineFlaggenbossScore(for: $1)
            if firstScore == secondScore {
                return $0.stats(for: selectedSubject).learnedThisWeek > $1.stats(for: selectedSubject).learnedThisWeek
            }
            return firstScore > secondScore
        }
    }

    var scopedLearnedThisWeekLeaderboard: [OnlinePlayerStats] {
        let source = selectedOnlineScope == .friends ? friendLeaderboard : deduplicatedOnlineLeaderboard
        return source.sorted {
            let firstStats = $0.stats(for: selectedSubject)
            let secondStats = $1.stats(for: selectedSubject)
            if firstStats.learnedThisWeek == secondStats.learnedThisWeek {
                return firstStats.accuracy > secondStats.accuracy
            }
            return firstStats.learnedThisWeek > secondStats.learnedThisWeek
        }
    }

    var scopedAchievementLeaderboard: [OnlinePlayerStats] {
        let source = selectedOnlineScope == .friends ? friendLeaderboard : deduplicatedOnlineLeaderboard
        return source.sorted {
            if $0.achievementCount == $1.achievementCount {
                return $0.stats(for: selectedSubject).totalPracticed > $1.stats(for: selectedSubject).totalPracticed
            }
            return $0.achievementCount > $1.achievementCount
        }
    }

    var learnedThisWeekLeaderboard: [OnlinePlayerStats] {
        deduplicatedOnlineLeaderboard.sorted {
            let firstStats = $0.stats(for: selectedSubject)
            let secondStats = $1.stats(for: selectedSubject)
            if firstStats.learnedThisWeek == secondStats.learnedThisWeek {
                return firstStats.accuracy > secondStats.accuracy
            }
            return firstStats.learnedThisWeek > secondStats.learnedThisWeek
        }
    }

    var achievementLeaderboard: [OnlinePlayerStats] {
        deduplicatedOnlineLeaderboard.sorted {
            if $0.achievementCount == $1.achievementCount {
                return $0.stats(for: selectedSubject).totalPracticed > $1.stats(for: selectedSubject).totalPracticed
            }
            return $0.achievementCount > $1.achievementCount
        }
    }

    func onlineDeduplicationKey(for player: OnlinePlayerStats) -> String {
        if isCurrentOnlinePlayer(player) {
            return "current"
        }

        if !player.gameCenterPlayerID.isEmpty {
            return "gc:\(player.gameCenterPlayerID)"
        }

        let displayNameToken = normalizedFriendToken(player.displayName)
        if !displayNameToken.isEmpty && displayNameToken != "spieler" && displayNameToken != "player" {
            return "name:\(displayNameToken)"
        }

        return "id:\(player.id)"
    }

    func preferredOnlinePlayer(_ first: OnlinePlayerStats, _ second: OnlinePlayerStats) -> OnlinePlayerStats {
        if isCurrentOnlinePlayer(first) != isCurrentOnlinePlayer(second) {
            return isCurrentOnlinePlayer(first) ? first : second
        }

        if first.gameCenterPlayerID.isEmpty != second.gameCenterPlayerID.isEmpty {
            return first.gameCenterPlayerID.isEmpty ? second : first
        }

        if first.updatedAt != second.updatedAt {
            return first.updatedAt > second.updatedAt ? first : second
        }

        return first.stats(for: selectedSubject).totalPracticed >= second.stats(for: selectedSubject).totalPracticed ? first : second
    }


}
