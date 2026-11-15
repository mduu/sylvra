import Testing

@testable import SylvraCore

struct UserRefTests {
    @Test func initialsUseNameWhenAvailable() {
        #expect(UserRef(login: "lkeller", name: "Lena Keller").initials == "LK")
    }

    @Test func initialsFallBackToLogin() {
        #expect(UserRef(login: "octo-cat").initials == "OC")
    }

    @Test func fullNameJoinsOwnerAndName() {
        #expect(RepositoryRef(owner: "mduu", name: "sylvra").fullName == "mduu/sylvra")
    }
}
