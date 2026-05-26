import Foundation

class SessionStore {
    static let shared = SessionStore()
    var currentSaveURL: URL?
    
    init() {
        let ud = UserDefaults.standard
        if let path = ud.string(forKey: "gfd_session_path") {
            currentSaveURL = URL(fileURLWithPath: path)
        }
    }
    
    func persist() {
        let ud = UserDefaults.standard
        if let url = currentSaveURL { ud.set(url.path, forKey: "gfd_session_path") }
    }
}
