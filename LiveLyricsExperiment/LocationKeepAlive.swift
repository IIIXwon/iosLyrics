// 앱 타깃 — 백그라운드 위치 추적으로 앱을 살려 둠 (저전력 버전)
//
// 목적은 "위치"가 아니라 "앱을 백그라운드에서 계속 실행"하는 것이므로,
// 위치 정확도와 위치 알림 횟수를 최대한 낮춰 배터리 소모를 줄여요.
//
// ⚠️ Signing & Capabilities → Background Modes → "Location updates"를 반드시 켜야 해요.
import CoreLocation

@MainActor
final class LocationKeepAlive: NSObject {
    private let manager = CLLocationManager()
    private(set) var isRunning = false
    private(set) var receivedCount = 0   // start() 이후 받은 위치 횟수 (재시작이 실제로 됐는지 확인용)
    var onLog: (@MainActor (String) -> Void)?
    /// 위치 권한이 바뀌었을 때 (준비 상태 화면 갱신용)
    var onAuthorizationChange: (@MainActor () -> Void)?

    override init() {
        super.init()
        manager.delegate = self

        // ① GPS를 쓰지 않는 가장 낮은 정확도 (기지국·와이파이 수준) → 가장 큰 절약 효과
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers

        // ② 위치가 바뀌어도 앱을 거의 깨우지 않음 (수천 km 이동해야 알림)
        //    앱은 위치 서비스가 켜져 있다는 이유만으로 계속 실행돼요
        manager.distanceFilter = CLLocationDistanceMax

        // ③ 자동 일시정지 끄기 — 켜 두면 가만히 있을 때 iOS가 위치를 멈추고 앱도 멈춰요
        manager.pausesLocationUpdatesAutomatically = false
        manager.activityType = .other
    }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    /// 화면·로그에 보여 줄 현재 위치 권한 ("항상" / "앱 사용 중" / …)
    var authorizationText: String { statusText(manager.authorizationStatus) }

    /// 위치 추적 시작. 권한이 없으면 요청하고 false 반환
    func start() -> Bool {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            onLog?("📍 위치 권한을 요청했어요 → '앱을 사용하는 동안 허용'을 누른 뒤 다시 [시작]")
            return false
        case .denied, .restricted:
            onLog?("❌ 위치 권한 없음 → 설정 → LiveLyricsExperiment → 위치 → '앱을 사용하는 동안'")
            return false
        default:
            break
        }
        manager.allowsBackgroundLocationUpdates = true
        // ④ '항상 허용'이면 상단 파란 표시를 숨김 ('앱 사용 중'이면 iOS가 강제로 표시)
        manager.showsBackgroundLocationIndicator = manager.authorizationStatus != .authorizedAlways
        manager.startUpdatingLocation()
        receivedCount = 0
        isRunning = true
        onLog?("📍 위치 추적 시작 — 저전력 (권한: \(statusText(manager.authorizationStatus)))")
        return true
    }

    func stop() {
        guard isRunning else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isRunning = false
        onLog?("📍 위치 추적 정지 (위치 수신 \(receivedCount)회)")
    }

    /// 위치 권한("앱을 사용하는 동안") 요청. 준비 상태 화면에서 사용자가 버튼을 눌렀을 때만 부름 (앱 시작 때 자동으로 띄우지 않음)
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// '항상 허용' 요청 (파란 표시를 없애고 싶을 때)
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    fileprivate func received() {
        receivedCount += 1   // 수신 로그는 남기지 않음 (시작·정지·실패 로그로 충분, 작업 010)
    }

    fileprivate func statusText(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "항상"
        case .authorizedWhenInUse: return "앱 사용 중"
        case .denied: return "거부"
        case .restricted: return "제한"
        case .notDetermined: return "미정"
        @unknown default: return "알 수 없음"
        }
    }
}

extension LocationKeepAlive: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.received() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.onLog?("⚠️ 위치 오류: \(message)") }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.onLog?("📍 위치 권한 변경: \(self.statusText(status))")
            self.onAuthorizationChange?()
            // 실행 중에 '항상'으로 바뀌면 파란 표시 즉시 숨김
            if self.isRunning {
                self.manager.showsBackgroundLocationIndicator = status != .authorizedAlways
            }
        }
    }
}
