# Announcements

These files hold Block Kit messages. A rake task posts one to a Slack channel as Armand, with his name and photo and no APP badge. It runs only on Armand's machine.

## Get the token

1. Open the Save Point Slack app settings, then OAuth & Permissions.
2. Reinstall the app if Slack asks, so it grants the `chat:write` user scope.
3. Copy the "User OAuth Token". It starts with `xoxp-`.
4. Paste it into your local `.env` as `SLACK_USER_TOKEN`.

Armand does this himself. Never commit the token. The tool never prints it.

## Write a message

A file is JSON. It is either an object with `text` and `blocks`, or a bare blocks array. `text` is the fallback shown in notifications. For a bare array, the fallback is the text of the first header or section block.

Design the blocks in [Block Kit Builder](https://app.slack.com/block-kit-builder) and paste the blocks array into a file here. See `example.json`.

A message has 1 to 50 blocks. Each block needs a `type`.

## Commands

Preview. It needs no token. It checks the file and prints a Block Kit Builder link.

```
bin/rails "slack:announce:preview[announcements/example.json]"
```

Test. It posts the message to your own DM, so you see the real render.

```
bin/rails "slack:announce:test[announcements/example.json]"
```

Announce. It posts to a channel.

```
CONFIRM=C0123ABCD bin/rails "slack:announce[C0123ABCD,announcements/example.json]"
```

## The CONFIRM rule

The channel must be a channel ID like `C0123ABCD`. Without `CONFIRM=<the same channel ID>`, the task only prints what it would post and exits. It posts nothing.

The task always refuses `C0C5UHLAAP5` and `C0C60KQ0XLJ`. Those are the wrong tool's channels.

Links in the message do not unfurl.

## Images

An image block needs a public image URL. Two options:

- Put the file in `public/announcements/`. After a deploy it is at `https://savepoint.hackclub.com/announcements/<file>`.
- Use any other public URL.
