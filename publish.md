# Hướng dẫn đưa app lên Play Store / TestFlight

Tài liệu này tổng hợp các bước cần làm trước khi publish app `ca_attendance`.

## 1. Package name / Bundle ID

Cấu hình hiện tại:

| Nền tảng | Định danh | File |
|---|---|---|
| Android (`applicationId`) | `com.mpcorp.ca_attendance` | `android/app/build.gradle.kts` |
| iOS (`PRODUCT_BUNDLE_IDENTIFIER`) | `com.mpcorp.caAttendance` | `ios/Runner.xcodeproj/project.pbxproj` |

**Cả hai đều hợp lệ về kỹ thuật, có thể publish.** Lưu ý 3 điểm cần chốt **trước lần publish đầu tiên**:

1. **Định danh là VĨNH VIỄN.** Sau khi app đã lên store, `applicationId` và bundle ID **không bao giờ đổi được** (đổi = phải tạo app mới hoàn toàn). Hãy chắc chắn `com.mpcorp.*` là cái muốn giữ mãi.
2. **`com.mpcorp` nên là domain mình sở hữu** (quy ước reverse-DNS). Không bắt buộc, nhưng nếu sau này dùng domain khác thì nên đổi *trước khi* publish.
3. **Hai nền tảng đang khác nhau**: Android dùng `ca_attendance` (gạch dưới), iOS dùng `caAttendance` (camelCase). Lý do: iOS **không cho phép dấu gạch dưới** trong bundle ID. Việc này **không gây lỗi** — mỗi store quản lý riêng.

> **Khuyến nghị:** ship như hiện tại là được. Nếu muốn thống nhất 1 định danh cho cả 2 nền tảng (dễ quản lý Firebase/analytics sau này), đổi Android `applicationId` thành `com.mpcorp.caAttendance` cho khớp iOS — chỉ sửa 1 dòng, vì đang ở giai đoạn debug nên chưa ảnh hưởng gì.

## 2. Đổi tên hiển thị app (tên dưới icon)

Tên này **khác** với package name — đổi lúc nào cũng được, kể cả sau khi publish.

**Android** — sửa `android:label` trong `android/app/src/main/AndroidManifest.xml`:
```xml
android:label="Điểm danh CA"
```

**iOS** — sửa `CFBundleDisplayName` trong `ios/Runner/Info.plist`:
```xml
<key>CFBundleDisplayName</key>
<string>Điểm danh CA</string>
```
(Giữ nguyên `CFBundleName` cũng được; `CFBundleDisplayName` mới là tên hiện trên màn hình.)

> Tên trên **trang Store** (Play Console / App Store Connect) là ô riêng nhập khi tạo listing — không liên quan tới 2 chỗ trên.

## 3. Đổi icon app

Dùng package `flutter_launcher_icons` để sinh tất cả kích thước cho Android + iOS từ 1 ảnh gốc.

**Bước 1 — Chuẩn bị ảnh.** Tạo thư mục `assets/icon/` và đặt:
- `icon.png` — **1024×1024**, vuông, **KHÔNG nền trong suốt** (App Store bắt buộc icon đặc).
- `icon_foreground.png` — 1024×1024 (lớp foreground cho adaptive icon Android); logo nằm trong vùng ~66% giữa, xung quanh để trong suốt.

**Bước 2 — Thêm package:**
```bash
cd d:/Work/ca_attendance
flutter pub add dev:flutter_launcher_icons
```

**Bước 3 — Thêm cấu hình vào cuối `pubspec.yaml`** (ngang cấp với `flutter:`, KHÔNG lồng bên trong):
```yaml
flutter_launcher_icons:
  image_path: "assets/icon/icon.png"
  android: true
  ios: true
  remove_alpha_ios: true          # bỏ alpha cho iOS (tránh bị App Store từ chối)
  min_sdk_android: 23
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "assets/icon/icon_foreground.png"
```

**Bước 4 — Sinh icon:**
```bash
flutter pub get
dart run flutter_launcher_icons
```
Lệnh này ghi đè toàn bộ `mipmap-*` (Android) và `AppIcon.appiconset` (iOS) đang là icon mặc định của Flutter.

> Icon trên **trang Store** vẫn upload thủ công trong console: Play Store cần PNG **512×512**, App Store cần **1024×1024** — dùng chính `icon.png`.

## 4. ⚠️ Release signing — đang CHẶN release lên Play Store

Trong `android/app/build.gradle.kts`, bản release đang ký bằng **debug key**:
```kotlin
release {
    signingConfig = signingConfigs.getByName("debug")  // ← Play Store sẽ từ chối
}
```
Play Console **không nhận** file AAB ký bằng debug key. Cần làm trước khi upload:

1. Tạo keystore release:
   ```bash
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Tạo file `android/key.properties` (KHÔNG commit vào git):
   ```properties
   storePassword=<mật khẩu>
   keyPassword=<mật khẩu>
   keyAlias=upload
   storeFile=<đường dẫn tới upload-keystore.jks>
   ```
3. Trỏ `signingConfig` của bản release vào keystore này trong `build.gradle.kts`.

**iOS / TestFlight:** cần **tài khoản Apple Developer ($99/năm)** và cấu hình signing/provisioning trong Xcode (không phải sửa code).

## 5. Checklist trước khi publish

- [ ] Chốt `applicationId` / bundle ID (vĩnh viễn, không đổi được sau publish)
- [ ] Đổi tên hiển thị (Android `android:label` + iOS `CFBundleDisplayName`)
- [ ] Thay icon app bằng `flutter_launcher_icons`
- [ ] Cấu hình release signing cho Android (keystore + `key.properties`)
- [ ] (iOS) Tài khoản Apple Developer + signing trong Xcode
- [ ] Kiểm tra `version: 1.0.0+1` trong `pubspec.yaml` (tăng `+build` mỗi lần upload)
- [ ] Build thử: `flutter build appbundle --release` (Android) / `flutter build ipa` (iOS)
