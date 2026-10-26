require "application_system_test_case"

class TopBarTest < ApplicationSystemTestCase
  test "a locked My project tab goes nowhere, and unlocking it makes it a Turbo visit" do
    visit onboarding_path
    execute_script("window.__marker = 1; window.__visits = []; document.addEventListener('turbo:before-visit', e => window.__visits.push(e.detail.url))")
    tab = find(".top-bar__nav a.top-bar__project")
    tab.click
    sleep 0.2
    assert_current_path onboarding_path
    assert_equal [], evaluate_script("window.__visits")
    tab.send_keys(:enter)
    sleep 0.2
    assert_equal [], evaluate_script("window.__visits")

    # Onboarding's controller unlocks the tab by flipping aria-disabled.
    execute_script("document.querySelector('.top-bar__project').setAttribute('aria-disabled', 'false')")
    find(".top-bar__nav a.top-bar__project").click
    sleep 0.5
    assert_match(%r{/project\z}, evaluate_script("window.__visits[0]"))
    assert_equal 1, evaluate_script("window.__marker"), "a Turbo visit, not a reload"
  end

  test "clicking the tab you are on does not navigate" do
    visit onboarding_path
    execute_script("window.__marker = 1; window.__visits = []; document.addEventListener('turbo:before-visit', e => window.__visits.push(e.detail.url)); window.__navs = performance.getEntriesByType('navigation').length")
    current = find(".top-bar__nav a[aria-current='page']")
    current.click
    current.send_keys(:enter)
    sleep 0.4
    assert_equal [], evaluate_script("window.__visits")
    assert_equal 1, evaluate_script("window.__marker"), "the page was not reloaded"
    assert_equal "page", find(".top-bar__nav a", text: "Onboarding")[:"aria-current"]
    assert_current_path onboarding_path
  end
end
