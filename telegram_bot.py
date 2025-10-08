#!/usr/bin/env python3
"""
Telegram Bot with Authentication
All information-returning commands require login
"""

import os
import logging
from typing import Dict, Set
from telegram import Update, BotCommand
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    filters,
    ContextTypes,
    ConversationHandler
)

# Enable logging
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)
logger = logging.getLogger(__name__)

# Conversation states
USERNAME, PASSWORD = range(2)

# Store authenticated users (in production, use a database)
authenticated_users: Set[int] = set()

# Valid credentials (in production, use secure database with hashed passwords)
VALID_CREDENTIALS = {
    "admin": "admin123",
    "user1": "pass123",
    "demo": "demo123"
}


class AuthenticatedBot:
    """Telegram bot with authentication requirement"""

    def __init__(self):
        self.authenticated_users = authenticated_users

    async def start(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /start command"""
        user_id = update.effective_user.id

        if user_id in self.authenticated_users:
            await update.message.reply_text(
                "🔓 You're already logged in!\n\n"
                "Available commands:\n"
                "/info - Get system information\n"
                "/stats - View statistics\n"
                "/users - List users\n"
                "/data - Get data summary\n"
                "/logout - Logout from bot"
            )
        else:
            await update.message.reply_text(
                "👋 Welcome to the Authenticated Bot!\n\n"
                "🔒 Please login to access commands.\n"
                "Use /login to authenticate."
            )

    async def login_start(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
        """Start login conversation"""
        user_id = update.effective_user.id

        if user_id in self.authenticated_users:
            await update.message.reply_text("You're already logged in! Use /logout to logout first.")
            return ConversationHandler.END

        await update.message.reply_text(
            "🔐 Login Required\n\n"
            "Please enter your username:\n"
            "(Send /cancel to abort)"
        )
        return USERNAME

    async def receive_username(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
        """Receive username and ask for password"""
        username = update.message.text.strip()
        context.user_data['username'] = username

        await update.message.reply_text(
            f"Username: {username}\n\n"
            "Now enter your password:"
        )
        return PASSWORD

    async def receive_password(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
        """Verify credentials and complete login"""
        password = update.message.text.strip()
        username = context.user_data.get('username')
        user_id = update.effective_user.id

        # Delete password message for security
        try:
            await update.message.delete()
        except:
            pass

        # Verify credentials
        if username in VALID_CREDENTIALS and VALID_CREDENTIALS[username] == password:
            self.authenticated_users.add(user_id)
            await update.message.reply_text(
                "✅ Login successful!\n\n"
                "You now have access to all commands:\n\n"
                "📊 Information Commands:\n"
                "/info - Get system information\n"
                "/stats - View statistics\n"
                "/users - List users\n"
                "/data - Get data summary\n\n"
                "🔧 Other Commands:\n"
                "/help - Show this help message\n"
                "/logout - Logout from bot"
            )
            logger.info(f"User {user_id} ({username}) logged in successfully")
        else:
            await update.message.reply_text(
                "❌ Invalid credentials!\n\n"
                "Please try again with /login"
            )
            logger.warning(f"Failed login attempt for user {user_id}")

        return ConversationHandler.END

    async def cancel_login(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
        """Cancel login process"""
        await update.message.reply_text("Login cancelled.")
        return ConversationHandler.END

    async def logout(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /logout command"""
        user_id = update.effective_user.id

        if user_id in self.authenticated_users:
            self.authenticated_users.remove(user_id)
            await update.message.reply_text(
                "👋 Logged out successfully!\n"
                "Use /login to login again."
            )
            logger.info(f"User {user_id} logged out")
        else:
            await update.message.reply_text("You're not logged in.")

    async def help_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle /help command"""
        user_id = update.effective_user.id

        if user_id in self.authenticated_users:
            await update.message.reply_text(
                "📚 Available Commands:\n\n"
                "📊 Information Commands:\n"
                "/info - Get system information\n"
                "/stats - View statistics\n"
                "/users - List users\n"
                "/data - Get data summary\n\n"
                "🔧 Other Commands:\n"
                "/help - Show this help message\n"
                "/logout - Logout from bot"
            )
        else:
            await update.message.reply_text(
                "🔒 Authentication Required\n\n"
                "Please /login first to access commands.\n\n"
                "Available after login:\n"
                "• System information\n"
                "• Statistics\n"
                "• User lists\n"
                "• Data summaries"
            )

    # Protected information commands (require authentication)

    def require_auth(func):
        """Decorator to require authentication for commands"""
        async def wrapper(self, update: Update, context: ContextTypes.DEFAULT_TYPE):
            user_id = update.effective_user.id
            if user_id not in self.authenticated_users:
                await update.message.reply_text(
                    "🔒 Authentication Required\n\n"
                    "Please /login first to access this command."
                )
                return
            return await func(self, update, context)
        return wrapper

    @require_auth
    async def info_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Get system information (protected)"""
        await update.message.reply_text(
            "📊 System Information\n\n"
            "• Bot Status: Online\n"
            "• Version: 1.0.0\n"
            "• Active Users: " + str(len(self.authenticated_users)) + "\n"
            "• Database: Connected\n"
            "• Last Update: 2025-10-06"
        )

    @require_auth
    async def stats_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """View statistics (protected)"""
        await update.message.reply_text(
            "📈 Statistics\n\n"
            "• Total Requests: 1,234\n"
            "• Active Sessions: " + str(len(self.authenticated_users)) + "\n"
            "• Success Rate: 98.5%\n"
            "• Avg Response Time: 45ms\n"
            "• Uptime: 99.9%"
        )

    @require_auth
    async def users_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """List users (protected)"""
        user_list = "\n".join([f"• User ID: {uid}" for uid in self.authenticated_users])
        await update.message.reply_text(
            f"👥 Active Users ({len(self.authenticated_users)})\n\n"
            f"{user_list if user_list else 'No active users'}"
        )

    @require_auth
    async def data_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Get data summary (protected)"""
        await update.message.reply_text(
            "💾 Data Summary\n\n"
            "• Records: 5,678\n"
            "• Storage Used: 234 MB\n"
            "• Last Backup: 2h ago\n"
            "• Data Integrity: ✅ Good\n"
            "• Sync Status: ✅ Synced"
        )

    async def unauthorized_command(self, update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
        """Handle messages from non-authenticated users"""
        user_id = update.effective_user.id
        if user_id not in self.authenticated_users:
            await update.message.reply_text(
                "🔒 Please /login first to use this bot."
            )


def main() -> None:
    """Start the bot"""
    # Get bot token from environment variable
    token = os.getenv('TELEGRAM_BOT_TOKEN')
    if not token:
        logger.error("TELEGRAM_BOT_TOKEN environment variable not set!")
        print("\n❌ Error: TELEGRAM_BOT_TOKEN not set!")
        print("Please set it with: export TELEGRAM_BOT_TOKEN='your-token-here'\n")
        return

    # Create bot instance
    bot = AuthenticatedBot()

    # Create application
    application = Application.builder().token(token).build()

    # Login conversation handler
    login_handler = ConversationHandler(
        entry_points=[CommandHandler('login', bot.login_start)],
        states={
            USERNAME: [MessageHandler(filters.TEXT & ~filters.COMMAND, bot.receive_username)],
            PASSWORD: [MessageHandler(filters.TEXT & ~filters.COMMAND, bot.receive_password)],
        },
        fallbacks=[CommandHandler('cancel', bot.cancel_login)],
    )

    # Add handlers
    application.add_handler(CommandHandler('start', bot.start))
    application.add_handler(login_handler)
    application.add_handler(CommandHandler('logout', bot.logout))
    application.add_handler(CommandHandler('help', bot.help_command))

    # Protected information commands
    application.add_handler(CommandHandler('info', bot.info_command))
    application.add_handler(CommandHandler('stats', bot.stats_command))
    application.add_handler(CommandHandler('users', bot.users_command))
    application.add_handler(CommandHandler('data', bot.data_command))

    # Handle unauthorized messages
    application.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND,
        bot.unauthorized_command
    ))

    # Set bot commands for menu
    async def post_init(app: Application) -> None:
        await app.bot.set_my_commands([
            BotCommand("start", "Start the bot"),
            BotCommand("login", "Login to access commands"),
            BotCommand("help", "Show help message"),
            BotCommand("info", "Get system information (requires login)"),
            BotCommand("stats", "View statistics (requires login)"),
            BotCommand("users", "List users (requires login)"),
            BotCommand("data", "Get data summary (requires login)"),
            BotCommand("logout", "Logout from bot"),
        ])

    application.post_init = post_init

    # Start the bot
    logger.info("Bot started successfully!")
    print("\n✅ Bot is running...")
    print("Press Ctrl+C to stop\n")
    application.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == '__main__':
    main()
