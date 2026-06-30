# ca_attendance — Client chấm công (iOS + Android)

App Flutter cho nhân viên, tập trung vào **cơ chế xác minh thiết bị** của backend chấm công LAN. Thiết bị tự sinh cặp khoá **EC P-256**, giữ private key cục bộ, và ký từng lần chấm công bằng **ECDSA (SHA256withECDSA)** để backend xác minh — không cần HTTPS, an toàn trong mạng nội bộ cô lập.

> Phạm vi: chỉ **3 luồng thiết bị** (enroll → challenge → attendance). Các thao tác admin (đăng nhập, phát mã ghép cặp, báo cáo) dùng Postman/curl hoặc app admin riêng.

## Luồng nghiệp vụ

1. **Kết nối máy chủ** — nhập địa chỉ LAN, ví dụ `http://192.168.1.10:8080`.
2. **Ghép cặp** (`POST /api/devices/enroll`) — nhập mã ghép cặp do admin cấp. App sinh khoá P-256 và **ký mã ghép cặp** (proof-of-possession), gửi public key (X.509) lên server. Server trả `deviceId` + `employeeId`, app lưu lại.
3. **Chấm công** (`POST /api/challenge` → `POST /api/attendance`) — bấm *Vào ca*/*Tan ca*: app xin challenge (nonce 32 byte), **ký `nonce ‖ "CHECK_IN"|"CHECK_OUT"`**, gửi chữ ký để ghi nhận.

## Tương thích crypto với backend (đã kiểm chứng)

Định dạng được chọn để khớp **đúng từng byte** với verifier `java.security` của backend:

| Hạng mục | Định dạng |
|---|---|
| Cặp khoá | EC **secp256r1 (P-256)** |
| Public key gửi lên | **X.509 SubjectPublicKeyInfo**, DER, Base64 chuẩn |
| Chữ ký | **DER** `SEQUENCE { INTEGER r, INTEGER s }` (low-S), Base64 chuẩn |
| Thuật toán ký | **SHA256withECDSA**, k tất định **RFC 6979** |

Tính tương thích đã được verify bằng chính primitive JDK 17 mà backend dùng (`X509EncodedKeySpec` + `Signature("SHA256withECDSA")`): public key parse `fieldSize=256`, chữ ký enroll & attendance đều `verified=true`. Có thể tái tạo:

```bash
dart run tool/gen_vector.dart vector.txt   # sinh test vector bằng crypto của app
# rồi verify vector.txt bằng JDK (xem tool/ + scratchpad/Verify.java)
```

## Cấu trúc mã

```
lib/
  crypto/ec_signer.dart        # keygen P-256, export SPKI, ký -> DER (pointycastle)
  data/
    models.dart                # DTO + AttendanceType + ApiException
    api_client.dart            # HTTP tới /devices/enroll, /challenge, /attendance
    local_store.dart           # lưu private key + deviceId (shared_preferences)
    device_repository.dart     # ghép 3 luồng: enroll, recordAttendance
  state/app_state.dart         # ChangeNotifier điều phối UI
  ui/                          # server_setup, enroll, attendance
  main.dart                    # routing theo trạng thái (setup -> enroll -> attendance)
tool/gen_vector.dart           # sinh vector kiểm thử interop
```

## Bảo mật / mạng LAN

- Dùng **HTTP thường** (đã bật `usesCleartextTraffic` trên Android, ATS `NSAllowsArbitraryLoads` trên iOS). An toàn vì xác minh dựa trên chữ ký số + challenge một-lần, không phụ thuộc TLS.
- Private key lưu dạng **software key** (`shared_preferences`) — đủ với mô hình mối đe doạ "mạng cô lập, không ra Internet". Có thể nâng cấp lên Keystore/Secure Enclave sau nếu cần.

## Chạy

```bash
flutter pub get
flutter run                 # cần thiết bị/emulator cùng mạng LAN với backend
flutter test                # unit test crypto + smoke test
flutter build apk --debug   # đóng gói Android
```

Đảm bảo điện thoại/emulator và máy chủ **cùng mạng LAN**; nhập đúng IP LAN của máy chạy backend (không dùng `localhost`).
