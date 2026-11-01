import Testing
@testable import LiveLyricsExperiment

struct LoginScopesTests {
    // 032-1
    @Test func 권한판단_기록이없으면_false() {
        // given
        let granted: String? = nil

        // when
        let result = LoginScopes.isSatisfied(granted: granted, required: ["a", "b"])

        // then
        #expect(result == false)
    }

    // 032-2
    @Test func 권한판단_필요한권한이모두있으면_true() {
        // given // when
        let result = LoginScopes.isSatisfied(granted: "a b", required: ["a", "b"])

        // then
        #expect(result == true)
    }

    // 032-3
    @Test func 권한판단_순서가달라도더많아도_true() {
        // given // when
        let result = LoginScopes.isSatisfied(granted: "c b a", required: ["a", "b"])

        // then
        #expect(result == true)
    }

    // 032-4
    @Test func 권한판단_하나가빠졌으면_false() {
        // given // when
        let result = LoginScopes.isSatisfied(granted: "a", required: ["a", "b"])

        // then
        #expect(result == false)
    }

    // 032-5
    @Test func 권한판단_공백이여러개여도_true() {
        // given // when
        let result = LoginScopes.isSatisfied(granted: "a  b ", required: ["a", "b"])

        // then
        #expect(result == true)
    }

    // 032-6
    @Test func 권한판단_필요한권한이없으면_빈기록이어도_true() {
        // given // when
        let result = LoginScopes.isSatisfied(granted: "", required: [])

        // then
        #expect(result == true)
    }
}
