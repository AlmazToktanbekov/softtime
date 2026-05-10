import requests
from datetime import datetime

BASE_URL = 'http://localhost:8000/api/v1'

def run_test():
    print("Starting Daily Report integration test...")
    
    # 1. Login
    try:
        res = requests.post(f"{BASE_URL}/auth/login", json={
            "username": "admin",
            "password": "admin123"
        })
        res.raise_for_status()
        token = res.json().get('access_token')
        print("✅ Login successful")
    except Exception as e:
        print(f"❌ Login failed: {e}")
        return

    headers = {"Authorization": f"Bearer {token}"}

    # 2. Get QR token
    try:
        res = requests.get(f"{BASE_URL}/qr/current", headers=headers)
        res.raise_for_status()
        qr_token = res.json().get('token')
        print(f"✅ Got QR token: {qr_token[:10]}...")
    except Exception as e:
        print(f"❌ Failed to get QR token: {e}")
        return

    # 3. Check In
    try:
        res_in = requests.post(f"{BASE_URL}/attendance/check-in", headers=headers, json={
            "qr_token": qr_token,
            "device_info": "Test Script"
        })
        if res_in.status_code == 400 and "уже отмечался" in res_in.text.lower():
            print("⚠️ Already checked in.")
        else:
            res_in.raise_for_status()
            print("✅ Check In successful")
    except Exception as e:
        print(f"❌ Check In failed: {e} | Detail: {res_in.text}")
        return

    # 4. Check Out with Daily Report
    report_text = "I completed the API testing and fixed the bugs."
    try:
        res_out = requests.post(f"{BASE_URL}/attendance/check-out", headers=headers, json={
            "qr_token": qr_token,
            "device_info": "Test Script",
            "daily_report": report_text
        })
        res_out.raise_for_status()
        print("✅ Check Out with daily report successful")
    except Exception as e:
        print(f"❌ Failed to check out: {e} | Detail: {res_out.text}")
        return

    # 5. Fetch Daily Reports
    try:
        today = datetime.now().strftime("%Y-%m-%d")
        res_rep = requests.get(f"{BASE_URL}/attendance/daily-reports?report_date={today}", headers=headers)
        res_rep.raise_for_status()
        reports = res_rep.json()
        print(f"✅ Fetched daily reports. Count: {len(reports)}")
        for r in reports:
            print(f"  - {r.get('employee_name')}: {r.get('daily_report')}")
    except Exception as e:
        print(f"❌ Failed to fetch daily reports: {e} | Detail: {res_rep.text}")
        return

if __name__ == '__main__':
    run_test()
