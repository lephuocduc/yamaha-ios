import urllib.request
import json
import time
import sys

REPO = "lephuocduc/yamaha-ios"
API_URL = f"https://api.github.com/repos/{REPO}/actions/runs"

def get_latest_run():
    req = urllib.request.Request(API_URL, headers={"User-Agent": "MyNMAX-Watcher/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            runs = data.get("workflow_runs", [])
            return runs[0] if runs else None
    except Exception as e:
        print(f"Lỗi kết nối GitHub API: {e}")
        return None

def get_artifacts(run_id):
    url = f"https://api.github.com/repos/{REPO}/actions/runs/{run_id}/artifacts"
    req = urllib.request.Request(url, headers={"User-Agent": "MyNMAX-Watcher/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("artifacts", [])
    except Exception:
        return []

def main():
    sys.stdout.reconfigure(encoding="utf-8")
    print(f"🔍 Đang kiểm tra trạng thái build của {REPO}...")
    run = get_latest_run()
    if not run:
        print("Không tìm thấy workflow run nào.")
        return

    commit_msg = run.get("head_commit", {}).get("message", "").split("\n")[0]
    run_id = run["id"]
    status = run["status"]
    conclusion = run["conclusion"]
    html_url = run["html_url"]

    print(f"📦 Commit: {commit_msg}")
    print(f"🔗 Chi tiết: {html_url}")

    if status == "completed":
        icon = "✅ THÀNH CÔNG" if conclusion == "success" else "❌ THẤT BẠI"
        print(f"📊 Trạng thái: {icon} ({conclusion})")
        artifacts = get_artifacts(run_id)
        if artifacts:
            print("\n📥 File IPA sẵn sàng tải về:")
            for a in artifacts:
                size_mb = a["size_in_bytes"] / (1024 * 1024)
                print(f"   • {a['name']} ({size_mb:.2f} MB)")
                print(f"     Link trang tải: {html_url}")
        return

    # Nếu đang chạy, theo dõi trực tiếp
    print(f"⏳ Bản build đang chạy ({status})... Tự động cập nhật mỗi 10 giây:")
    while True:
        time.sleep(10)
        run = get_latest_run()
        if not run:
            continue
        status = run["status"]
        conclusion = run["conclusion"]
        if status == "completed":
            print("\n" + "=" * 50)
            if conclusion == "success":
                print("🎉 CHÚC MỪNG: Bản build đã hoàn tất THÀNH CÔNG!")
                artifacts = get_artifacts(run_id)
                for a in artifacts:
                    size_mb = a["size_in_bytes"] / (1024 * 1024)
                    print(f"📥 Artifact: {a['name']} ({size_mb:.2f} MB)")
                print(f"🔗 Mở tải IPA tại: {html_url}")
            else:
                print(f"⚠️ Bản build thất bại ({conclusion}). Xem chi tiết lỗi tại: {html_url}")
            break
        else:
            print(".", end="", flush=True)

if __name__ == "__main__":
    main()
