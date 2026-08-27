import GamesLib
import UIKit
import SwiftUI


/// 4. Game - provide game Controller.
/// This is the main entry class to the game. It has to be named Game and conform to GameCard protocol
class Game: GameCard {
    /// returns full screen game view controller which is displayed modally fullscreen by the host app
    static func viewController(data: [String : Any]?) -> UIViewController? {
        /// The game itself is a web app; the navigation controller supplies the
        /// bar the web page deliberately does not render in native mode.
        let game = GameWebViewController(launchUrl: data?["link"] as? String)
        return UINavigationController(rootViewController: game)
    }
}

struct GameBody: View {
    /// Native reference implementation, reachable from the web game's debug
    /// button so the two can be compared side by side.
    static func hostingController(data: [String: Any]?) -> UIViewController {
        UIHostingController(rootView: GameBody(data: data))
    }

    /// initial data passed by the game
    var data: [String: Any]?
    @State var user: GHUser?
    /// GamingHubCards.isLoggedIn returns current  user login state
    @State var isLoggedIn = GamingHubCards.isLoggedIn
    
    init(data: [String: Any]?){
        self.data = data
        
        /// 8. Deeplinking on  game start
        processDeeplink(data: data)
        
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16){
                Text("Hello, I'm the game!")
                
                /// 1. Environment info: you can always get it by accessing: GamingHubCards.environment
                Text("Environment: \(GamingHubCards.environment.environment)")
                    .navigationTitle("Last Man Standing")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                openMenu()
                            } label: {
                                Image(systemName: "line.3.horizontal")
                            }
                            .accessibilityLabel("Open Menu")
                        }
                    }
                
                /// check if user is logged in on Gaming
                if isLoggedIn {
                    /// logged in. You have access to the user info
                    Text("Username: \(user?.username ?? "")")
                    /// user ID
                    Text("UserID: \(user?.uefaId ?? "-")")
                }else{
                    /// not logged in - show login option if needed:
                    Button("Login") {
                        requestLogin()
                    }
                }
                
                Spacer()
                Button("Ask Host to open link"){
                    openLink()
                }
            }
            
        }
        .onAppear{
            /// 2. GamingHubCards.user returns a copy current user info (name,  id, avatars, access token)
            user = GamingHubCards.user
        }
        .ghOnLoggedIn {
            /// listen to login .ghLoggedIn
            /// in UIKit:
            /*
             NotificationCenter.default.addObserver(self,
                                                    selector: #selector(onLoginLogout(notification:)),
                                                    name: .ghLoggedIn,
                                                    object: nil)
            */
            authorizeWithGameBackend()
            
        }
        .ghOnLoggedOut {
            /// listen to login .ghLoggedOut
            /// in UIKit:
            /*
             NotificationCenter.default.addObserver(self,
                                                    selector: #selector(onLoginLogout(notification:)),
                                                    name: .ghLoggedOut,
                                                    object: nil)
            */
            
            clearGameSession()
        }
        .ghOnNotification(.ghOpenLink) { data in
            /// 8. Deeplink - listen to depelink in already playing game
            /// in UIKit:
            /*
             NotificationCenter.default.addObserver(self,
                                                    selector: #selector(onDeepLink(notification:)),
                                                    name: .ghOpenLink,
                                                    object: nil)
             */
            processDeeplink(data: data as? [String: Any])
        }
    }
    
    /// 7. Menu - ask the Host app to open menu ( so user can navigate to other screens on the app)
    /// when user taps menu icon on top left corner of the screen, the game:
    /// - will close in POC
    /// - in final Host app the menu will showup
    private func openMenu() {
        GamingHubCards.openMenu()
    }
    
    ///3. Login/registratin flow.  ask host app to authenticate and autorize the user.
    private func requestLogin() {
        /// start login flow
        GamingHubCards.login("epllastmanstanding")
        /// or registration flow
        //GamingHubCards.register("epllastmanstanding")
    }
    
    private func authorizeWithGameBackend() {
        user = GamingHubCards.user
        isLoggedIn = GamingHubCards.isLoggedIn
        
        // TODO: Authorize with Game backend
        print("user acceess token:\(GamingHubCards.user.token?.token ?? ".")")
    }

    private func clearGameSession() {
        user = nil
        isLoggedIn = GamingHubCards.isLoggedIn
        
        // TODO: Do whatever is needed to clear and reset game flow when user logs out
    }
    
    
    // process deeplink
    func processDeeplink(data: [String: Any]?){
        if let path = data?["link"] as? String, let url = URL(string: path) {
            print("GAME DEEPLINK to process \(url.absoluteString)")
        }
    }
    
    /// ask Host to open (process) the a link
    func openLink(){
        GamingHubCards.openDeepLink("https://dreamteam.com/en/epllastmanstanding/idasdfjhaefhewaihfoiewqagfh")
    }
}
