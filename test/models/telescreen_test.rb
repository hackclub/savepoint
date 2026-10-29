require "test_helper"

# D-114: the one place that builds Telescreen URLs, for the review page and the admin projects list.
class TelescreenTest < ActiveSupport::TestCase
  test "the Hackatime workbench opens for the stored numeric id and the escaped project names" do
    user = User.new(hackatime_uid: "1001")
    assert_equal "https://telescreen.hackclub.com/workbench/hackatime/overview?u=1001&p=Slime+Survivors,Excuse+Me%2C+Pardon+Me",
                 Telescreen.hackatime_url(user, [ "Slime Survivors", "Excuse Me, Pardon Me" ])
    assert_equal "https://telescreen.hackclub.com/workbench/hackatime/overview?u=1001", Telescreen.hackatime_url(user, [])
  end

  test "without a numeric id there is no URL, and the review page's bare workbench stands in" do
    [ nil, "", "abc", "12a", "12 3" ].each do |uid|
      user = User.new(hackatime_uid: uid)
      assert_nil Telescreen.hackatime_url(user, [ "pong" ]), uid.inspect
      assert_equal Telescreen::HACKATIME_WORKBENCH, Telescreen.hackatime_url_or_workbench(user, [ "pong" ])
      assert_equal Telescreen::LAPSE_REVIEW, Telescreen.lapse_review_url(user)
    end
    assert_equal "https://telescreen.hackclub.com/workbench/lapse?u=7", Telescreen.lapse_review_url(User.new(hackatime_uid: "7"))
  end
end
