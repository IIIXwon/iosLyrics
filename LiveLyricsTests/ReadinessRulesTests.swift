import Testing
import Foundation
@testable import LiveLyricsExperiment

@MainActor
struct ReadinessRulesTests {

    private func item(_ id: String, ready: Bool) -> ReadinessItem {
        ReadinessItem(id: id, title: id, isReady: ready)
    }

    // MARK: - 라벨 3단계

    @Test func 라벨단계_전부준비됨_준비완료() {
        // given
        let items = [item("a", ready: true), item("b", ready: true), item("c", ready: true)]
        // when
        let result = ReadinessModel.summary(items)
        // then
        #expect(result == .ready)
    }

    @Test func 라벨단계_일부만문제_부분준비와문제개수() {
        // given
        let items = [item("a", ready: true), item("b", ready: false), item("c", ready: false)]
        // when
        let result = ReadinessModel.summary(items)
        // then
        #expect(result == .partial(problems: 2))
    }

    @Test func 라벨단계_전부문제_없음과문제개수() {
        // given
        let items = [item("a", ready: false), item("b", ready: false), item("c", ready: false)]
        // when
        let result = ReadinessModel.summary(items)
        // then
        #expect(result == .notReady(problems: 3))
    }

    @Test func 라벨단계_항목이없으면_준비완료() {
        // given
        let items: [ReadinessItem] = []
        // when
        let result = ReadinessModel.summary(items)
        // then
        #expect(result == .ready)
    }

    // MARK: - Spotify 항목

    @Test func Spotify항목_로그인안됨_버튼없이_로그인필요문구() {
        // given
        let isConfigured = true, isLoggedIn = false, needsRelogin = false
        // when
        let result = ReadinessModel.spotifyItem(isConfigured: isConfigured, isLoggedIn: isLoggedIn, needsRelogin: needsRelogin)
        // then
        #expect(result.isReady == false)
        #expect(result.fix == nil)
        #expect(result.fixTitle == nil)
        #expect(result.problem == "로그인이 필요해요")
    }

    @Test func Spotify항목_다시로그인필요_버튼없이_로그아웃후재로그인문구() {
        // given
        let isConfigured = true, isLoggedIn = true, needsRelogin = true
        // when
        let result = ReadinessModel.spotifyItem(isConfigured: isConfigured, isLoggedIn: isLoggedIn, needsRelogin: needsRelogin)
        // then
        #expect(result.isReady == false)
        #expect(result.fix == nil)
        #expect(result.problem == "Spotify 칸에서 로그아웃 후 다시 로그인해 주세요")
    }

    @Test func Spotify항목_로그인됨_준비됨과로그인됨설명() {
        // given
        let isConfigured = true, isLoggedIn = true, needsRelogin = false
        // when
        let result = ReadinessModel.spotifyItem(isConfigured: isConfigured, isLoggedIn: isLoggedIn, needsRelogin: needsRelogin)
        // then
        #expect(result.isReady == true)
        #expect(result.okDetail == "로그인됨")
    }

    @Test func Spotify항목_설정안됨_버튼없이_ClientID문구() {
        // given
        let isConfigured = false, isLoggedIn = false, needsRelogin = false
        // when
        let result = ReadinessModel.spotifyItem(isConfigured: isConfigured, isLoggedIn: isLoggedIn, needsRelogin: needsRelogin)
        // then
        #expect(result.isReady == false)
        #expect(result.fix == nil)
        #expect(result.problem == "SpotifyConfig.swift에 Client ID를 넣어 주세요")
    }
}
