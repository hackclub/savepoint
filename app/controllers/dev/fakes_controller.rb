# Development only (the routes aren't there otherwise): the fake people from bin/rails dev:fake, to see the site as one
# of them (the admin "View as", then Stop to come back) and to have one accept your buddy invite in a click.
class Dev::FakesController < ApplicationController
  layout "save_point"

  before_action :development_only

  def index
    @people = User.where("hca_id LIKE 'ident!fake-%'").includes(project: [ :pair_as_first, :pair_as_second ]).order(:id)
    @me = true_user
    @invite = @me&.project && buddy_invite_url(@me.project.buddy_code!)
  end

  # A fake person who has no buddy yet accepts the invite of whoever you really are, as if they'd opened the link.
  def buddy
    project = true_user&.project
    return redirect_to dev_path, alert: "Set up your own project first (or run bin/rails dev:fake)." unless project
    return redirect_to buddy_path, alert: "You have a buddy already." if project.buddy

    fake = Project.joins(:user).where("users.hca_id LIKE 'ident!fake-%'").where.not(id: project.id).detect { |other| other.pair.nil? }
    return redirect_to dev_path, alert: "Every fake person has a buddy already. Run bin/rails dev:fake:reset, then dev:fake." unless fake

    fake.pair_with(project)
    redirect_to buddy_path, notice: "#{fake.user.public_name} accepted your invite."
  end

  # Pretend it's a given moment (the session keeps it), or go back to the real time when no moment is sent.
  def clock
    moment = Time.zone.parse(params[:now].to_s) if params[:now].present?
    moment ? session[:dev_now] = moment.iso8601 : session.delete(:dev_now)
    redirect_to dev_path, notice: moment ? "Pretending it's #{moment.utc.strftime("%b %-d, %H:%M")} UTC." : "Back to the real time."
  end

  # Your own project's hours, to walk through the goal and the shop: `kind` is logged (Hackatime's hours), approved (what
  # you can spend) or auto (back to the usual made-up logged hours); `percent` is of your goal prize's hours.
  def hours
    mine = Dev::MyProject.new(my_project) if my_project
    return redirect_to dev_path, alert: "Set up your own project first." unless mine

    percent = params[:percent].to_i
    return redirect_to dev_path, alert: "Pick one of the levels." unless Dev::MyProject::PERCENTS.include?(percent) || params[:kind] == "auto"

    hours = mine.hours_at(percent)
    case params[:kind]
    when "logged" then mine.set_logged!(hours)
    when "approved" then mine.set_approved!(hours)
    when "auto" then mine.set_logged!(nil)
    else return redirect_to dev_path, alert: "Pick logged or approved hours."
    end
    where_you_were(notice: params[:kind] == "auto" ? "Logged hours are back to the usual made-up pattern." : "Your #{params[:kind]} hours are #{helpers.project_hours(hours.to_f)} (#{percent}% of the #{my_project.prize_short}).")
  end

  def reset_orders
    return redirect_to dev_path, alert: "Set up your own project first." unless my_project

    Dev::MyProject.new(my_project).reset_orders!
    where_you_were(notice: "Your orders are gone, so you can claim again.")
  end

  def reset_goal_popup
    return redirect_to dev_path, alert: "Set up your own project first." unless my_project

    Dev::MyProject.new(my_project).reset_goal_popup!
    where_you_were(notice: "The goal popup shows again when your approved hours cover your goal.")
  end

  # Become a fake person outright (no OAuth in development), to walk their whole flow: shop, claim, the lot.
  def take_over
    person = User.find(params[:id])
    return redirect_to dev_path, alert: "Only fake people." unless Hackatime::Fake.fake_person?(person)

    session.delete(:impersonator_id)
    session[:user_id] = person.id
    redirect_to project_path, notice: "You're #{person.public_name} now. /dev takes you back."
  end

  # A brand-new fake person, as if they just signed in for the first time: created now, Hackatime linked, no project
  # yet. You become them and land in onboarding, to walk the sticker promise (D-051) end to end.
  def sticker_fresh
    number = (User.maximum(:id) || 0) + 1
    person = User.create!(hca_id: "ident!fake-fresh-#{number}", email: "fresh-#{number}@example.com",
                          name: "Fresh Example", first_name: "Fresh", verification_status: "verified",
                          ysws_eligible: true, hackatime_trust_level: "blue", timezone: "America/New_York",
                          hackatime_uid: "fake-fresh-#{number}", hackatime_access_token: "fake-token")
    session.delete(:impersonator_id)
    session[:user_id] = person.id
    redirect_to onboarding_path, notice: "Fresh sign-up: your first hour started now. Pick a game, then press \"Log 5 fake minutes\" on /dev."
  end

  # Plant fake coding minutes on your linked game just after you signed up, then run the sticker check (D-051), as the
  # next sync would.
  def sticker_minutes
    person = true_user
    return redirect_to dev_path, alert: "Take someone over (or make a fresh fake) first." unless person
    return redirect_to onboarding_path, alert: "Pick a game first: only minutes on your linked project count." unless person.project&.tracking?

    minutes = params.fetch(:minutes, 5).to_i.clamp(1, 60)
    Hackatime::Fake.plant_span!(person, start: person.created_at + 1.minute, duration: minutes * 60)
    Reward.award_stickers!(person)
    if person.earned?("stickers")
      redirect_to shop_path, notice: "#{minutes} fake minutes logged in your first hour: stickers earned. The claim card is at the top."
    else
      since = person.created_at >= Reward::STICKERS_SINCE
      reason = since ? "your first hour (plus the sync grace) has passed" : "this account is older than STICKERS_SINCE"
      redirect_back_or_to dev_path, alert: "#{minutes} fake minutes logged, but no stickers: #{reason}. Use \"Fresh sign-up\" instead."
    end
  end

  # Flip whether Hack Club Auth calls you YSWS-eligible, to see the sticker promise (D-051) vanish and come back.
  def sticker_eligible
    person = true_user
    return redirect_to dev_path, alert: "Take someone over (or make a fresh fake) first." unless person

    person.update!(ysws_eligible: !person.ysws_eligible?)
    redirect_to dev_path, notice: person.ysws_eligible? ? "You're YSWS-eligible now." : "You're not YSWS-eligible now: no sticker card, no claim."
  end

  # Fake a Hackatime ban (trust level red) or lift it (blue), and store it on you as the next stats answer would.
  def sticker_ban
    person = true_user
    return redirect_to dev_path, alert: "Take someone over (or make a fresh fake) first." unless person

    banned = !person.hackatime_banned?
    Hackatime::Fake.set_trust_level!(person, banned ? "red" : "blue")
    person.update_column(:hackatime_trust_level, Hackatime::Fake.trust_level(person))
    redirect_to dev_path, notice: banned ? "Hackatime has banned you (trust red): no stickers." : "Hackatime trusts you again (blue)."
  end

  private
    def my_project = true_user&.project

    # Back to the page you pressed it on, or your project page.
    def where_you_were(**flash)
      redirect_back_or_to project_path, allow_other_host: false, **flash
    end

    def development_only
      head :not_found unless Rails.env.development?
    end
end
