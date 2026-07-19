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
    And the tools include wd_dismiss_alert
    And the tools include wd_alert_text
    And the tools include wd_all_cookies
    And the tools include wd_get_cookie
    And the tools include wd_delete_all_cookies
    And the tools include wd_delete_cookie
    And the tools include wd_forward
    And the tools include wd_back
    And the tools include wd_refresh
    And the tools include wd_current_url
    And the tools include wd_running
    And the tools include wd_status
    And the tools include wd_title
    And the tools include wd_width
    And the tools include wd_y
    And the tools include wd_rect
    And the tools include wd_element_rect
    And the tools include wd_save_screen_shot_to
    And the tools include wd_visible_text
    And the tools include wd_active_element
    And the tools include wd_attribute
    And the tools include wd_clear
    And the tools include wd_click
    And the tools include wd_double_click
    And the tools include wd_drag_and_drop
    And the tools include wd_send_keys
    And the tools include wd_css_property_value
    And the tools include wd_property
    And the tools include wd_enabled
    And the tools include wd_displayed
    And the tools include wd_selected
    And the tools include wd_submit
    And the tools include wd_tag_name
    And the tools include wd_take_screen_shot_base64
    And the tools include wd_text
    And the tools include wd_upload_file
    And the tools include wd_height
    And the tools include wd_location

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

  Scenario: Dismiss a JavaScript alert
    Given an open webdriver session on "https://example.com"
    When I call wd_dismiss_alert
    Then the alert is dismissed

  Scenario: Get all cookies
    Given an open webdriver session on "https://example.com"
    When I call wd_all_cookies
    Then the cookies include "test=test_value"

  Scenario: Get a cookie by name
    Given an open webdriver session on "https://example.com"
    When I call wd_get_cookie with name "test"
    Then the cookie value is "test_value"

  Scenario: Delete all cookies
    Given an open webdriver session on "https://example.com"
    When I call wd_delete_all_cookies
    Then all cookies are deleted

  Scenario: Delete a cookie by name
    Given an open webdriver session on "https://example.com"
    When I call wd_delete_cookie with name "test"
    Then the cookie "test" is deleted

  Scenario: Navigate forward
    Given an open webdriver session on "https://example.com"
    When I call wd_forward
    Then the browser navigates forward

  Scenario: Navigate back
    Given an open webdriver session on "https://example.com"
    When I call wd_back
    Then the browser navigates back

  Scenario: Refresh the page
    Given an open webdriver session on "https://example.com"
    When I call wd_refresh
    Then the page is refreshed

  Scenario: Get current URL
    Given an open webdriver session on "https://example.com"
    When I call wd_current_url
    Then the current URL is "https://example.com"

  Scenario: Check if the browser is running
    Given an open webdriver session on "https://example.com"
    When I call wd_running
    Then the browser status is "true"

  Scenario: Get WebDriver status
    Given an open webdriver session on "https://example.com"
    When I call wd_status
    Then the WebDriver status includes "ready=true"

  Scenario: Get the page title
    Given an open webdriver session on "https://example.com"
    When I call wd_title
    Then the page title is "Example Domain"

  Scenario: Get the window width
    Given an open webdriver session on "https://example.com"
    When I call wd_width
    Then the window width is "1024"

  Scenario: Get the window y-coordinate
    Given an open webdriver session on "https://example.com"
    When I call wd_y
    Then the window y-coordinate is "0"

  Scenario: Get the window rect
    Given an open webdriver session on "https://example.com"
    When I call wd_rect
    Then the window rect includes "x=0.0, y=0.0, width=1024.0, height=768.0"

  Scenario: Get the rect of an element
    Given an open webdriver session on "https://example.com"
    When I call wd_element_rect with css_selector "button"
    Then the element rect includes "x=0.0, y=0.0, width=200.0, height=100.0"

  Scenario: Save a screenshot of an element to a file
    Given an open webdriver session on "https://example.com"
    When I call wd_save_screen_shot_to with css_selector "button" and filename "element.png"
    Then the screenshot is saved to "element.png"

  Scenario: Get visible text of an element
    Given an open webdriver session on "https://example.com"
    When I call wd_visible_text with css_selector "h1"
    Then the visible text is "Example Domain"

  Scenario: Get the active element selector
    Given an open webdriver session on "https://example.com"
    When I call wd_active_element
    Then it return element css selector

  Scenario: Get an element attribute
    Given an open webdriver session on "https://example.com"
    When I call wd_attribute with css_selector "a" and attr_name "href"
    Then the attribute value is "mock-attribute-value"

  Scenario: Clear an element
    Given an open webdriver session on "https://example.com"
    When I call wd_clear with css_selector "input"
    Then the element is cleared

  Scenario: Click on an element
    Given an open webdriver session on "https://example.com"
    When I call wd_click with css_selector "button"
    Then the element is clicked

  Scenario: Right-click on an element
    Given an open webdriver session on "https://example.com"
    When I call wd_click with css_selector "button" and button "mbRight"
    Then the element is clicked

  Scenario: Double-click on an element
    Given an open webdriver session on "https://example.com"
    When I call wd_double_click with css_selector "button"
    Then the element is double-clicked

  Scenario: Right double-click on an element
    Given an open webdriver session on "https://example.com"
    When I call wd_double_click with css_selector "button" and button "mbRight"
    Then the element is double-clicked

  Scenario: Drag an element by offset
    Given an open webdriver session on "https://example.com"
    When I call wd_drag_and_drop with css_selector "div" and delta_x 100 and delta_y 50
    Then the element is dragged

  Scenario: Send keys to an element
    Given an open webdriver session on "https://example.com"
    When I call wd_send_keys with css_selector "input" and text "hello world"
    Then the keys are sent

  Scenario: Get a CSS property value
    Given an open webdriver session on "https://example.com"
    When I call wd_css_property_value with css_selector "h1" and name "color"
    Then the css value is "mock-css-value"

  Scenario: Get an element property value
    Given an open webdriver session on "https://example.com"
    When I call wd_property with css_selector "input" and name "value"
    Then the property value is "mock-property-value"

  Scenario: Check whether an element is enabled
    Given an open webdriver session on "https://example.com"
    When I call wd_enabled with css_selector "button"
    Then the element is enabled "true"

  Scenario: Check whether an element is displayed
    Given an open webdriver session on "https://example.com"
    When I call wd_displayed with css_selector "button"
    Then the element is displayed "true"

  Scenario: Check whether an element is selected
    Given an open webdriver session on "https://example.com"
    When I call wd_selected with css_selector "input"
    Then the element is selected "true"

  Scenario: Submit a form containing an element
    Given an open webdriver session on "https://example.com"
    When I call wd_submit with css_selector "input"
    Then the element is submitted

  Scenario: Get the tag name of an element
    Given an open webdriver session on "https://example.com"
    When I call wd_tag_name with css_selector "input"
    Then the tag name includes "h1"

  Scenario: Take a base64 screenshot of an element
    Given an open webdriver session on "https://example.com"
    When I call wd_take_screen_shot_base64 with css_selector "button"
    Then the screenshot base64 includes "iVBORw0KGgo"

  Scenario: Get the visible text of an element
    Given an open webdriver session on "https://example.com"
    When I call wd_text with css_selector "h1"
    Then the element text includes "mock-property-value"

  Scenario: Upload a file to a file input element
    Given an open webdriver session on "https://example.com"
    When I call wd_upload_file with css_selector "input" and filename "test-upload.txt"
    Then the file is uploaded to "test-upload.txt"

  Scenario: Get the height of an element
    Given an open webdriver session on "https://example.com"
    When I call wd_height with css_selector "button"
    Then the element height is "100.0"

  Scenario: Get the location of an element
    Given an open webdriver session on "https://example.com"
    When I call wd_location with css_selector "button"
    Then the element location includes "x=0.0, y=0.0"
