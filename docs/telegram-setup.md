# Telegram Setup

Use this guide to create a Telegram bot, find the chat ID MST should send to, and test delivery before enabling automated reports.

## 1. Create a Telegram Bot

1. Open Telegram.
2. Search for `BotFather`.
3. Start a chat with BotFather and send:

   ```text
   /newbot
   ```

4. Follow the prompts to choose a display name for the bot.
5. Choose a bot username. Telegram bot usernames must end in `bot`.
6. Copy the bot token BotFather returns.

The token format looks like:

```text
123456789:ABCdefGhIJKlmNoPQRsTUVwxyz
```

## 2. Get the Chat ID

MST needs the numeric Telegram chat ID for the destination chat.

### Personal Chat

1. Open a direct chat with the newly created bot.
2. Send any message to the bot.
3. Open this URL in a browser, replacing `<TOKEN>` with the real bot token:

   ```text
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```

4. In the JSON response, find the numeric `id` field under `chat`.

### Group Chat

1. Add the bot to the Telegram group.
2. Send any message in the group.
3. Open this URL in a browser, replacing `<TOKEN>` with the real bot token:

   ```text
   https://api.telegram.org/bot<TOKEN>/getUpdates
   ```

4. In the JSON response, find the `id` field under `chat`. Group chat IDs are usually negative numbers.

`getUpdates` only returns recent messages. Send a message to the bot or group first, then reload the `getUpdates` URL.

## 3. Configure MST

Edit `/etc/mst/config.conf` and set:

```bash
MST_TELEGRAM_ENABLED="true"
MST_TELEGRAM_BOT_TOKEN="<the bot token>"
MST_TELEGRAM_CHAT_ID="<the chat id>"
```

## 4. Test Delivery

Run:

```bash
sudo mst report --style telegram | sudo mst telegram
```

Confirm that a Telegram message arrives.

Common failure modes:

- Invalid bot token: Telegram API returns `401`.
- Empty `getUpdates` response: the bot has not received a recent message yet. Send a message to the bot or group, then reload the URL.
- Wrong chat ID format: personal chat IDs are numeric; group chat IDs are often negative.

## 5. Keep the Token Private

`MST_TELEGRAM_BOT_TOKEN` is sensitive. Keep `/etc/mst/config.conf` at its existing restrictive file permissions and do not loosen them.

## 6. Automate Daily Reports

After manual Telegram delivery works, use `scripts/mst-daily-report.sh` with the example schedule in `templates/mst.cron.example` to set up the daily automated report.
