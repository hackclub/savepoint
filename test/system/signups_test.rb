require "application_system_test_case"

class SignupsTest < ApplicationSystemTestCase
  test "the landing page counts the people finishing their game, and follows the server without a reload" do
    visit root_path
    assert_selector "a.cta--join", text: /Join\s+\d+\s+people also finishing their game/

    # The poll is every 30 s; coming back to the tab asks at once, so the test answers that ask.
    execute_script(<<~JS)
      window.fetch = () => Promise.resolve(new Response(JSON.stringify({ count: 1 }), { headers: { "Content-Type": "application/json" } }))
      document.dispatchEvent(new Event("visibilitychange"))
    JS

    assert_selector "a.cta--join", text: /\AJoin\s+1\s+person also finishing their game\s*\z/

    # Back to nobody: the button goes back to its plain label.
    execute_script(<<~JS)
      window.fetch = () => Promise.resolve(new Response(JSON.stringify({ count: 0 }), { headers: { "Content-Type": "application/json" } }))
      document.dispatchEvent(new Event("visibilitychange"))
    JS

    assert_selector "a.cta--join", text: /\AContinue your game\s*\z/
  end
end
