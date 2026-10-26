# Save Point

A Hack Club YSWS: keep working on an unfinished game, usually your jame gam entry, and earn a prize for the new hours.

The site is [savepoint.hackclub.com](https://savepoint.hackclub.com). The code is MIT licensed. The project wiki, with its decisions and handoffs, is private.

| Path | What it is |
|---|---|
| `app/`, `config/`, `db/`, `test/` … | The Rails 8.1 app. Rails 8.1 on Postgres. |
| `app/views/pages/home.html.erb` | The landing page, with its partials in `app/views/pages/landing/`, styles in `app/assets/stylesheets/save_point/landing.css`, and Stimulus controllers `goal`, `prize-reel`, `countdown`, `local-time` and `dock`. |
| `app/models/prize.rb`, `app/models/program.rb` | The prizes and their hours, and the program's start and end (`Program::STARTS_AT`, `Program::ENDS_AT`). |
| `design/` | The style sheet. `build/make.py` writes `system/`, and `bin/rails style_sheet:sync` copies it into `app/assets`. |

Run it (Ruby 3.4.3 from `.ruby-version`, and Postgres):

```
bundle install
bin/rails db:prepare
bin/dev
```

Run the tests:

```
bin/rails test
bin/rails test:system
```

After the style sheet changes, run `bin/rails style_sheet:sync` and commit what it writes. CI fails while the app's copy is behind.

`main` is protected. Open a pull request; it merges itself when CI passes.
