# schema.rb doesn't dump views, so a fresh database has no `insights` schema until the migrations that create them
# run. After a schema load, run those migrations' `up` (the one place the view SQL lives) when the views are absent.
# An existing database gets its views from `db:migrate`, so this does nothing there.
#
# A schema load marks every migration as run, so one left out of this list never runs on that database: add each new
# migration that creates or replaces an insights view. The files run in the order of their timestamps, whatever the order here.
INSIGHTS_VIEW_MIGRATIONS ||= %w[
  CreateInsightsViews
  AddUtmToInsightsViews
  AddLastSeenToInsightsUsers
  AddOnboardingProgressToInsightsUsers
  AddHackatimeSeenToInsightsProjects
  UpdateInsightsShipsForFraudStage
  AddRetentionDataToInsightsViews
  AddFaqReadsToInsightsViews
  AddReaderIdToInsightsFaqReads
  HideSupersededShipsFromInsights
].freeze

namespace :insights do
  desc "Create the insights views on a database loaded from schema.rb. Safe to repeat."
  task load_views: :environment do
    connection = ActiveRecord::Base.connection
    next if connection.select_value("select 1 from pg_views where schemaname = 'insights' and viewname = 'users'")

    pattern = INSIGHTS_VIEW_MIGRATIONS.map(&:underscore).join(",")
    Dir[Rails.root.join("db/migrate/*_{#{pattern}}.rb")].sort.each do |file|
      require file
      File.basename(file, ".rb").sub(/\A\d+_/, "").camelize.constantize.new.up
    end
  end
end

# db:prepare (what bin/docker-entrypoint runs) loads the schema without invoking db:schema:load, so hook both.
%w[db:schema:load db:prepare].each do |name|
  Rake::Task[name].enhance { Rake::Task["insights:load_views"].invoke } if Rake::Task.task_defined?(name)
end
