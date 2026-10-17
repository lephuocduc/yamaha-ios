# SỔ TAY KỸ THUẬT & LỊCH SỬ PHÁT TRIỂN NCONNECT-IOS
> **Mục đích**: Ghi chép chi tiết toàn bộ kiến trúc, cơ chế giao thức kết nối xe máy Yamaha, phân tích dịch ngược (reverse-engineering), các lỗi thực tế đã gặp và giải pháp chuẩn xác để **tránh lặp lại lỗi** trong quá trình bảo trì và phát triển tiếp theo.

---

## 1. TỔNG QUAN KIẾN TRÚC HỆ THỐNG
Dự án **NConnect-iOS** (tên hiển thị: **MyNMAX**) là giải pháp dẫn đường OpenStreetMap và hiển thị thông tin chuyên dụng cho các dòng xe máy Yamaha trang bị màn hình TFT kỹ thuật số (XMAX 300, NMAX 155, MT-09, R9, v.v.).

### Cơ chế kết nối đa kênh đồng thời (Multi-Channel):
1. **Kênh ExternalAccessory (MFi Garmin NaviLite - `com.garmin.navilite.data`)**:
   - Giao tiếp với cụm màn hình TFT của xe qua giao thức chuẩn Garmin StreetCross (Service UUID: `00007220-0000-1000-8000-00805F9B34FB`).
   - Nhiệm vụ: Stream hình ảnh bản đồ thời gian thực (nén JPEG qua Bluetooth), hiển thị thanh chỉ dẫn rẽ (Turn-by-Turn), cập nhật tên đường dưới footer, nhận và xử lý tín hiệu phím bấm cùm tay lái (+ / -).
2. **Kênh CoreBluetooth (Yamaha CCU GATT - Service `AFA2CDF4...` / `00008911...`)**:
   - Kết nối với bộ điều khiển CCU xe máy Yamaha để lắng nghe trạng thái khoá điện, kết nối và thu thập dữ liệu telemetry phụ trợ.
3. **Kênh Apple Notification Center Service (ANCS) & CallKit**:
   - Quản lý hiển thị thông báo tin nhắn (SMS, iMessage, Zalo, Messenger) từ hệ thống iOS lên cụm đồng hồ xe.
   - Bắt sự kiện cuộc gọi đến theo thời gian thực qua `CXCallObserver` và điều hướng phím bấm cùm tay lái (+ nghe, - từ chối).

---

## 2. CHI TIẾT GIAO THỨC GARMIN STREETCROSS & NAVILITE
Qua quá trình dịch ngược (disassembly/decompilation) file thực thi `classes.dex` của phiên bản Android gốc (gói `o3/c`, `Lm3/r`, `b/k`):

### 2.1 Cấu trúc khung tin NaviLite (Wire Framing)
Mọi gói tin dữ liệu điều khiển gửi lên màn hình xe đều phải tuân thủ nghiêm ngặt định dạng:
```
[ 4 Bytes Magic: "nAl@" (0x6e, 0x41, 0x6c, 0x40) ]
[ 1 Byte Version: 0x01 ]
[ 1 Byte FrameType (ft): 0x06 = FT_PHONE ]
[ 1 Byte ServiceType (svc) ]
[ 4 Bytes Payload Length: Little-Endian ]
[ 1 Byte Payload Data Type (pdt): 0 = VALUE, 1 = POINTER ]
[ 4 Bytes CRC32-MPEG2 Checksum: Tính từ byte Magic đến hết Payload ]
[ N Bytes Payload ]
```

### 2.2 Quy trình bắt tay 3 bước (3-Step Handshake)
* **Bước 1 (Serial Exchange)**: Khi xe kết nối, xe gửi chuỗi Serial máy. Điện thoại phản hồi: `[0x51, 0x21, 0x00, 0x00]`.
* **Bước 2 (Screen Dimension Negotiation)**: Xe gửi lệnh `0x53` hoặc `0x83` kèm kích thước màn hình (ví dụ `480x234` hoặc `400x240`). Điện thoại phản hồi gói `0x54, 0x01` kèm mã phần mềm `006-B4160` (hoặc fallback `006-B3952-10`).
* **Bước 3 (Auth Confirmation)**: Xe xác nhận quyền truyền hình qua mã `82 = 1`. Sau đó điện thoại gửi cấu hình khởi tạo `0x20` để sẵn sàng nhận luồng frame JPEG.

### 2.3 Phân mảnh luồng ảnh JPEG (Chunking)
- Mỗi khung hình JPEG kích thước ~480x234 sau khi vẽ bằng CoreGraphics được nén ở mức chất lượng 0.85 (kích thước ~15KB - 30KB).
- Header khung hình: `[0x05, FrameIdx(4B LE), TotalSize(4B LE)]`.
- Phải cắt nhỏ thành các chunk **<= 500 bytes** để vừa với MTU Bluetooth/MFi và không làm tràn bộ đệm phần cứng của màn hình xe.

---

## 3. SỔ TAY CÁC LỖI ĐÃ GẶP & CÁCH GIẢI QUYẾT TRIỆT ĐỂ (TRÁNH LẶP LẠI)

### 🔴 LỖI 1: Chữ `▲ Road` ở thanh Footer màn hình xe không đổi
* **Triệu chứng**: Dưới đáy màn hình TFT luôn hiện chữ `▲ Road` mặc định, không hiển thị được tên con đường xe đang chạy qua.
* **Nguyên nhân gốc rễ**:
  1. Chữ `▲ Road` là text mặc định nạp sẵn trong ROM xe khi xe chưa nhận được gói tin tên đường hợp lệ từ CCU.
  2. Trong các phiên bản đầu, hàm `updateCurrentRoadNameOnTFT` chỉ được gọi khi đang có lộ trình (`isNavigating && !road.isEmpty`). Khi người dùng chạy xe tự do (không bật chỉ đường tới điểm cụ thể), app không hề phát gói tin tên đường xuống xe.
  3. Code cũ từng gửi xen kẽ các gói Service 1 (Cmd 3) và Service 14. Bộ firmware của màn hình xe khi nhận các gói thừa này sẽ tự động reset chu kỳ chuỗi hiển thị về mặc định (`Road`).
* **Giải pháp chuẩn xác**:
  - Gửi liên tục và định kỳ chuỗi 3 gói tin chuẩn của Garmin (theo hàm `Lm3/r;->l` offset `1858112`):
    1. Service 2: `[0x01, 0x00]` (Init/Mode).
    2. Service 4: `[s4, length, utf8_road_name...]` (Tên đường dạng chuỗi UTF-8).
    3. Service 2: `[0x03, etaMinLow, etaMinHigh, 0x00]` (Thông tin thời gian/ETA).
  - Áp dụng cơ chế fallback: Khi đang chờ định vị hoặc geocoding chưa có tên đường cụ thể, phát tên mặc định ("MyNMAX" hoặc "Yamaha") để xóa ngay chữ `▲ Road` trong ROM xe.
  - Tuyệt đối không gửi chèn Service 1 hoặc Service 14 vào giữa chuỗi phát tên đường này.

---

### 🔴 LỖI 2: Phím `+` / `-` trên ghi-đông không zoom được hoặc chỉ bấm được 1 lần
* **Triệu chứng**: Nhấn phím zoom trên cùm tay lái xe thì màn hình không phóng to / thu nhỏ được, hoặc bấm được 1 lần đầu rồi các lần sau bị đơ.
* **Nguyên nhân gốc rễ**:
  - Khi người dùng bấm phím cùm tay lái, xe gửi mã `51, 53, 57` (phím +) hoặc `52, 54, 58` (phím -).
  - Firmware xe máy Yamaha yêu cầu điện thoại **phải phản hồi ngay lập tức gói tin ACK Service 14**: `NaviLite.frame(6, 14, 1, [0x07, 0x1A, 0x00, 0x00])`. Nếu không có gói ACK này, xe sẽ coi như sự kiện trước đó bị nghẽn và khóa các sự kiện bấm phím tiếp theo.
* **Giải pháp chuẩn xác**:
  - Ngay khi nhận mã `51, 53, 57` hoặc `52, 54, 58`, gọi lệnh `writeEAData(NaviLite.frame(6, 14, 1, [0x07, 0x1A, 0x00, 0x00]))` lập tức để giải phóng khóa phím của xe, sau đó mới dispatch tác vụ zoom trên Main thread.

---

### 🔴 LỖI 3: Đổi giao diện bản đồ (Theme Tile) không có tác dụng
* **Triệu chứng**: Người dùng vào Cài đặt đổi từ `Voyager` sang `Dark Matter` hay `Positron` nhưng bản đồ trên điện thoại và xe vẫn giữ nguyên màu cũ.
* **Nguyên nhân gốc rễ**:
  1. `OSMTileEngine` lưu trữ các file tile đã tải về đĩa trong một thư mục chung `OSMTiles_v4/\(z)_\(x)_\(y).png` mà không phân chia theo style. Khi đổi theme, app vẫn đọc file tile cũ trong bộ nhớ đệm ổ đĩa.
  2. Lớp `MKMapView` trên màn hình iOS chỉ nạp lớp phủ `CustomOSMTileOverlay` một lần lúc khởi tạo view và không tự thay thế khi URL template thay đổi.
* **Giải pháp chuẩn xác**:
  - Phân vùng cache riêng biệt cho từng theme: `cacheDirectory.appendingPathComponent(currentStyleKey)`.
  - Cung cấp hàm `updateStyle(template:styleKey:)` để phát thông báo và dọn bộ nhớ RAM cache.
  - Trong `OSMMapView.updateUIView`, bắt sự kiện thay đổi template để remove lớp overlay cũ và chèn `MKTileOverlay` mới vào `MKMapView`.

---

### 🔴 LỖI 4: Vòng tua máy (RPM) và % nhiên liệu hiển thị `--`
* **Bản chất kỹ thuật**:
  - Phân tích toàn bộ APK gốc chứng minh rằng: **Garmin StreetCross Protocol trên các dòng xe màn hình TFT không bao giờ truyền tín hiệu RPM hay mức xăng qua Bluetooth**.
  - Tín hiệu vòng tua máy và mức xăng trên các dòng xe này được đưa trực tiếp từ ECU bằng dây điện vật lý vào cụm đồng hồ LCD/TFT.
* **Giải pháp chuẩn xác**:
  - Không để dấu `--` gây hiểu lầm là tính năng bị hỏng.
  - Hiển thị nhãn **"Theo xe (LCD)"** kèm chú thích rõ ràng: "Đồng hồ xe hiển thị trực tiếp từ cảm biến phần cứng của ECU".
  - Giữ lại bộ lắng nghe ngầm (packet sniffer) trong `YamahaCCUManager` để tự động hiển thị nếu firmware của dòng xe tương lai có phát gói tin này.

---

### 🔴 LỖI 5: Chỉ đường hay rẽ vào ngõ hẻm nhỏ thay vì đường lớn
* **Triệu chứng**: Thuật toán dẫn đường ép người dùng rẽ vào các ngõ hẻm quanh co, hẹp hòi thay vì đi trên các trục đường lớn.
* **Nguyên nhân gốc rễ**:
  - Để ngăn xe máy đi vào đường cao tốc ô tô ở Việt Nam, cấu hình ban đầu đặt `use_highways: 0.0`. Tuy nhiên, nếu thiếu các trọng số phụ, thuật toán Valhalla sẽ coi các đại lộ nhiều làn xe cũng là dạng đường cấp cao cần né tránh, từ đó chọn các lối tắt ngõ hẻm để thay thế.
* **Giải pháp chuẩn xác**:
  - Cấu hình chuẩn cho xe máy đô thị trong `NavigationEngine.swift`:
    * `use_highways: 0.0`: Tránh tuyệt đối cao tốc cấm xe máy.
    * `use_primary: 0.9`: **Ưu tiên tối đa** các trục đường lớn, đại lộ chính (Nguyễn Văn Linh, Điện Biên Phủ, Võ Văn Kiệt...).
    * `alley_factor: 5.0`: **Phạt rất nặng việc đi vào ngõ hẻm**, kiệt nhỏ.
    * `use_trails: 0.0` & `use_tolls: 0.0`: Tránh lối mòn, đường bộ và trạm thu phí.
    * `top_speed: 65`: Căn chỉnh tốc độ thực tế của xe máy.

---

### 🔴 LỖI 6: Giọng nói Text-To-Speech gây phiền toái, gián đoạn âm thanh
* **Triệu chứng**: Giọng nói đọc chỉ đường tiếng Việt tự động kích hoạt chiếm quyền `AVAudioSession`, ngắt quãng nhạc tai nghe hoặc cuộc gọi đàm thoại của người lái.
* **Giải pháp chuẩn xác**:
  - Đặt `isVoiceGuidanceEnabled: Bool = false` làm mặc định.
  - Vô hiệu hoá hàm `speak(_ text: String)` thành no-op (return ngay), không can thiệp vào `AVAudioSession` để giữ nguyên luồng âm thanh trong tai nghe nón bảo hiểm.

---

### 🔴 LỖI 7: Quản lý thông báo tin nhắn và cuộc gọi đến
* **Cơ chế hoạt động trên iOS**:
  1. **Tin nhắn (SMS / iMessage / Zalo / Messenger)**:
     - Do chính sách bảo mật sandbox của Apple, ứng dụng bên thứ ba không được phép đọc trực tiếp nội dung tin nhắn của ứng dụng khác.
     - Thay vào đó, iOS cung cấp dịch vụ Bluetooth chuẩn **ANCS (Apple Notification Center Service)** ở cấp độ hệ điều hành.
     - **Yêu cầu cài đặt**: Vào Cài đặt iPhone → Bluetooth → chọn tên xe Yamaha → Bật **"Chia sẻ thông báo hệ thống"**. Khi đó iOS sẽ tự động chuyển tiếp toàn bộ thông báo lên màn hình xe.
  2. **Cuộc gọi đến & Điều khiển bằng phím cùm xe**:
     - Tích hợp `CallNotificationManager` sử dụng framework `CallKit` (`CXCallObserver`).
     - Khi có cuộc gọi đến (`!call.hasConnected && !call.isOutgoing`):
       * Kích hoạt `isCallRinging = true`.
       * Vẽ banner cảnh báo cuộc gọi màu đỏ neon nổi bật ở góc trên màn hình TFT xe: `📞 CUỘC GỌI ĐẾN` - `[+] TRẢ LỜI   [-] TỪ CHỐI`.
       * Vẽ banner tương ứng trên giao diện iPhone.
       * Khi người dùng nhấn phím **(+)** trên cùm xe: Thực hiện lệnh trả lời cuộc gọi (`CXAnswerCallAction`).
       * Khi người dùng nhấn phím **(-)** trên cùm xe: Thực hiện lệnh từ chối / ngắt cuộc gọi (`CXEndCallAction`).
       * Khi cuộc gọi kết thúc: Banner tự động biến mất, phím (+) và (-) lập tức quay về chức năng phóng to / thu nhỏ bản đồ.

---

## 4. QUY TRÌNH BIÊN DỊCH VÀ PHÁT HÀNH (CI/CD)
- Dự án sử dụng GitHub Actions workflow (`.github/workflows/build-ios.yml`).
- Mỗi khi có commit mới được push lên nhánh `main`, hệ thống tự động:
  1. Kiểm tra mã nguồn Swift.
  2. Biên dịch dự án bằng lệnh `xcodebuild` (SDK `iphoneos`, cấu hình `Release`).
  3. Đóng gói thư mục `Payload` thành file `NConnect.ipa`.
  4. Xuất file Artifact `NConnect-iOS-IPA` để tải về và cài đặt trực tiếp qua TrollStore / AltStore / Sideloadly / Scarlet.
