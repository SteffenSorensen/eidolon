import Quick
import Nimble
import RxSwift
@testable
import Kiosk
import Moya
import RxBlocking

let testPassword = "password"
let testEmail = "test@example.com"

class RegistrationPasswordViewModelTests: QuickSpec {

    typealias Check = (() -> ())?

    @warn_unused_result
    func stubProvider(emailExists emailExists: Bool, emailCheck: Check, loginSucceeds: Bool, loginCheck: Check, passwordRequestSucceeds: Bool, passwordCheck: Check) -> Networking {

        let endpointsClosure = { (target: ArtsyAPI) -> Endpoint<ArtsyAPI> in

            switch target {
            case ArtsyAPI.FindExistingEmailRegistration(let email):
                emailCheck?()
                expect(email) == testEmail
                return Endpoint<ArtsyAPI>(URL: url(target), sampleResponseClosure: {.NetworkResponse(emailExists ? 200 : 404, NSData())}, method: target.method, parameters: target.parameters)
            case ArtsyAPI.LostPasswordNotification(let email):
                passwordCheck?()
                expect(email) == testEmail
                return Endpoint<ArtsyAPI>(URL: url(target), sampleResponseClosure: {.NetworkResponse(passwordRequestSucceeds ? 200 : 404, NSData())}, method: target.method, parameters: target.parameters)
            case ArtsyAPI.XAuth(let email, let password):
                loginCheck?()
                expect(email) == testEmail
                expect(password) == testPassword
                // Fail auth (wrong password maybe)
                return Endpoint<ArtsyAPI>(URL: url(target), sampleResponseClosure: {.NetworkResponse(loginSucceeds ? 200 : 403, NSData())}, method: target.method, parameters: target.parameters)
            case .XApp:
                // Any XApp requests are incidental; ignore.
                return MoyaProvider<ArtsyAPI>.DefaultEndpointMapping(target)
            default:
                // Fail on all other cases
                fail("Unexpected network call")
                return Endpoint<ArtsyAPI>(URL: url(target), sampleResponseClosure: {.NetworkResponse(200, NSData())}, method: target.method, parameters: target.parameters)
            }
        }

        return Networking(provider: OnlineProvider(endpointClosure: endpointsClosure, stubClosure: MoyaProvider.ImmediatelyStub, online: Observable.just(true)))
    }

    func testSubject(provider: Networking = Networking.newStubbingNetworking(), passwordSubject: Observable<String> = Observable.just(testPassword), invocation: Observable<Void> = PublishSubject<Void>().asObservable(), finishedSubject: PublishSubject<Void> = PublishSubject<Void>()) -> RegistrationPasswordViewModel {
        return RegistrationPasswordViewModel(provider: provider, password: passwordSubject, execute: invocation, completed: finishedSubject, email: testEmail)
    }

    override func spec() {

        var disposeBag: DisposeBag!

        beforeEach {
            disposeBag = DisposeBag()
        }

        it("enables the command when the password is valid") {
            let passwordSubject = Variable<String>("validpassword")

            let subject = self.testSubject(passwordSubject: passwordSubject.asObservable())

            expect(try! subject.action.enabled.toBlocking().first()).to( beTrue() )
        }

        it("disables the command when the password is too short") {
            let passwordSubject = Variable<String>("nope")

            let subject = self.testSubject(passwordSubject: passwordSubject.asObservable())

            expect(try! subject.action.enabled.toBlocking().first()).to( beFalse() )
        }

        it("disables the command when the password is empty") {
            let passwordSubject = Variable<String>("")

            let subject = self.testSubject(passwordSubject: passwordSubject.asObservable())

            expect(try! subject.action.enabled.toBlocking().first()).to( beFalse() )
        }

        it("checks for an email when executing the command") {
            var checked = false

            let networking = self.stubProvider(emailExists: false, emailCheck: {
                checked = true
            }, loginSucceeds: true, loginCheck: nil, passwordRequestSucceeds: true, passwordCheck: nil)

            let subject = self.testSubject(networking)
            let disposeBag = DisposeBag()

            waitUntil { done in
                subject.action.execute().subscribeCompleted {
                    done()
                }.addDisposableTo(disposeBag)
            }

            expect(checked).to( beTrue() )
        }

        it("sends true on emailExists if email exists") {
            var exists = false

            let networking = self.stubProvider(emailExists: true, emailCheck: {
                exists = true
            }, loginSucceeds: true, loginCheck: nil, passwordRequestSucceeds: true, passwordCheck: nil)

            let subject = self.testSubject(networking)
            let disposeBag = DisposeBag()

            subject
                .emailExists
                .subscribeNext { (object) in
                    exists = object
                }
                .addDisposableTo(disposeBag)

            waitUntil { done in
                subject.action.execute().subscribeCompleted {
                    done()
                }.addDisposableTo(disposeBag)
            }
            
            expect(exists).to( beTrue() )
        }

        it("sends false on emailExists if email does not exist") {
            var exists: Bool?

            let networking = self.stubProvider(emailExists: false, emailCheck: {
                exists = true
            }, loginSucceeds: true, loginCheck: nil, passwordRequestSucceeds: true, passwordCheck: nil)

            let subject = self.testSubject(networking)
            let disposeBag = DisposeBag()

            subject
                .emailExists
                .subscribeNext { (object) in
                    exists = object
                }
                .addDisposableTo(disposeBag)

            waitUntil { done in
                subject.action.execute().subscribeCompleted {
                    done()
                }.addDisposableTo(disposeBag)
            }

            expect(exists).toNot( beNil() )
            expect(exists).to( beFalse() )
        }

        it("checks for authorization if the email exists") {
            var checked = false
            var authed = false

            let networking = self.stubProvider(emailExists: true, emailCheck: {
                checked = true
            }, loginSucceeds: true, loginCheck: {
                authed = true
            }, passwordRequestSucceeds: true, passwordCheck: nil)

            let subject = self.testSubject(networking)
            let disposeBag = DisposeBag()


            waitUntil { done in
                subject.action.execute().subscribeCompleted {
                    done()
                }.addDisposableTo(disposeBag)
            }
            
            expect(checked).to( beTrue() )
            expect(authed).to( beTrue() )
        }

        it("sends an error on the command if the authorization fails") {
            let networking = self.stubProvider(emailExists: true, emailCheck: nil, loginSucceeds: false, loginCheck: nil, passwordRequestSucceeds: true, passwordCheck: nil)

            let subject = self.testSubject(networking)
            let disposeBag = DisposeBag()

            var errored = false

            subject
                .action
                .errors
                .subscribeNext { _ in
                    errored = true
                }
                .addDisposableTo(disposeBag)

            waitUntil { done in
                subject.action.execute().subscribeError { _ in
                    done()
                }.addDisposableTo(disposeBag)
            }

            expect(errored).to( beTrue() )
        }

        it("executes command when manual  sends") {
            let networking = self.stubProvider(emailExists: false, emailCheck: nil, loginSucceeds: false, loginCheck: nil, passwordRequestSucceeds: true, passwordCheck: nil)

            let invocation = PublishSubject<Void>()

            let subject = self.testSubject(networking, invocation: invocation)
            let disposeBag = DisposeBag()

            var completed = false

            subject
                .action
                .executing
                .take(1)
                .subscribeNext { _ in
                    completed = true
                }
                .addDisposableTo(disposeBag)

            invocation.onNext()
            
            expect(completed).to( beTrue() )
        }

        it("sends completed on finishedSubject when command is executed") {
            let invocation = PublishSubject<Void>()
            let finishedSubject = PublishSubject<Void>()

            var completed = false

            finishedSubject
                .subscribeCompleted {
                    completed = true
                }
                .addDisposableTo(disposeBag)

            let subject = self.testSubject(invocation:invocation, finishedSubject: finishedSubject)
            let disposeBag = DisposeBag()
            
            waitUntil { done in
                subject.action.execute().subscribeCompleted {
                    done()
                }.addDisposableTo(disposeBag)
            }

            expect(completed).to( beTrue() )
        }

        it("handles password reminders") {
            var sent = false

            let networking = self.stubProvider(emailExists: true, emailCheck: nil, loginSucceeds: true, loginCheck: nil, passwordRequestSucceeds: true, passwordCheck: {
                sent = true
            })

            let subject = self.testSubject(networking)
            let disposeBag = DisposeBag()

            waitUntil { done in
                subject
                    .userForgotPassword()
                    .subscribeCompleted {
                        // do nothing – we subscribe just to force the observable to execute.
                        done()
                    }
                    .addDisposableTo(disposeBag)
            }

            expect(sent).to( beTrue() )
        }
    }
}
