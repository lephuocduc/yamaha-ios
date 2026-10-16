# Hướng dẫn Build & Cài đặt NConnect lên iPhone (Không cần máy Mac)

Tài liệu này hướng dẫn bạn cách biên dịch dự án **NConnect iOS** thành file **`NConnect.ipa`** thông qua máy chủ macOS miễn phí của GitHub Actions, sau đó cài trực tiếp lên iPhone từ máy tính Windows của bạn.

---

## BƯỚC 1: Đẩy mã nguồn lên GitHub của bạn

1. Truy cập [github.com](https://github.com/) và tạo một Repository mới (đặt tên ví dụ: `NConnect-iOS`). Chọn chế độ **Private** hoặc **Public**.
2. Mở cửa sổ **PowerShell** hoặc **Command Prompt** tại thư mục `E:\REA` và chạy lần lượt các lệnh:

```bash
git init
git add .
git commit -m "Khoi tao du an NConnect iOS"
git branch -M main
git remote add origin https://github.com/TÊN_GITHUB_CỦA_BẠN/NConnect-iOS.git
git push -u origin main
```

*(Nếu bạn dùng ứng dụng **GitHub Desktop**, chỉ cần chọn `Add Existing Repository` $\rightarrow$ chọn thư mục `E:\REA` $\rightarrow$ bấm `Publish Repository`).*

---

## BƯỚC 2: Tải file `NConnect.ipa` từ GitHub Actions

1. Sau khi đẩy code lên, bạn vào trang GitHub Repository của bạn trên trình duyệt.
2. Bấm vào tab **Actions** ở thanh menu trên cùng.
3. Bạn sẽ thấy tiến trình **"Build NConnect iOS (.IPA)"** đang tự động chạy trên máy Mac của GitHub.
4. Chờ khoảng 1 – 2 phút đến khi xuất hiện dấu tích xanh **`✓` (Success)**.
5. Bấm vào lượt chạy đó, cuộn xuống phần **Artifacts** ở dưới cùng:
   * Bạn sẽ thấy file **`NConnect-iOS-IPA`**.
   * Bấm tải về và giải nén, bạn sẽ nhận được file **`NConnect.ipa`**.

---

## BƯỚC 3: Cài đặt file .IPA vào iPhone bằng Windows (Qua Sideloadly)

1. Tải và cài đặt phần mềm **[Sideloadly](https://sideloadly.io/)** (phiên bản Windows 64-bit).
2. Mở Sideloadly lên.
3. Cắm iPhone vào máy tính Windows bằng cáp sạc USB (nếu iPhone hỏi *"Tin cậy máy tính này?"*, chọn **Tin cậy** và nhập mật khẩu màn hình).
4. Trên giao diện Sideloadly:
   * Kéo thả file **`NConnect.ipa`** vừa tải ở Bước 2 vào ô IPA.
   * Nhập địa chỉ **Apple ID** của bạn vào ô *Apple ID* (đây là tài khoản dùng để ký chứng chỉ nhà phát triển cá nhân miễn phí của Apple).
   * Bấm nút **Start**.
5. Nhập mật khẩu Apple ID khi Sideloadly yêu cầu (và mã xác thực 2 bước 6 số gửi về màn hình iPhone).
6. Đợi khoảng 30 giây đến khi thanh tiến trình báo **Done!**. Ứng dụng **NConnect** sẽ xuất hiện trên màn hình chính của iPhone!

---

## BƯỚC 4: Cấp quyền chạy ứng dụng trên iPhone

Lần đầu mở app, iOS sẽ thông báo *"Nhà phát triển doanh nghiệp chưa được tin cậy"*. Bạn chỉ cần:
1. Vào **Cài đặt (Settings)** trên iPhone.
2. Chọn **Cài đặt chung (General)** $\rightarrow$ **Quản lý VPN & Thiết bị (VPN & Device Management)**.
3. Bấm vào tài khoản Apple ID của bạn $\rightarrow$ Chọn **Tin cậy (Trust)**.
4. Mở app **NConnect**, cấp quyền **Bluetooth** và **Vị trí (Luôn cho phép)** để app có thể tự động kết nối với xe Yamaha khi bật khóa.

Chúc bạn có những chuyến đi an toàn cùng màn hình TFT của xe Yamaha!
