# در فایل utils/bot_helpers.py

import telebot
import qrcode
from io import BytesIO
import logging

from utils import messages, helpers

logger = logging.getLogger(__name__)

def send_subscription_info(bot: telebot.TeleBot, user_id: int, sub_link: str):
    """
    اطلاعات اشتراک را با ارسال یک پیام (عکس QR کد با کپشن کامل) ارسال می‌کند.
    """
    bot.send_message(user_id, messages.CONFIG_DELIVERY_HEADER, parse_mode='Markdown')
    
    # --- بخش اصلاح شده ---
    # ساخت کپشن کامل شامل لینک و توضیحات QR کد
    caption_text = messages.CONFIG_DELIVERY_SUB_LINK.format(sub_link=sub_link) + \
                   "\n\n" + messages.QR_CODE_CAPTION
    
    try:
        qr_image = qrcode.make(sub_link)
        bio = BytesIO()
        bio.name = 'qrcode.jpeg'
        qr_image.save(bio, 'JPEG')
        bio.seek(0)

        # ارسال QR کد به همراه لینک و توضیحات در کپشن
        bot.send_photo(user_id, bio, caption=caption_text, parse_mode='Markdown')
        
    except Exception as e:
        # اگر ساخت QR کد با خطا مواجه شد، فقط لینک را به صورت متنی ارسال می‌کند
        logger.error(f"Failed to generate or send QR code: {e}")
        bot.send_message(user_id, caption_text, parse_mode='Markdown')