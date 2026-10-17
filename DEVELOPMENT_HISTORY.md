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
* **Nguyên nhân gốc rễ (Phân tích dịch ngược DEX chuyên sâu)**:
  1. Chữ `▲ Road` là chuỗi placeholder nạp sẵn trong ROM xe khi xe chưa nhận được lệnh cập nhật chuỗi tên đường hợp lệ từ CCU.
  2. Dịch ngược chi tiết các hàm trong `classes.dex` của Android:
     - `Lo3/c;->f` (cOff `1980160`): Nhận tên đường (String) → chuẩn hoá bỏ dấu tiếng Việt → chuyển thành mảng bytes UTF-8 ASCII → gọi `Lo3/c;->b(roadBytes, 3, 1)`. **Đây chính là Service 3 (PDT 1) chuyên trách gửi chuỗi tên đường trực tiếp cho màn hình xe!**
     - `Lo3/c;->j` (cOff `1980568`): Nhận chuỗi văn bản → đóng gói `[0x07, 0x1A, len, 0x00] + bytes` → gọi `Lo3/c;->b(payload, 14, 1)`. **Đây là Service 14 (PDT 1) với lệnh con 0x1A để hiển thị văn bản lên thanh trạng thái đồng hồ xe!**
     - `Lm3/r;->d` (cOff `1854372`): Khi chuẩn bị chuyển thông tin rẽ, gọi tuần tự:
       `Lo3/c;->j("300 m")` (Service 14) → `Lo3/c;->g()` (Service 2 `[1, 0]`) → `Lo3/c;->f(road)` (Service 3) → `Lo3/c;->j("")` (Service 14).
     - `Lm3/r;->l` (cOff `1858112`): Gửi Service 4 (PDT 1: `[icon, distLE(4B), unitLen, roadLen, unitBytes, roadBytes]`) và Service 2 (PDT 1: ETA).
  3. **Lỗi trong code cũ**:
     - Trong chuỗi bắt tay `setup` ban đầu, code cũ gửi `(3, 1, [])` với mảng byte rỗng (`roadBytes = []`)! Do nhận chuỗi rỗng nên xe giữ nguyên chữ `Road` mặc định trong ROM.
     - Trong hàm `updateCurrentRoadNameOnTFT`, code cũ chỉ gửi Service 2 và Service 4, **hoàn toàn bỏ quên Service 3 và Service 14**!
* **Giải pháp chuẩn xác triệt để**:
  - Trong `runNaviLiteHandshake`: Luôn nạp tên đường khởi tạo hợp lệ (mặc định `"YAMAHA"`), gửi `(3, 1, roadBytes)` thực tế và `(14, 1, roadPayload)` trong setup burst.
  - Trong `updateCurrentRoadNameOnTFT`: Gửi đầy đủ tổ hợp 5 gói tin chuẩn:
    1. Service 2 (PDT 0): `[1, 0]` (Bật chế độ dẫn đường Active Navigation).
    2. Service 3 (PDT 1): `roadBytes` (Gửi trực tiếp chuỗi tên đường dạng UTF-8 ASCII theo chuẩn `Lo3/c;->f`).
    3. Service 4 (PDT 1): `s4` (Gửi mũi tên maneuver, khoảng cách float LE, đơn vị, tên đường theo chuẩn `Lm3/r;->l`).
    4. Service 14 (PDT 1): `[0x07, 0x1A, len, 0x00] + roadBytes` (Lệnh Sub 0x1A hiển thị tên đường theo chuẩn `Lo3/c;->j`).
    5. Service 2 (PDT 1): `arrivePayload` (Thông tin giờ đến ETA trong ngày).

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

### 🔴 LỖI 7: Quản lý thông báo ứng dụng (Zalo, Messenger, SMS...) và cuộc gọi đến
* **Cơ chế hoạt động trên iOS**:
  1. **Thông báo ứng dụng (SMS / iMessage / Zalo / Messenger / Telegram...)**:
     - Do chính sách bảo mật sandbox của Apple, ứng dụng bên thứ ba không thể nghe trộm trực tiếp thông báo push của các ứng dụng khác.
     - **Giải pháp đa tầng thông minh**:
       * **Kênh ANCS (Apple Notification Center Service)**: Hỗ trợ chuyển tiếp tự động thông báo của iOS sang cụm đồng hồ xe khi bật "Chia sẻ thông báo hệ thống" trong cài đặt Bluetooth.
       * **Kênh URL Scheme (`mynmax://notify?app=Zalo&sender=Nam&message=Alo`)**: Cho phép người dùng tạo Phím tắt iOS (Shortcuts Automation) để tự động bắn thông báo tức thì lên màn hình xe khi nhận tin nhắn.
       * **Quản lý thời gian hiển thị (`AppNotificationManager`)**: Cho phép tuỳ chỉnh số giây hiển thị trên màn hình xe (mặc định 7 giây, cấu hình từ 3 - 30 giây trong Cài đặt). Sau thời gian này, thông báo tự động ẩn và trả lại bản đồ dẫn đường.
  2. **Cuộc gọi đến & Điều khiển bằng phím cùm xe**:
     - Tích hợp `CallNotificationManager` sử dụng `CallKit` (`CXCallObserver`) kết hợp trích xuất Caller ID qua `TelephonyUtilities` (`TUCallCenter`).
     - **Giao diện hiển thị chuẩn theo yêu cầu**:
       * Nền banner: Màu **Xanh lá cây (Emerald Green)** nổi bật, tương phản cao.
       * Nội dung: Hiển thị nổi bật **Tên người gọi hoặc Số điện thoại** (không cần chú thích phím rườm rà).
       * Thời gian hiển thị: **Hiển thị liên tục** suốt quá trình đổ chuông và đàm thoại cho tới khi cuộc gọi kết thúc.
       * Khi người dùng nhấn phím **(+)** trên cùm xe: Nhận / Trả lời cuộc gọi (`CXAnswerCallAction`).
       * Khi người dùng nhấn phím **(-)** trên cùm xe: Từ chối / Kết thúc cuộc gọi (`CXEndCallAction`).
       * Khi cuộc gọi kết thúc: Banner tự động biến mất, phím (+) và (-) lập tức quay về chức năng phóng to / thu nhỏ bản đồ.

---

### 🔴 TÍNH NĂNG 8: Gợi ý các tuyến đường thay thế (Alternative Routes) & Chạm vào bản đồ để chuyển tuyến (Google Maps Style)
* **Yêu cầu**: Tương tự như Google Maps, khi tìm đường và dẫn đường cần hiển thị các tuyến đường gợi ý thay thế. Nếu thấy tối ưu hơn, người dùng có thể nhấp trực tiếp vào đường vẽ gợi ý trên bản đồ (hoặc thẻ tóm tắt) để đổi tuyến và đi theo lộ trình đó.
* **Kiến trúc giải pháp chuẩn xác**:
  1. **Routing Engines (Valhalla & OSRM) đa lộ trình**:
     - Valhalla: Bổ sung tham số `"alternates": 2`. Khi phản hồi, `json["trip"]` chứa tuyến chính và `json["alternates"]` chứa danh sách các `{ "trip": ... }` thay thế.
     - OSRM: Bổ sung tham số `&alternatives=true` để lấy mảng `json["routes"]`.
     - Tự động thống kê các con đường chính đã đi qua (`roadDistances`) để đặt tên tuyến thân thiện tự nhiên như Google Maps: *"Qua Đ. Pasteur"*, *"Qua Đ. Hai Bà Trưng"*, *"Qua Đ. Nam Kỳ Khởi Nghĩa"*.
     - Tự động tính chênh lệch thời gian so với tuyến nhanh nhất: *"Nhanh nhất"*, *"+3 phút"*, *"+7 phút"*.
  2. **Hiển thị trực quan trên bản đồ iPhone (`MKMapView`) & Màn hình xe Yamaha TFT**:
     - Tuyến đang chọn (Active Route): Vẽ bằng màu **Xanh Yamaha Racing Neon Cyan (`#00B0FF`)** siêu sáng, độ dày 11.0pt, nằm trên cùng.
     - Các tuyến gợi ý thay thế (Alternative Routes): Vẽ bằng màu **Xám khói tương phản (`#78909C`)** độ dày 7.5pt, nằm bên dưới.
     - Cả trên màn hình TFT xe máy cũng đồng bộ hiển thị các tuyến xám này để người lái dễ quan sát các ngã rẽ khả dĩ.
  3. **Cử chỉ tương tác chạm trực tiếp vào đường vẽ (Polyline Touch Detection)**:
     - Tích hợp `UITapGestureRecognizer` trên `MKMapView`.
     - Thuật toán tính khoảng cách vuông góc từ điểm chạm ngón tay (`CGPoint`) đến từng đoạn thẳng (`Segment`) của các tuyến đường thay thế (`pointToSegmentDistance`).
     - Ngưỡng dung sai chạm: 36 points (~1cm trên màn hình iPhone), cực kỳ nhạy và dễ bấm chính xác ngay cả khi gắn điện thoại trên giá đỡ xe máy.
     - Khi phát hiện chạm trúng tuyến thay thế: Kích hoạt rung phản hồi xúc giác (`UIImpactFeedbackGenerator(style: .medium)`), gọi `navEngine.selectRoute(selectedRoute)` để chuyển đổi tức thì.
  4. **Thẻ chọn lộ trình (Route Carousel) & Nút chuyển nhanh khi đang chạy xe**:
     - Ở màn hình xem trước: Carousel vuốt ngang hiển thị các thẻ tuyến đường với thông số thời gian, chênh lệch phút, độ dài cự ly và tên đường chính.
     - Khi đang lái xe dẫn đường (`isNavigating`): Hiển thị thanh chuyển nhanh (`alternativeRoutesNavigationPill`) nổi ở phía dưới để người lái có thể bấm nút hoặc nhấp thẳng vào đường vẽ trên bản đồ.

---

### 🔴 TÍNH NĂNG 9: Dời thông tin thời gian đến (ETA) xuống Footer & Mở rộng Header toàn chiều ngang TFT
* **Yêu cầu người dùng**:
  - Footer màn hình xe máy đã hiển thị thành công tên con đường hiện tại (`▲ PHU THO HOA`).
  - Dời toàn bộ thông tin giờ đến dự kiến (ETA - ví dụ `17:44` và `41 phút`) từ hộp góc phải của Header xuống tích hợp trực tiếp vào thanh Footer.
  - Mục đích: Giải phóng hoàn toàn chiều ngang dải đen Header trên màn hình TFT (~408pt) để tên đường tiếp theo hiển thị trọn vẹn, không bị cắt bớt hoặc hiện dấu ba chấm (`...`) khi tên đường dài.
* **Kiến trúc giải pháp chuẩn xác**:
  1. **Tích hợp ETA vào thanh Footer của xe (`updateCurrentRoadNameOnTFT`)**:
     - Định dạng Footer khi đang dẫn đường: `[TÊN ĐƯỜNG HIỆN TẠI] - [GIỜ ĐẾN] ([SỐ PHÚT CÒN LẠI]P)`.
       * Ví dụ thực tế: `▲ PHU THO HOA - 17:44 (41P)` hoặc `▲ 58 DO DUC DUC - 18:25 (1H15P)`.
     - Toàn bộ chuỗi được chuẩn hoá qua hàm `cleanVietnameseForGarmin`, chuyển sang chữ in hoa chuẩn ASCII (32-126) mà vi điều khiển màn hình xe Yamaha/Garmin hỗ trợ hoàn hảo.
     - Khi chạy xe tự do không có lộ trình: Footer tự động quay về hiển thị tên đường hiện tại không kèm ETA (ví dụ `▲ PHU THO HOA`).
     - Khi kết thúc chuyến đi (`stopNavigationOnTFT`): Reset sạch chuỗi để không lưu vết ETA cũ.
  2. **Giải phóng và tối ưu Header dẫn đường trên TFT (`drawTopNavigationBanner`)**:
     - Gỡ bỏ hộp chữ nhật ETA (`etaBoxRect`) ở góc trên bên phải.
     - Tăng chiều rộng vùng hiển thị văn bản `availableTextWidth` từ 302pt lên **408pt** (`size.width (480) - textStartX (62) - 10`).
     - Tự động co giãn cỡ chữ thông minh cho tên đường tiếp theo:
       * Tên đường dài > 28 ký tự: Cỡ chữ 24pt Bold.
       * Tên đường dài > 20 ký tự: Cỡ chữ 26pt Bold.
       * Tên đường thông thường: Cỡ chữ 28pt Bold.
     - Khoảng cách rẽ (`36pt Heavy Neon Green`) và tên đường (`Bold White`) luôn được căn giữa theo chiều cao dải đen (62pt), hiển thị cực kỳ sang trọng, rõ ràng và chống chói tuyệt đối dưới trời nắng gắt.

---

## 4. QUY TRÌNH BIÊN DỊCH VÀ PHÁT HÀNH (CI/CD)
- Dự án sử dụng GitHub Actions workflow (`.github/workflows/build-ios.yml`).
- Mỗi khi có commit mới được push lên nhánh `main`, hệ thống tự động:
  1. Kiểm tra mã nguồn Swift.
  2. Biên dịch dự án bằng lệnh `xcodebuild` (SDK `iphoneos`, cấu hình `Release`).
  3. Đóng gói thư mục `Payload` thành file `NConnect.ipa`.
  4. Xuất file Artifact `NConnect-iOS-IPA` để tải về và cài đặt trực tiếp qua TrollStore / AltStore / Sideloadly / Scarlet.

