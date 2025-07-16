# config.py

import os
import ast
from pathlib import Path  # این خط اضافه می‌شود
from dotenv import load_dotenv


# --- تنظیمات ربات تلگرام ---
BOT_TOKEN = os.getenv("BOT_TOKEN_ALAMOR")

# کد هوشمند و مقاوم برای خواندن آیدی ادمین‌ها
import re
admin_ids_str = os.getenv("ADMIN_IDS_ALAMOR", "")
try:
    # این کد تمام رشته‌های عددی را از متن استخراج کرده و به لیست اعداد تبدیل می‌کند
    ADMIN_IDS = [int(s) for s in re.findall(r'\d+', admin_ids_str)]
except:
    ADMIN_IDS = []

# کد دیباگ شما... (می‌توانید بعد از حل مشکل آن را پاک کنید)
# ================================= DEBUG =================================
print("--- START DEBUG ---")
print(f"Loaded ADMIN_IDS variable: {ADMIN_IDS}")
if ADMIN_IDS:
    print(f"Type of ADMIN_IDS list: {type(ADMIN_IDS)}")
    print(f"Type of the first element in the list: {type(ADMIN_IDS[0])}")
else:
    print("ADMIN_IDS list is empty or was not loaded correctly!")
print("--- END DEBUG ---")
# =======================================================================
# --- تنظیمات دیتابیس ---
DATABASE_NAME = os.getenv("DATABASE_NAME_ALAMOR", "database/alamor_vpn.db")

# --- تنظیمات رمزنگاری ---
encryption_key_str = os.getenv("ENCRYPTION_KEY_ALAMOR")
if encryption_key_str:
    ENCRYPTION_KEY = encryption_key_str.encode('utf-8')
else:
    # اگر کلید وجود ندارد، یک فایل .env بسازید و کلید را در آن قرار دهید
    # می‌توانید با اجرای فایل code-generate.py یک کلید جدید بسازید
    raise ValueError("ENCRYPTION_KEY_ALAMOR environment variable must be set in .env file!")

# --- تنظیمات تست رایگان ---
FREE_TEST_DURATION_HOURS = int(os.getenv("FREE_TEST_DURATION_HOURS_ALAMOR", 1))
FREE_TEST_VOLUME_GB = float(os.getenv("FREE_TEST_VOLUME_GB_ALAMOR", 0.5))

# --- تنظیمات کانال اجباری ---
REQUIRED_CHANNEL_ID_STR = os.getenv("REQUIRED_CHANNEL_ID_ALAMOR")
REQUIRED_CHANNEL_ID = int(REQUIRED_CHANNEL_ID_STR) if REQUIRED_CHANNEL_ID_STR else None
REQUIRED_CHANNEL_LINK = os.getenv("REQUIRED_CHANNEL_LINK_ALAMOR", "https://t.me/Alamor_Network")


# --- سایر تنظیمات ---
SUPPORT_CHANNEL_LINK = os.getenv("SUPPORT_CHANNEL_LINK_ALAMOR", "https://t.me/YourSupportChannel")
WELCOME_MESSAGE = os.getenv("WELCOME_MESSAGE_ALAMOR", "به ربات Alamor VPN خوش آمدید، {first_name}! 🤖")
MAX_API_RETRIES = int(os.getenv("MAX_API_RETRIES_ALAMOR", 3))

# --- تنظیمات سابسکریپشن (این تنظیمات دیگر در دیتابیس به ازای هر سرور ذخیره می‌شوند) ---
# این مقادیر می‌توانند به عنوان مقدار پیش‌فرض استفاده شوند اما اولویت با دیتابیس است.
# SUBSCRIPTION_BASE_URL = os.getenv("SUBSCRIPTION_BASE_URL_ALAMOR")
# SUBSCRIPTION_PATH_PREFIX = os.getenv("SUBSCRIPTION_PATH_PREFIX_ALAMOR", "sub")