import CoreLocation

// ============================================================
//  LocationManager = '현재 위치 한 번 받아오기' 도우미.
//  - 처음엔 위치 권한을 물어보고(허용해야 동작),
//  - 위치를 1회 받아온 뒤, 가까운 장소 이름까지(역지오코딩) 붙여
//    LocationStamp(위도·경도·이름)로 돌려줘요.
//
//  @unchecked Sendable: 이 객체의 일들은 전부 메인 스레드(앱 UI)에서만
//  일어나므로 안전하다고 우리가 보증한다는 표시예요.
// ============================================================
final class LocationManager: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = LocationManager()

    private let manager = CLLocationManager()
    private var pending: ((LocationStamp?) -> Void)?   // 결과를 돌려줄 콜백

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // 현재 위치를 1회 요청. 끝나면 completion(결과)로 알려줘요(실패하면 nil).
    func requestStamp(_ completion: @escaping (LocationStamp?) -> Void) {
        pending = completion
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // 권한 물어본 뒤, 콜백에서 위치 요청
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            deliver(nil)                              // 거부/제한이면 실패
        }
    }

    private func deliver(_ stamp: LocationStamp?) {
        let p = pending
        pending = nil
        p?(stamp)
    }

    // 권한 응답이 오면: 허용이면 위치 요청, 거부면 실패 처리
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        guard pending != nil else { return }
        switch m.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            m.requestLocation()
        case .denied, .restricted:
            deliver(nil)
        default:
            break
        }
    }

    // 위치를 받으면: 장소 이름까지 붙여서 돌려줘요
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let loc = locs.last else { deliver(nil); return }
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        CLGeocoder().reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            let name = placemarks?.first.flatMap { $0.name ?? $0.locality }
            self?.deliver(LocationStamp(latitude: lat, longitude: lon, name: name))
        }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        deliver(nil)
    }
}
