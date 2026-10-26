require "test_helper"
require Rails.root.join("lib/slack_demo")

class SlackGifsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup { @admins = Rails.configuration.x.admin_slack_ids }
  teardown { Rails.configuration.x.admin_slack_ids = @admins }

  def with_gifs(on)
    before = Rails.configuration.x.slack_gifs
    Rails.configuration.x.slack_gifs = on
    yield
  ensure
    Rails.configuration.x.slack_gifs = before
  end

  def image_blocks(blocks) = blocks.select { |block| (block[:type] || block["type"]) == "image" }

  def queued_gif(user_slack_id)
    job = enqueued_jobs.find { |each| each[:job] == SlackMessageJob && each[:args].first == user_slack_id }
    job[:args].third["gif"]
  end

  test "the switch is off by default" do
    assert_not Rails.configuration.x.slack_gifs
    assert_nil SlackGifs.block("nudge.progress")
  end

  test "every key has a pool of gifs, each with an https GIPHY url and alt text, and the keys are the ones that send a gif" do
    SlackGifs::GIFS.each do |key, pool|
      assert pool.present?, key
      pool.each do |gif|
        assert_match(%r{\Ahttps://media\.giphy\.com/media/\w+/giphy(-downsized)?\.gif\z}, gif["url"], key)
        assert gif["alt"].present?, key
      end
    end
    (Nudge::Copy::ARMS.keys + Nudge::Copy::FIXED.keys - %w[hackatime_project last_day]).each { |arm| assert SlackGifs::GIFS.key?("nudge.#{arm}"), arm }
    %w[reward.gold_star reward.streak_shoutout extension.approved extension.denied order.ordered].each do |key|
      assert SlackGifs::GIFS.key?(key), key
    end
  end

  test "a key without a pool sends no image" do
    %w[nudge.hackatime_project nudge.last_day project.auto_link].each do |key|
      assert_not SlackGifs::GIFS.key?(key), key
      assert_nil SlackGifs.block(key, force: true)
    end
  end

  test "a pick rotates through the pool and wraps, and without one the gif is random within the pool" do
    pool = SlackGifs::GIFS.fetch("nudge.progress")
    assert_operator pool.size, :>, 1
    urls = (0..pool.size).map { |index| SlackGifs.block("nudge.progress", force: true, pick: index)[:image_url] }
    assert_equal pool.map { _1["url"] }, urls.first(pool.size)
    assert_equal urls.first, urls.last

    random = Array.new(40) { SlackGifs.block("nudge.progress", force: true)[:image_url] }
    assert_empty random - pool.map { _1["url"] }
    assert_operator random.uniq.size, :>, 1
  end

  test "a nudge has the image between its text and its buttons only with the switch on" do
    nudge = users(:orpheus).nudges.create!(channel: "slack", kind: "bandit", arm: "progress", text: "you're 35% of the way to a prize.")

    assert_empty image_blocks(Nudge::Message.new(nudge).blocks)

    with_gifs(true) do
      assert_equal %w[section image actions], Nudge::Message.new(nudge).blocks.map { _1[:type] }
      image = image_blocks(Nudge::Message.new(nudge).blocks).first
      assert_includes SlackGifs::GIFS.fetch("nudge.progress").map { _1["url"] }, image[:image_url]
      assert image[:alt_text].present?
    end
  end

  test "a reward DM queues its gif key, and the job draws it only with the switch on" do
    users(:orpheus).update!(slack_id: "U0ORPHEUS")
    RewardNotifier.earned(Struct.new(:key, :announce_at, :users).new("gold_star", nil, [ users(:orpheus) ]))
    assert_equal "reward.gold_star", queued_gif("U0ORPHEUS")

    link = [ "Open Save Point", "https://example.test/project" ]
    assert_empty image_blocks(SlackMessageJob.blocks("hi", link, gif: "reward.gold_star"))
    with_gifs(true) do
      blocks = SlackMessageJob.blocks("hi", link, gif: "reward.gold_star")
      assert_equal %w[section image actions], blocks.map { _1["type"] }
    end
  end

  test "an extension decision and an ordered DM queue their gif keys, and an auto-link DM has none" do
    Rails.configuration.x.admin_slack_ids = []
    extension = projects(:ana).create_extension!(reason: "exams")
    extension.decide!("approved", by: users(:orpheus))
    assert_equal "extension.approved", queued_gif("U0ANA")

    clear_enqueued_jobs
    OrderNotifier.ordered(Struct.new(:project, :configuration).new(projects(:ana), "a keyboard"))
    assert_equal "order.ordered", queued_gif("U0ANA")

    clear_enqueued_jobs
    projects(:ana).send(:dm_about_auto_link, "pong-v2")
    assert_nil queued_gif("U0ANA")
  end

  test "admin DMs never have a gif" do
    Rails.configuration.x.admin_slack_ids = [ "U0ADMIN" ]
    ExtensionNotifier.requested(projects(:ana).create_extension!(reason: "exams"))
    job = enqueued_jobs.find { |each| each[:job] == SlackMessageJob && each[:args].first == "U0ADMIN" }
    assert_nil job[:args].third["gif"]
  end

  test "the demo shows the gifs whatever the switch says, and only on participant DMs" do
    assert_not Rails.configuration.x.slack_gifs
    messages = SlackDemo.new("U0123ABCD").messages
    with_image, without = messages.partition { |message| image_blocks(message.blocks).any? }

    assert_operator with_image.size, :>=, 50
    assert_equal [ "order · admin DM", "extension · admin DM", "auto-link DM", "streak shoutout channel post", "nudge · hackatime_project", "nudge · last_day" ],
                 without.map { |message| message.label[/(order · admin DM|extension · admin DM|auto-link DM|streak shoutout channel post|nudge · hackatime_project|nudge · last_day)/] }
  end

  test "in the demo each variant of an arm shows a different gif" do
    messages = SlackDemo.new("U0123ABCD").messages
    %w[progress streak pledge overtake cheer_done cheer_streak].each do |arm|
      urls = messages.select { |message| message.label.include?("· #{arm} ·") }.map { |message| image_blocks(message.blocks).first[:image_url] }
      assert_operator urls.size, :>=, 3
      assert_equal urls.uniq, urls, arm
    end
    nudges = messages.select { |message| message.label.include?("nudge ·") }.map { |message| image_blocks(message.blocks).first&.dig(:image_url) }
    assert nudges.each_cons(2).none? { |a, b| a && a == b }
  end
end
