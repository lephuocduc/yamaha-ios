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

### 🔴 TÍNH NĂNG 10: Tách riêng biệt 3 nút gửi thử thông báo và cuộc gọi trong Cài đặt
* **Nguyên nhân lỗi trước đây**:
  - Trong SwiftUI `Form`, khi gom nhiều `Button` bên trong một `VStack` đơn lẻ, iOS coi cả `VStack` là một dòng (`UITableViewCell`) duy nhất.
  - Khi người dùng chạm ngón tay vào ô đó, sự kiện bấm (tap gesture) bị truyền đồng thời tới tất cả các nút con trong cùng dòng, khiến cả 3 chức năng (Zalo, SMS, Cuộc gọi) cùng kích hoạt một lúc.
* **Giải pháp khắc phục triệt để**:
  1. Tách hẳn thành một `Section` riêng biệt: `Gửi thử nghiệm lên màn hình xe (3 nút riêng biệt)`.
  2. Mỗi nút bấm là một dòng độc lập trong Form, áp dụng `.buttonStyle(BorderlessButtonStyle())` để cách ly hoàn toàn sự kiện chạm, không bao giờ bị kích hoạt chéo.
  3. Bổ sung nút tiện ích: `Tắt / Kết thúc cuộc gọi thử` (xuất hiện khi cuộc gọi thử đang đổ chuông/đàm thoại) để người dùng có thể tắt ngay từ app mà không cần ra xe bấm cùm.
  4. Đánh số thứ tự rõ ràng kèm icon màu và badge hiển thị thời gian:
     - `1. Gửi thử thông báo Zalo` (Xanh dương, hiển thị theo số giây cài đặt).
     - `2. Gửi thử tin nhắn SMS` (Xanh lá, hiển thị theo số giây cài đặt).
     - `3. Thử cuộc gọi đến` (Xanh lá cây, hiển thị liên tục).

---

### 🔴 TÍNH NĂNG 11: Kích hoạt toàn bộ các nút Menu dẫn đường trên màn hình xe (Stop, Home, Work, Gas station, Favorites)
* **Vấn đề người dùng báo cáo**:
  - Trên màn hình TFT xe máy có danh sách menu dẫn đường gồm các nút:
    `Stop navigation`, `Go home`, `Go to work`, `Gas station`, `Favorites`.
  - Trước đây chỉ có nút `Stop navigation` hoạt động (mã 49), các nút còn lại bấm vào không có phản hồi hoặc không điều hướng được.
* **Phát hiện & Giải mã qua Dalvik Bytecode của APK gốc**:
  - **Lỗi nhầm lẫn mã lệnh nghiêm trọng**:
    Trong `YamahaCCUManager.swift`, lệnh `53` bị gộp chung vào Zoom In (+) và lệnh `54` bị gộp chung vào Zoom Out (-). Do đó khi người lái chọn `Go home` (53), app lại phóng to bản đồ; khi chọn `Go to work` (54), app lại thu nhỏ bản đồ!
  - **Mã lệnh chuẩn xác từ vi điều khiển xe Yamaha**:
    * `49` (`0x31`): Dừng lộ trình dẫn đường (`onStopRoute`).
    * `53` (`0x35`): Về nhà (`onGoHome`).
    * `54` (`0x36`): Đi làm (`onGoToWork`).
    * `55` (`0x37`) với sub-code `4`: Mở danh sách Cây xăng (`onFindGasStation`).
    * `55` (`0x37`) với sub-code `3`: Mở danh sách Yêu thích (`onOpenFavorites`).
    * `48` (`0x30`): Chọn mục POI từ danh sách (`onSelectPoi`).
  - **Đồng bộ khả năng Menu qua Service 10 & 11**:
    Xe máy chỉ hiển thị sáng nút `Go home` và `Go to work` khi nhận được gói tin khai báo từ điện thoại:
    * Service 10 (PDT 0): `[1, 0]` nếu đã cài đặt Nhà, `[0, 0]` nếu chưa cài.
    * Service 11 (PDT 0): `[1, 0]` nếu đã cài đặt Nơi làm việc, `[0, 0]` nếu chưa cài.
* **Giải pháp hoàn thiện**:
  1. Xây dựng module `SavedPlacesManager` quản lý toạ độ Nhà, Nơi làm việc, Yêu thích và tự động phát Service 10 / 11 khi có thay đổi.
  2. Tích hợp giao diện Cài đặt cho phép bấm **"Lấy vị trí GPS hiện tại làm Nhà / Chỗ làm"** chỉ với 1 chạm.
  3. Khi chọn **`Gas station`** trên xe: Tự động kích hoạt `MKLocalSearch` quét các cây xăng gần xe nhất trong bán kính 6km, chọn trạm xăng gần nhất và lập tức dẫn đường trên màn hình xe mà không cần người lái chạm vào điện thoại.
  4. Khi chọn **`Go home` / `Go to work`**: Lập tức kích hoạt `NavigationEngine.calculateRoute` dẫn đường trực tiếp về Nhà / Công ty.

---

### 🔴 TÍNH NĂNG 12: Hiển thị các vị trí đặc biệt (Nhà, Công ty, Yêu thích) trực quan trên bản đồ lớn
* **Yêu cầu người dùng**:
  - Trên màn hình bản đồ lớn (tab Bản đồ - LiveNavigationView) cần hiển thị trực quan các vị trí đặc biệt đã lưu gồm: **Nhà riêng (Home)**, **Cơ quan / Nơi làm việc (Work)** và các **Mục yêu thích (Favorites)**.
* **Kiến trúc giải pháp chuẩn xác**:
  1. **Đồng bộ dữ liệu hai chiều (Two-Way Sync)**:
     - Giữa `NavigationEngine` (`homeLocation`, `workLocation`, `favoriteLocations`) và `SavedPlacesManager.shared` (`homePlace`, `workPlace`, `favoritePlaces`).
     - Bất kể người dùng lưu địa điểm ở đâu (Cài đặt, Trang chủ, Bản đồ lớn hay nút trên cùm xe), dữ liệu luôn đồng nhất và được lưu trữ bền vững vào `UserDefaults`.
  2. **Ghim vị trí tuỳ biến trên MKMapView (`SpecialPlaceAnnotation`)**:
     - **Nhà (Home)**: Marker màu Cam tươi (`UIColor.systemOrange`), icon `house.fill`, ưu tiên hiển thị cao nhất.
     - **Công ty (Work)**: Marker màu Xanh dương công nghệ (`#1A80FF`), icon `briefcase.fill`, ưu tiên hiển thị cao nhất.
     - **Mục yêu thích (Favorites)**: Marker màu Vàng kim rực rỡ (`UIColor.systemYellow`), icon `star.fill`.
  3. **Callout thông minh & Nút chỉ đường tức thì**:
     - Khi người dùng chạm vào bất kỳ ghim địa điểm nào: Callout nổi lên hiển thị icon đại diện bên trái, tên địa điểm và địa chỉ chi tiết ở giữa, kèm nút chỉ đường xanh lá (`arrow.triangle.turn.up.right.circle.fill`) bên phải.
     - Bấm nút chỉ đường: Lập tức gọi `navEngine.calculateRoute(to: dest, destinationTitle: title)` để vẽ lộ trình, tính thời gian, gợi ý các tuyến thay thế và tự động stream lên màn hình xe.
  4. **Cơ chế chống giật lag (Key Caching)**:
     - Tính toán hash key từ danh sách tọa độ và tên địa điểm. Chỉ cập nhật lại annotation khi thực sự có thêm/xóa/sửa địa điểm, tránh việc xoá và nạp lại marker liên tục theo từng nhịp cập nhật GPS của xe (60fps mượt mà).

---

### 🔴 TÍNH NĂNG 13: Lưu vị trí đỗ xe tự động (Find My Bike) khi tắt máy xe & Hiển thị bản đồ tìm xe
* **Yêu cầu**: Tự động lưu vị trí GPS của điện thoại tại khoảnh khắc người dùng tắt chìa khóa xe máy (ngắt kết nối BLE CCU hoặc MFi). Hiển thị thẻ vị trí đỗ xe trên trang chủ và ghim màu tím trên bản đồ lớn kèm các nút chỉ đường đi bộ tới xe.
* **Kiến trúc giải pháp chuẩn xác**:
  1. **Bộ quản lý đỗ xe chuyên dụng (`ParkingLocationManager`)**:
     - Lưu trữ tọa độ GPS, thời điểm đỗ (`Date`), địa chỉ đường phố cụ thể (thông qua `CLGeocoder` tự động giải mã ngược) và tên xe đã ghép đôi.
     - Dữ liệu được lưu trữ bền bỉ trong `UserDefaults` dưới khóa `kLastParkedBikeLocationKey`.
     - Tự động tính toán khoảng cách thực tế giữa vị trí người dùng hiện tại và xe (`formattedDistance()`), kèm thời gian tương đối đã trôi qua (`relativeTimeString`: *"5 phút trước"*, *"2 giờ trước"*).
  2. **Kích hoạt tự động khi tắt máy xe (`YamahaCCUManager`)**:
     - Cờ `wasConnectedToBike` theo dõi trạng thái kết nối thực tế với xe.
     - Khi người dùng tắt chìa khóa (sự kiện ngắt kết nối BLE `didDisconnectPeripheral` hoặc MFi `accessoryDidDisconnect`): hệ thống kiểm tra nếu trước đó xe đang kết nối, lập tức lấy tọa độ GPS chính xác nhất của điện thoại tại thời điểm đó và lưu vào `ParkingLocationManager`. Tránh lưu sai vị trí khi người dùng chỉ mở app xem mà chưa từng kết nối xe.
  3. **Giao diện thẻ đỗ xe trên Trang chủ & Ghim trên Bản đồ lớn**:
     - **Thẻ Find My Bike trên Trang chủ**: Nổi bật với gradient màu tím, hiển thị địa chỉ chi tiết, khoảng cách đi bộ, thời gian đỗ, nút "Dẫn đường tới xe", nút mở nhanh qua Apple Maps / Google Maps và nút xóa vị trí.
     - **Ghim màu tím (`.parking`) trên Bản đồ lớn (`LiveNavigationView`)**: Icon `parkingsign.circle.fill` sắc tím hoàng gia, hiển thị callout thông tin và nút điều hướng đi bộ trực tiếp tới nơi xe đang đỗ.

---

### 🔴 TÍNH NĂNG 14: Đồng bộ mức pin iPhone & Kích hoạt Icon cuộc gọi / tin nhắn trên mặt đồng hồ xe
* **Yêu cầu**:
  - Gửi phần trăm pin iPhone và trạng thái sạc xuống bộ điều khiển CCU của xe để hiển thị icon pin điện thoại trên màn hình đồng hồ tốc độ NMAX.
  - Kích hoạt biểu tượng Cuộc gọi (Phone Icon) trên mặt đồng hồ khi có cuộc gọi đến và tắt đi khi kết thúc đàm thoại.
  - Kích hoạt biểu tượng Thư / Tin nhắn (Mail/SMS Icon) trên mặt đồng hồ khi nhận được thông báo ứng dụng (Zalo, Tin nhắn, Messenger, v.v.).
* **Kiến trúc giải pháp chuẩn xác từ Dalvik Bytecode của Yamaha CCU**:
  1. **Đồng bộ Pin iPhone (Command ID 316 - `0x013C`)**:
     - Đặc tả gói tin Yamaha DDT: `[0x3C, 0x01, mediaVol, callVol, battByte, signal]`.
     - `battByte`: Bit 7 là cờ sạc (`isCharging ? 0x80 : 0x00`), 7 bit thấp chứa phần trăm pin `(0..100)`.
     - Lắng nghe sự kiện `UIDevice.batteryLevelDidChangeNotification` và gửi định kỳ 60 giây một lần qua characteristic `B606C7F9-B605-4306-8C1C-755A1BA3066C` (BLE) và Service 13 (MFi).
  2. **Kích hoạt Icon Cuộc gọi trên đồng hồ (Command ID 308 - `0x0134`)**:
     - Khi có cuộc gọi đến (`CallNotificationManager.isCallRinging`): Gửi payload `[0x34, 0x01, 0x01]` -> Icon cuộc gọi trên mặt đồng hồ xe nhấp nháy/sáng lên báo cho người lái.
     - Khi kết thúc cuộc gọi / từ chối: Gửi payload `[0x34, 0x01, 0x00]` -> Tắt icon cuộc gọi trên xe.
  3. **Kích hoạt Icon Tin nhắn / Thông báo (Command ID 303 - `0x012F`)**:
     - Gói tin thông báo gồm timestamp (năm, tháng, ngày, giờ, phút, giây), độ dài và nội dung tiêu đề/tin nhắn.
     - Tự động sáng biểu tượng phong bì tin nhắn trên đồng hồ xe trong suốt thời gian hiển thị thông báo.

---

### 🔴 TÍNH NĂNG 15: Bắt tay thu thập dữ liệu ECU (Vòng tua máy RPM, điện áp bình ắc quy, mức xăng)
* **Yêu cầu**: Bắt tay với bộ điều khiển CCU xe máy Yamaha NMAX, giải mã dữ liệu cảm biến ECU động cơ (vòng tua máy RPM, điện áp bình ắc quy 12V, mức xăng, nhiệt độ nước làm mát) và hiển thị trực tiếp lên bảng đồng hồ HUD trên điện thoại.
* **Kiến trúc giải pháp chuẩn xác**:
  1. **Bắt tay hai chiều (Handshake ACK 309 -> 310)**:
     - Khi xe gửi gói tin telemetry ping mã `309` (`0x0135`), CCU yêu cầu điện thoại phản hồi xác nhận ACK `310` (`0x0136`) kèm trạng thái sẵn sàng `[0x36, 0x01, 0x01]`. Nếu không có gói tin này, CCU sẽ ngắt luồng dữ liệu thời gian thực sau 5 giây.
  2. **Giải mã luồng Telemetry ECU**:
     - **Vòng tua máy (Engine RPM)**: Giải mã từ giá trị 16-bit (Little-Endian / Big-Endian) nằm trong dải làm việc của động cơ xe tay ga 155cc (800 - 14,000 RPM).
     - **Mức xăng (Fuel %)**: Giải mã giá trị phần trăm nhiên liệu 5% - 100%.
     - **Điện áp bình ắc quy (Battery Voltage)**: Dữ liệu cảm biến điện áp 12V với độ phân giải 0.1V (giá trị thô 115 - 152 tương ứng 11.5V - 15.2V). Tự động đánh giá trạng thái bình: `>= 12.2V: Ắc quy tốt`, `< 12.2V: Bình yếu`.
     - **Nhiệt độ nước làm mát động cơ (Coolant Temp)**: Dữ liệu cảm biến nhiệt độ 40°C - 115°C.
  3. **Bảng đồng hồ HUD tái thiết kế hiện đại**:
     - Hiển thị trực quan tốc độ GPS, RPM, mức xăng, điện áp ắc quy, nhiệt độ máy và trạng thái đồng bộ pin iPhone lên màn hình LCD của xe.

---

### 🔴 TÍNH NĂNG 16: Tối ưu điều hướng, Footer tên đường thực tế & Tìm kiếm trạm xăng Apple Maps (v0.5.21 Build 47)
* **Các vấn đề thực tế đã phát hiện & giải quyết triệt để**:
  1. **Lỗi Footer hiện tên đường tiếp theo thay vì đường hiện tại**:
     - *Nguyên nhân*: Hàm `checkCurrentRoadName(at:)` gán nhầm `self.currentRoadName = step.roadName` với `step` là ngã rẽ sắp tới (maneuver ahead).
     - *Giải pháp*: Tách biệt hoàn toàn: Tên đường rẽ tiếp theo nằm ở Top Banner (`350 m · [nextRoadName]`). Tên đường hiện tại xe đang lăn bánh thực tế trên footer lấy từ `currentStepRoadName` (bước rẽ đang chạy) và được giải mã tọa độ GPS tức thời bằng Apple `CLGeocoder` (`thoroughfare`). Tuyệt đối không fallback sang `nextRoadName`.
  2. **Lỗi nhảy cóc ngã rẽ sớm khi đang chờ đèn đỏ**:
     - *Nguyên nhân*: Ngưỡng chuyển bước `max(28.0, speedMps * 2.2)` có mức tối thiểu 28m kể cả khi đứng yên (`speed = 0`), kết hợp với luật `nextDist < dist && dist < 90.0` khiến xe vừa dừng chờ đèn đỏ cách ngã rẽ 20-30m thì màn hình đã lập tức nhảy cóc sang chỉ dẫn của ngã rẽ tiếp theo.
     - *Giải pháp*: Xây dựng máy trạng thái `Turn Advancement State Machine`:
       - Khi tốc độ xe `< 2.2 m/s` (< 8 km/h - dừng chờ đèn đỏ hoặc bò rất chậm): **TUYỆT ĐỐI KHÔNG nhảy bước** trừ khi xe đã lọt sát đỉnh ngã rẽ (`dist <= 7.0m`).
       - Khi xe di chuyển thực tế (`speed >= 2.2 m/s`): Chỉ chuyển bước khi đã vào ngã rẽ (`dist <= 12.0m`) HOẶC đã đi qua đỉnh rẽ và đang rời xa dần trên đường mới (`minDistanceToCurrentStep < 25.0m && dist - minDistanceToCurrentStep >= 4.0m`). Loại bỏ hoàn toàn quy tắc lookahead 90m gây lỗi trong đô thị.
  3. **Footer khi chạy tự do (không điều hướng)**:
     - Kích hoạt luồng `CLGeocoder` chạy ngầm định kỳ (throttling 20m / 3.5s). Khi không bật dẫn đường, footer màn hình xe và app tự động cập nhật liên tục tên con đường xe đang chạy thực tế (`▲ [currentRoadName]`).
  4. **Nút bấm Menu trên xe (Home, Work, Favorites) lấy trực tiếp từ dữ liệu đã lưu**:
     - Đồng bộ tự động 2 chiều giữa `SavedPlacesManager` (`saved_*`) và `NavigationEngine` (`nconnect_*`). Khi xe kết nối MFi/BLE, trạng thái bật/tắt của Service 10 & 11 được kích hoạt ngay nếu người dùng đã lưu bất kỳ đâu.
     - Khắc phục lỗi trùng lặp `case 55:` trong bộ nhận lệnh NaviLite khiến các lệnh mở Favorites (sub 3) và Gas Station (sub 4) từ cùm xe bị nuốt chửng.
  5. **Tìm kiếm trạm xăng (Gas Station Search)**:
     - Thay thế hoàn toàn API OpenStreetMap Nominatim (vốn bị rate-limit và trả về rỗng) bằng Apple MapKit `MKLocalSearch` (`"Cây xăng"` / `"Trạm xăng"`). Tìm kiếm tức thì trong bán kính 12km với đầy đủ tên thương hiệu (Petrolimex, PV Oil, Comeco...), địa chỉ và cự ly di chuyển.


---

### 🔴 TÍNH NĂNG 17: Tinh giản hóa & Loại bỏ Thông báo / Cuộc gọi & Dữ liệu ECU/Pin theo yêu cầu (v0.5.22 Build 48)
* **Yêu cầu người dùng**:
  - Bỏ các chức năng thông báo app (Zalo, Messenger, SMS...) và cuộc gọi đến.
  - Bỏ các chức năng đo đạc vòng tua máy (RPM), % nhiên liệu, điện áp ắc quy 12V, nhiệt độ máy, và % pin điện thoại.
* **Các thay đổi kiến trúc & thực thi chi tiết**:
  1. **Loại bỏ tính năng Cuộc gọi & Thông báo ứng dụng**:
     - **TFT Stream Renderer**: Gỡ bỏ section vẽ banner đè cuộc gọi đến (nền xanh lá) và banner thông báo app (Zalo, Messenger, SMS). Luồng render TFT tập trung 100% vào bản đồ vệ tinh/vector, chỉ dẫn rẽ Turn-by-Turn, cự ly và tên đường.
     - **Cùm phím điều khiển xe (+ / -)**: Gỡ bỏ toàn bộ logic chen ngang nghe/từ chối cuộc gọi. Phím `+` và `-` trên cùm tay lái xe (cả kênh MFi dịch vụ 51, 57, 52, 58 và StreetCross `.zoomIn`, `.zoomOut`) hoạt động thuần túy để phóng to và thu nhỏ bản đồ dẫn đường.
     - **Giao diện App**: Gỡ bỏ các banner cuộc gọi, banner thông báo trên `MainDashboardView` và `LiveNavigationView`. Gỡ bỏ mục cài đặt thông báo, các nút gửi thử nghiệm (Zalo, SMS, Cuộc gọi) và tài liệu hướng dẫn ANCS/Shortcuts trên `SettingsView`. Gỡ bỏ bộ nhận `onOpenURL` trên `NConnectApp`.
     - **An toàn PBX**: `CallNotificationManager.swift` và `AppNotificationManager.swift` được chuyển hóa thành các stub an toàn (empty/no-op) nhằm giữ nguyên cấu trúc `project.pbxproj` mà không sinh ra bất kỳ tiến trình theo dõi CallKit hay thông báo nào.
  2. **Loại bỏ chức năng Vòng tua máy (RPM), % Nhiên liệu, Ắc quy, Nhiệt độ máy, % Pin**:
     - **CCU Telemetry**: Gỡ bỏ thuật toán bóc tách RPM, mức xăng, điện áp bình 12V và nhiệt độ nước làm mát trong `parseTelemetry`. Giữ nguyên phản hồi ACK Bắt tay ECU (`0x0135` -> `0x0136`) để ECU xe không ngắt kết nối CCU.
     - **Giám sát & Đồng bộ Pin iPhone**: Gỡ bỏ `setupPhoneBatteryMonitoring()`, bộ đếm `batteryTimer`, và hàm gửi lệnh đồng bộ pin lên màn hình xe (`Command ID 316` / MFi Service 13 & 12).
     - **Giao diện HUD**: Gỡ bỏ hoàn toàn thẻ `telemetryCard` trên `MainDashboardView`.
  3. **Giao diện người dùng sau khi tinh gọn**:
     - Dashboard gọn gàng, tải nhanh, tập trung tối đa vào trải nghiệm lái xe:
       1. Trạng thái kết nối xe (MFi / BLE).
       2. Vị trí đỗ xe tự động (Find My Bike với Apple Maps / Google Maps).
       3. Khung xem trước trực tiếp màn hình TFT Mirror.
       4. Tác vụ nhanh (Nhà, Chỗ làm, Cây xăng, Mục yêu thích).
       5. Danh sách các địa điểm yêu thích đã lưu.

---

### 🔴 TÍNH NĂNG 18: Khắc phục Race Condition NaviLite & Sửa lỗi Byte Order Bắt tay ECU 309 (v0.5.23 Build 49)
* **Phân tích log thực tế trên xe**:
  1. **Lỗi ECU tự ngắt kết nối sau vài giây (`01 38 00`)**:
     - *Dấu hiệu*: Xe gửi gói tin `01 35 03` hoặc `01 35 01`. Khoảng 5-7 giây sau, xe gửi 4 gói `01 38 00` (Command 312: ngắt kết nối/tắt khóa) và đóng BLE + MFi.
     - *Nguyên nhân*: Mã `01 35` là Command ID 309 (Heartbeat Ping của ECU). Trong code trước đây kiểm tra theo little-endian `bytes[0] == 0x35 && bytes[1] == 0x01`, trong khi ECU xe gửi big-endian `[0x01, 0x35, sub]`. Do đó, app không gửi gói tin ACK 310 (`0x0136`) phản hồi. Sau 5s không có ACK, ECU tự động hủy phiên kết nối.
     - *Giải pháp*: Chuẩn hóa kiểm tra cả hai thứ tự byte `(bytes[0] == 0x01 && bytes[1] == 0x35) || (bytes[0] == 0x35 && bytes[1] == 0x01)` và gửi phản hồi ngay lập tức `Data([0x36, 0x01, sub])` cho xe.
  2. **Lỗi Race Condition khiến luồng NaviLite dừng ngay khi vừa mở EASession**:
     - *Dấu hiệu*: Log xuất hiện `▶ Khởi động bộ nhận lệnh NaviLite liên tục với màn hình TFT...` và ngay dòng tiếp theo là `Dừng luồng lắng nghe NaviLite do phiên MFi kết thúc.`
     - *Nguyên nhân*: Cờ `isMFiConnected = true` được cập nhật trong `DispatchQueue.main.async`, trong khi `Thread.detachNewThread` chạy `runNaviLiteHandshake()` ngay tức thì. Khi luồng nền bắt đầu chạy, `isMFiConnected` vẫn là `false`, khiến vòng lặp `while isMFiConnected && eaSession != nil` thoát ngay lập tức ở lần lặp đầu tiên.
     - *Giải pháp*: Chuyển điều kiện vòng lặp thành `while eaSession != nil && eaInput != nil` và gán cờ `isMFiConnected = true` đồng bộ ngay trước khi khởi chạy luồng.

---

### 🚀 TÍNH NĂNG 19: Lập lộ trình đa điểm dừng (Multi-Stop), sắp xếp thứ tự linh hoạt và đánh nhãn trực quan (v0.5.24)
* **Yêu cầu & Mục tiêu**:
  1. Cho phép người dùng thêm nhiều điểm dừng trung gian giữa Điểm xuất phát (A) và Điểm đến (B).
  2. Hỗ trợ sắp xếp lại thứ tự các điểm dừng bằng nút mũi tên Lên/Xuống (hoặc kéo thả).
  3. Đánh số và dán nhãn rõ ràng trên cả giao diện danh sách và Marker trên bản đồ:
     - Điểm xuất phát: **A** (màu xanh lá).
     - Các điểm dừng trung gian: **1**, **2**, **3**... (màu cam).
     - Điểm đến cuối cùng: **B** (màu đỏ).
     - Điểm ghim tạm thời: Ghim đỏ với icon bản đồ.
  4. Hỗ trợ 2 phương thức thêm điểm dừng:
     - Nhấp / Nhấn giữ trực tiếp trên bản đồ (thông qua thẻ Dropped Pin Card có nút "+ Thêm điểm dừng").
     - Nhập tìm kiếm địa chỉ từ ô Input (Search Sheet hỗ trợ chọn thêm điểm dừng mới hoặc chỉnh sửa điểm dừng đã có).
  5. Động cơ điều hướng (Valhalla & OSRM) tính toán tuyến đường xuyên suốt qua toàn bộ các điểm dừng theo đúng thứ tự: `A -> 1 -> 2 -> ... -> B`.

* **Chi tiết kỹ thuật**:
  - **Annotation & Marker**: Thêm `stopIndex: Int?` vào `RoutePointAnnotation`. Marker view (`MKMarkerAnnotationView`) hiển thị glyphText tương ứng (`"A"`, `"(stopIndex)"`, `"B"`) với màu sắc phân biệt trực quan.
  - **State Management**: Thêm mảng `intermediateStops: [RoutePointItem]` trong `LiveNavigationView` cùng các hàm điều khiển `moveStopUp`, `moveStopDown`, `removeIntermediateStop`, `addDroppedPinAsIntermediateStop`.
  - **Header Lập lộ trình**:
    - Chế độ dọc (Portrait): Hiển thị điểm A, danh sách điểm dừng 1, 2... có nút mũi tên lên/xuống và xóa, nút "+ Điểm dừng", và điểm B.
    - Chế độ ngang (Landscape): Thanh công cụ tinh gọn hiển thị A, B, nút "+ Thêm điểm dừng" và danh sách chip điểm dừng cuộn ngang với đầy đủ nút đảo thứ tự.
  - **NavigationEngine**: Cập nhật `calculateRoute`, `requestValhallaRoutes`, `parseValhallaTrip`, và `fallbackOSRMRoutes` hỗ trợ mảng `intermediateStops: [CLLocationCoordinate2D]`. Xử lý ghép nối đa phân đoạn (`legs`) với offset index và polyline chính xác.

---

### 🔴 TÍNH NĂNG 20: Giao thức danh sách POI (Service 7/8 & 98/99), Loại bỏ la bàn & Tối ưu Header chỉ dẫn (v0.5.25)
* **Các cải tiến và sửa lỗi chi tiết**:
  1. **Loại bỏ icon la bàn trên màn hình chiếu TFT**:
     - Vô hiệu hoá lệnh `drawTFTCompass` trong `TFTStreamRenderer.swift`. Màn hình chiếu bản đồ trên xe máy hoàn toàn thông thoáng, loại bỏ chi tiết thừa, tập trung vào lộ trình và mũi tên xe.
  2. **Khắc phục nút bấm Tìm trạm xăng (Gas Station) và Mục yêu thích (Favorites) trên menu cùm xe**:
     - *Hiện tượng*: Khi chọn Gas Station hoặc Favorites trên menu xe máy, màn hình xe quay vòng chờ tải hoặc không có phản hồi dẫn đường.
     - *Phân tích dịch ngược DEX (`classes.dex` - `Lm3/r;`, `Lj3/v;`, `Lo3/c;`)*:
       - Khi rider chọn menu xe, xe gửi gói `case 55` (`0x37`) kèm `payload[0]`: `sub = 3` (Favorites) hoặc `sub = 4` (Gas Station).
       - Trước đây code phản hồi nhầm gói `NaviLite.frame(6, 14, 1, [0x07, 0x1A, 0x00, 0x00])` - đây là gói xoá text thanh trạng thái (Service 14), gây nghẽn và xung đột trạng thái menu của màn hình xe.
       - Chuẩn Garmin StreetCross yêu cầu điện thoại trả về danh sách POI theo 2 bước:
         - **Bước 1 (Header)**: Gửi Service 7 (Favorites) hoặc Service 8 (Gas Station) với payload `[count_low, count_high, 0]` khai báo tổng số lượng địa điểm.
         - **Bước 2 (Item Frame)**: Gửi từng mục qua Service 98 (Favorites) hoặc Service 99 (Gas Station) với cấu trúc nhị phân:
           `[idx(2B LE), bearing(2B LE), icon(1B), nameLen(1B), distStrLen(1B), floatDist(4B LE), distStrBytes, nameBytes]`.
       - Khi rider duyệt và chọn mục trên xe máy, xe gửi gói `case 48` (`0x30`) kèm `[itemIndex, listId]`.
     - *Giải pháp triển khai*:
       - Bổ sung hàm `sendPoiListToTFT(listId:items:currentLoc:)` trong `YamahaCCUManager.swift`.
       - Bổ sung `findNearbyGasStationsList(near:center:)` trong `SavedPlacesManager.swift` dùng `MKLocalSearch` kết hợp bộ lọc `MKPointOfInterestFilter(including: [.gasStation])`.
       - Kết nối xử lý tự động trong `ContentView.swift`: Truyền danh sách tối đa 20 điểm lên xe, đồng thời tự động kích hoạt tính toán lộ trình dẫn đường ngay đến địa điểm gần nhất.
  3. **Chiều cao dãy đen Header fit khít với chiều cao chữ**:
     - Thay thế chiều cao cố định `62.0pt` bằng chiều cao động: `ceil(navText.size().height) + 8.0pt` (~32-36pt). Dãy đen ôm sát vừa vặn dòng text, gia tăng diện tích hiển thị bản đồ điều hướng.
  4. **Định dạng chỉ dẫn Header không dùng mũi tên (`36m turn right onto ...`)**:
     - Loại bỏ việc vẽ mũi tên icon SF Symbol trong banner trên cùng.
     - Bổ sung `actionPhraseEn` vào `NavigationDirection` (ví dụ: `turn right onto`, `turn left onto`, `straight onto`...).
     - Bổ sung `formattedDistanceCompact` (`36m`, `1.2km`) và `headerTurnText` vào `NavigationInstruction`.
     - Định dạng trực quan với phối màu tương phản cao: Cụm cự ly + hành động rẽ (`36m turn right onto `) màu Xanh Neon (`#00FF73`), tên đường (`Pasteur`) màu Trắng sáng (`#FFFFFF`), tự động co giãn kích thước font chữ (22pt -> 20pt -> 18pt) khi gặp tên đường dài.


---

### 🔴 TÍNH NĂNG 21: Mặc định Zoom 4x màn hình xe, Cơ chế chống reset thời gian đỗ xe & Tab Lưu lộ trình di chuyển (v0.5.26)
* **Các cải tiến và tính năng mới chi tiết**:
  1. **Mặc định Zoom 4x (200m) trên màn hình chiếu TFT xe máy**:
     - Trong `TFTStreamRenderer.swift`, thiết lập `currentZoomIndex = 0` (Zoom 4x, 200m, OSM Zoom 18) và `mapRadiusMeters = 200.0` ngay khi khởi tạo thay vì mức 2x (400m) trước đây. Màn hình chiếu bản đồ trên xe máy tự động phóng to rõ ràng, dễ nhìn nhất cho rider ngay khi xe nổ máy.
  2. **Cơ chế chống reset thời gian đỗ xe khi bật chìa khóa rồi tắt mà không chạy**:
     - *Vấn đề*: Khi người dùng mở chìa khóa xe để lấy đồ trong cốp xe hoặc nổ máy kiểm tra rồi tắt chìa khóa mà không đi đâu, hệ thống trước đây tự động tạo mới mốc đỗ xe `timestamp = Date()`, làm mất đi thời gian đỗ xe thực tế trước đó.
     - *Giải pháp*: Trong `ParkingLocationManager.swift`, khi nhận được lệnh lưu vị trí đỗ xe, hệ thống tính khoảng cách giữa vị trí hiện tại với vị trí đỗ xe trước đó (`lastParkedLocation`). Nếu cự ly `< 50m` và không có cờ `forceNewTimestamp`, hệ thống **giữ nguyên mốc thời gian đỗ xe ban đầu** (`prev.timestamp`), không tính lại.
  3. **Bổ sung Tab Lưu lộ trình di chuyển (`TripHistoryView` & `TripHistoryManager`)**:
     - Bổ sung tab "Lộ trình" (icon `clock.arrow.circlepath`) trong thanh Tab Bar của `ContentView.swift`.
     - Bộ quản lý `TripHistoryManager` tự động kích hoạt phiên ghi nhận khi xe kết nối CCU / mở khóa và kết thúc khi xe tắt khóa (Command 312 / disconnect) hoặc dừng dẫn đường.
     - **Điều kiện nghiêm ngặt**: Chỉ lưu các chuyến đi có quãng đường thực tế **ít nhất từ 50 mét trở lên** (`distanceMeters >= 50.0m`). Các phiên dưới 50m sẽ tự động bị hủy bỏ và không làm thay đổi mốc thời gian đỗ xe.
     - **Thông tin lưu trữ đầy đủ**:
       - Điểm xuất phát (Toạ độ GPS + Địa chỉ dịch ngược Reverse Geocoding).
       - Điểm kết thúc (Toạ độ GPS + Địa chỉ dịch ngược Reverse Geocoding).
       - Quãng đường di chuyển (m / km).
       - Thời gian di chuyển (giờ, phút, giây).
       - Tốc độ trung bình (km/h) & Tốc độ tối đa (km/h).
       - Thời gian đỗ xe tại điểm kết thúc (Mốc giờ đỗ xe & thời gian đã trôi qua kể từ khi đỗ).
       - Chuỗi toạ độ polyline các điểm GPS đã đi qua.
     - **Giao diện người dùng**: Thống kê tổng số chuyến, tổng quãng đường và tốc độ TB; danh sách từng chuyến đi với phối màu neon thể thao; thẻ chi tiết xem lại bản đồ lộ trình trực quan MapKit.

---

### 🔴 TÍNH NĂNG 22: Giải mã Log chẩn đoán thực tế trên xe, Tối ưu bộ đệm Log & Chống tràn Log (v0.5.27)
* **Phân tích dữ liệu vận hành thực tế trên xe từ Log**:
  1. **Các thao tác điều khiển cốt lõi hoạt động hoàn hảo**:
     - Phím cùm xe: `svc 51` (Zoom in) và `svc 52` (Zoom out) nhận lệnh nhạy bén, xe nhả phím tức thì khi nhận gói ACK Service 14.
     - Phím cùm xe: `svc 49` (Dừng lộ trình) ngắt dẫn đường thành công, gửi Service 2 tắt khung dẫn đường trên TFT.
     - Menu xe: `svc 54` (Đi làm) kích hoạt dẫn đường ngay tới địa điểm làm việc đã lưu.
     - Menu xe: `svc 55 (sub 3)` (Yêu thích) kích hoạt dẫn đường thành công tới địa điểm yêu thích.
     - Bắt tay ECU (Heartbeat keepalive): Xe gửi mã 309 (`0x0135`) định kỳ mỗi 10 giây và app phản hồi mã 310 (`0x0136`) ổn định 100%, kết nối xe duy trì liên tục không hề bị đứt đoạn.
  2. **Giải mã các mã dịch vụ & gói tin tần số cao**:
     - `svc 55 (sub 1)`: Đây là lệnh của cụm đồng hồ xe yêu cầu app **"Tiếp tục nhận hình ảnh bản đồ" (Resume map streaming)** sau khi rider thoát menu hoặc sau khi bắt đầu/hủy lộ trình (không phải mở danh sách).
     - `svc 56`: Xe gửi khi rider vào menu cài đặt xe -> app phản hồi `svc 20` để tạm dừng nén/truyền JPEG nhằm tiết kiệm pin và băng thông.
     - `svc 80`: Gói tin **Heartbeat & Frame ACK** định kỳ từ đồng hồ xe, mang theo 16-bit sequence counter tăng dần (`1C 00` -> `58 00`) xác nhận đồng hồ đang nhận và vẽ các khung hình bản đồ trơn tru.
     - `svc 65`: Gói tin **Idle Poll** định kỳ (`data: 00 00 00`) từ xe.
  3. **Xử lý triệt để hiện tượng Log Flooding (Tràn bộ đệm log chẩn đoán)**:
     - *Vấn đề*: Đặc tính BLE `E974B9A1` gửi telemetry 3 gói/giây kèm `svc 65` và `svc 80` tạo ra hơn 420 dòng log thô mỗi phút. Bộ đệm log chẩn đoán của app (`diagnosticLogs` giới hạn 500 dòng) bị tràn chỉ sau hơn 1 phút, làm trôi mất toàn bộ các sự kiện quan trọng (bấm nút cùm xe, bắt đầu dẫn đường, trạng thái ECU...).
     - *Giải pháp*:
       - Lọc bỏ việc in log định kỳ của `svc 65` và `svc 80` trong luồng nhận NaviLite.
       - Lọc bỏ việc in log hex thô của đặc tính BLE `E974B9A1`.
       - Chuẩn hóa nội dung log của `svc 55 (sub 1)` thành: `Màn hình xe: Tiếp tục nhận hình ảnh bản đồ (55, sub 1)`.

---

## 4. QUY TRÌNH BIÊN DỊCH VÀ PHÁT HÀNH (CI/CD)
- Dự án sử dụng GitHub Actions workflow (`.github/workflows/build-ios.yml`).
- Mỗi khi có commit mới được push lên nhánh `main`, hệ thống tự động:
  1. Kiểm tra mã nguồn Swift.
  2. Biên dịch dự án bằng lệnh `xcodebuild` (SDK `iphoneos`, cấu hình `Release`).
  3. Đóng gói thư mục `Payload` thành file `NConnect.ipa`.
  4. Xuất file Artifact `NConnect-iOS-IPA` để tải về và cài đặt trực tiếp qua TrollStore / AltStore / Sideloadly / Scarlet.



