Feature: WebDriver MCP
  As an MCP client
  I want to drive a remote WebDriver through MCP tools
  So that browser automation is available over the Model Context Protocol

  Scenario: List the webdriver tools
    Given an initialized webdrivermcp session
    When I list the tools
    Then the tools include wd_new_web_driver
    And the tools include wd_create_session
    And the tools include wd_close_session
    And the tools include wd_navigate
    And the tools include wd_get_page_source
    And the tools include wd_find_element
    And the tools include wd_get_text
    And the tools include wd_accept_alert
    And the tools include wd_alert_text
    And the tools include wd_all_cookies
    And the tools include wd_back

  Scenario: Create a webdriver and a session
    Given a webdrivermcp server
    When I call wd_new_web_driver with url "http://localhost:4444"
    And I call wd_create_session
    Then a session id is returned

  Scenario: Navigate and read page source
    Given an open webdriver session
    When I call wd_navigate with url "https://example.com"
    And I call wd_get_page_source
    Then the page source contains "Example Domain"

  Scenario: Find an element and read its text
    Given an open webdriver session on "https://example.com"
    When I call wd_find_element with selector "h1" and strategy "css"
    And I call wd_get_text on the element
    Then the element text is "Example Domain"

  Scenario: Close the session
    Given an open webdriver session
    When I call wd_close_session
    Then the session is closed

  Scenario: Accept a JavaScript alert
    Given an open webdriver session on "https://example.com"
    When I call wd_accept_alert
    Then the alert is accepted

  Scenario: Get alert text
    Given an open webdriver session on "https://example.com"
    When I call wd_alert_text
    Then the alert text is retrieved

  Scenario: Get all cookies
    Given an open webdriver session on "https://example.com"
    When I call wd_all_cookies
    Then the cookies include "test=test_value"

  Scenario: Navigate back
    Given an open webdriver session on "https://example.com"
    When I call wd_back
    Then the browser navigates back
