require "test_helper"
require "rake"

class ScreenshotsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("screenshots:drop_lost")
    Rake::Task["screenshots:drop_lost"].reenable
  end

  teardown { ENV.delete("CONFIRM") }

  def lost_project
    project = Project.first or skip "no project fixture"
    project.screenshot.attach(io: StringIO.new("x"), filename: "gone.png", content_type: "image/png")
    project.screenshot.blob.service.delete(project.screenshot.blob.key)
    project
  end

  test "a dry run lists a lost screenshot and keeps it" do
    project = lost_project
    out, = capture_io { Rake::Task["screenshots:drop_lost"].invoke }
    assert_includes out, "project #{project.id}: gone.png"
    assert project.reload.screenshot.attached?
  end

  test "CONFIRM=1 drops the attachment and blob" do
    project = lost_project
    blob_id = project.screenshot.blob.id
    ENV["CONFIRM"] = "1"
    capture_io { Rake::Task["screenshots:drop_lost"].invoke }
    assert_not project.reload.screenshot.attached?
    assert_nil ActiveStorage::Blob.find_by(id: blob_id)
  end
end
