import std/[unittest, strutils, options]
import pepino/pepino


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

suite "pepino helpers":

  test "toKeyword maps names":
    check toKeyword("Given").get == skGiven
    check toKeyword("when").get == skWhen
    check toKeyword("THEN").get == skThen
    check toKeyword("And").get == skAnd
    check toKeyword("But").get == skBut
    check toKeyword("*").get == skStar
    check toKeyword("foo").isNone

  test "keywordFromText splits keyword and rest":
    let r = keywordFromText("Given the user logs in").get
    check r.k == skGiven
    check r.rest == "the user logs in"

  test "keywordFromText handles star":
    let r = keywordFromText("* do something").get
    check r.k == skStar
    check r.rest == "do something"

  test "keywordFromText returns none for plain text":
    check keywordFromText("not a step").isNone

  test "splitTags parses stacked tags":
    check splitTags("@a @b @c") == @["a", "b", "c"]

  test "splitTags handles single tag":
    check splitTags("@smoke") == @["smoke"]

  test "parseTableRow trims cells":
    check parseTableRow("| name | age | city |") == @["name", "age", "city"]

  test "parseTableRow handles no leading/trailing spaces":
    check parseTableRow("|a|b|") == @["a", "b"]

  test "isTagLine detects tags":
    check isTagLine("  @tag")
    check not isTagLine("Feature: x")

  test "docStringDelim detects triple quote":
    check docStringDelim("\"\"\"json") == '"'
    check docStringDelim("```code") == '`'
    check docStringDelim("Given x") == '\0'


# ---------------------------------------------------------------------------
# basic feature + scenarios
# ---------------------------------------------------------------------------

suite "pepino basic parsing":

  const simple = """
Feature: Calculator
  As a user
  I want to add numbers

  Scenario: Add two numbers
    Given I have entered 50 into the calculator
    And I have entered 70 into the calculator
    When I press add
    Then the result should be 120 on the screen
"""

  test "parses feature name":
    let f = parseFeature(simple)
    check f.name == "Calculator"

  test "parses feature description":
    check "As a user" in parseFeature(simple).description
    check "I want to add numbers" in parseFeature(simple).description

  test "parses one scenario":
    let f = parseFeature(simple)
    check f.scenarios.len == 1
    check f.scenarios[0].name == "Add two numbers"

  test "parses steps with mixed keywords":
    let s = parseFeature(simple).scenarios[0]
    check s.steps.len == 4
    check s.steps[0].keyword == skGiven
    check s.steps[0].text == "I have entered 50 into the calculator"
    check s.steps[1].keyword == skAnd
    check s.steps[2].keyword == skWhen
    check s.steps[3].keyword == skThen

  test "no background when none defined":
    check parseFeature(simple).background.isNone


# ---------------------------------------------------------------------------
# background
# ---------------------------------------------------------------------------

suite "pepino background":

  const withBg = """
Feature: Login

  Background:
    Given a user exists
    And the system is up

  Scenario: User logs in
    When the user logs in
    Then access is granted
"""

  test "parses background":
    let f = parseFeature(withBg)
    check f.background.isSome
    check f.background.get.steps.len == 2
    check f.background.get.steps[0].text == "a user exists"

  test "scenario after background still parsed":
    let f = parseFeature(withBg)
    check f.scenarios.len == 1
    check f.scenarios[0].steps[0].keyword == skWhen


# ---------------------------------------------------------------------------
# scenario outline + examples
# ---------------------------------------------------------------------------

suite "pepino scenario outline":

  const outline = """
Feature: Outlines

  Scenario Outline: Eating
    Given there are <start> cucumbers
    When I eat <eat> cucumbers
    Then I should have <left> cucumbers

    Examples:
      | start | eat | left |
      | 12    | 5   | 7    |
      | 20    | 5   | 15   |
"""

  test "marks scenario as outline":
    let s = parseFeature(outline).scenarios[0]
    check s.isOutline

  test "parses examples header":
    let s = parseFeature(outline).scenarios[0]
    check s.examples.len == 1
    check s.examples[0].header == @["start", "eat", "left"]

  test "parses examples rows":
    let ex = parseFeature(outline).scenarios[0].examples[0]
    check ex.rows.len == 2
    check ex.rows[0] == @["12", "5", "7"]
    check ex.rows[1] == @["20", "5", "15"]

  test "steps contain placeholders":
    let s = parseFeature(outline).scenarios[0]
    check "<start>" in s.steps[0].text
    check "<eat>" in s.steps[1].text


# ---------------------------------------------------------------------------
# tags
# ---------------------------------------------------------------------------

suite "pepino tags":

  const tagged = """
@feature-tag
Feature: Tagged

@smoke @fast
Scenario: A
  Given x

@wip
Scenario: B
  Given y
"""

  test "feature tags captured":
    let f = parseFeature(tagged)
    check f.tags == @["feature-tag"]

  test "scenario tags captured on correct scenario":
    let f = parseFeature(tagged)
    check f.scenarios[0].tags == @["smoke", "fast"]
    check f.scenarios[1].tags == @["wip"]


# ---------------------------------------------------------------------------
# doc strings
# ---------------------------------------------------------------------------

suite "pepino doc strings":

  const doc = """
Feature: Payload

  Scenario: Send json
    Given a request with body
      ```
      {"a": 1, "b": 2}
      ```
    Then it is accepted
"""

  test "captures doc string":
    let s = parseFeature(doc).scenarios[0]
    check s.steps[0].docString.isSome
    check "{\"a\": 1" in s.steps[0].docString.get

  test "step after doc string still parsed":
    let s = parseFeature(doc).scenarios[0]
    check s.steps.len == 2
    check s.steps[1].keyword == skThen


# ---------------------------------------------------------------------------
# data tables on steps
# ---------------------------------------------------------------------------

suite "pepino step tables":

  const tbl = """
Feature: Users

  Scenario: Bulk
    Given the following users
      | name  | role  |
      | alice | admin |
      | bob   | user  |
"""

  test "captures step table":
    let s = parseFeature(tbl).scenarios[0]
    let step = s.steps[0]
    check step.table.len == 3
    check step.table[0] == @["name", "role"]
    check step.table[1] == @["alice", "admin"]
    check step.table[2] == @["bob", "user"]


# ---------------------------------------------------------------------------
# rule
# ---------------------------------------------------------------------------

suite "pepino rules":

  const ruleSrc = """
Feature: Rules

  Rule: Accounts are protected

    Scenario: No access
      Given a locked account
      When access is attempted
      Then it is denied
"""

  test "parses rule with scenario":
    let f = parseFeature(ruleSrc)
    check f.rules.len == 1
    check f.rules[0].name == "Accounts are protected"
    check f.rules[0].scenarios.len == 1
    check f.rules[0].scenarios[0].name == "No access"


# ---------------------------------------------------------------------------
# comments and blank lines
# ---------------------------------------------------------------------------

suite "pepino comments and whitespace":

  const commented = """
# a leading comment
Feature: C

  # comment inside
  Scenario: X
    Given a     # inline-ish comment is not stripped here
"""

  test "ignores leading comment":
    let f = parseFeature(commented)
    check f.name == "C"

  test "ignores comment lines":
    let s = parseFeature(commented).scenarios[0]
    check s.steps.len == 1


# ---------------------------------------------------------------------------
# error handling
# ---------------------------------------------------------------------------

suite "pepino errors":

  test "raises when no feature present":
    expect GherkinError:
      discard parseFeature("just some prose\nno feature here")

  test "raises with line info":
    try:
      discard parseFeature("nope")
      check false
    except GherkinError as e:
      check e.line >= 1
