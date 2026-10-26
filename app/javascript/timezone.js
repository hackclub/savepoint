// Your timezone (like "America/New_York"), for the server: ApplicationController#remember_timezone saves it to your
// account, so streak days and the bot's messages follow your local time. Set before you sign in too, so it's there
// on the way back from Hack Club Auth.
const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
if (timezone) document.cookie = `timezone=${encodeURIComponent(timezone)}; path=/; max-age=31536000; samesite=lax`
