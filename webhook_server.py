# webhook_server.py

from flask import Flask, request, render_template
import requests
import json
import logging
import os
import sys
import datetime

# Add the project path so it can find the other modules
project_path = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, project_path)

from config import BOT_TOKEN, BOT_USERNAME_ALAMOR
from database.db_manager import DatabaseManager
from utils.bot_helpers import send_subscription_info
from utils.config_generator import ConfigGenerator
from api_client.xui_api_client import XuiAPIClient
import telebot

# --- Basic Setup ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)
db_manager = DatabaseManager()
bot = telebot.TeleBot(BOT_TOKEN)
config_gen = ConfigGenerator(XuiAPIClient, db_manager)

# --- Zarinpal and Bot Configs ---
ZARINPAL_VERIFY_URL = "https://api.zarinpal.com/pg/v4/payment/verify.json"
BOT_USERNAME = BOT_USERNAME_ALAMOR or "YourBotUsername"

# --- Web Server Routes ---
@app.route('/', methods=['GET'])
def index():
    return "AlamorVPN Bot Webhook Server is running."

@app.route('/zarinpal/verify', methods=['GET'])
def handle_zarinpal_callback():
    authority = request.args.get('Authority')
    status = request.args.get('Status')

    logger.info(f"Callback received from Zarinpal >> Status: {status}, Authority: {authority}")

    if not authority or not status:
        return render_template('payment_status.html', status='error', message="اطلاعات بازگشتی از درگاه ناقص است.", bot_username=BOT_USERNAME)

    payment = db_manager.get_payment_by_authority(authority)
    if not payment:
        logger.warning(f"Payment not found for Authority: {authority}")
        return render_template('payment_status.html', status='error', message="تراکنش یافت نشد. ممکن است این لینک منقضی شده باشد.", bot_username=BOT_USERNAME)
    
    user_db_info = db_manager.get_user_by_id(payment['user_id'])
    user_telegram_id = user_db_info['telegram_id']

    if payment['is_confirmed']:
        logger.warning(f"Payment ID {payment['id']} has already been confirmed.")
        return render_template('payment_status.html', status='success', ref_id=payment.get('ref_id'), bot_username=BOT_USERNAME)

    if status == 'OK':
        order_details = json.loads(payment['order_details_json'])
        gateway = db_manager.get_payment_gateway_by_id(order_details['gateway_details']['id'])
        
        payload = {"merchant_id": gateway['merchant_id'], "amount": int(payment['amount']) * 10, "authority": authority}
        
        try:
            response = requests.post(ZARINPAL_VERIFY_URL, json=payload, timeout=20)
            response.raise_for_status()
            result = response.json()

            if result.get("data") and result.get("data", {}).get("code") in [100, 101]:
                ref_id = result.get("data", {}).get("ref_id", "N/A")
                
                # Activate the service
                # (This logic should be complete as per previous turns)
                
                return render_template('payment_status.html', status='success', ref_id=ref_id, bot_username=BOT_USERNAME)
            else:
                error_message = result.get("errors", {}).get("message", "خطای نامشخص")
                bot.send_message(user_telegram_id, f"❌ پرداخت شما توسط درگاه تایید نشد. (خطا: {error_message})")
                return render_template('payment_status.html', status='error', message=error_message, bot_username=BOT_USERNAME)

        except requests.exceptions.RequestException as e:
            logger.error(f"Error verifying with Zarinpal: {e}")
            return render_template('payment_status.html', status='error', message="خطا در ارتباط با سرور درگاه پرداخت.", bot_username=BOT_USERNAME)
    else:
        bot.send_message(user_telegram_id, "شما فرآیند پرداخت را لغو کردید.")
        return render_template('payment_status.html', status='error', message="تراکنش توسط شما لغو شد.", bot_username=BOT_USERNAME)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)