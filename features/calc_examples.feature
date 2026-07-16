Feature: Calculator
  In order to avoid silly mistakes
  As a math idiot
  I want to be told the sum of two numbers

  Scenario: Add two numbers
    Given I have entered 50 into the calculator
    And I have entered 70 into the calculator
    When I press add
    Then the result should be 120 on the screen

  Scenario: Subtract two numbers
    Given I have entered 100 into the calculator
    And I have entered 40 into the calculator
    When I press subtract
    Then the result should be 60 on the screen

  Scenario: Multiply two numbers
    Given I have entered <left_op> into the calculator
    And I have entered <right_op> into the calculator
    When I press multiply
    Then the result should be <expected> on the screen

    Examples:
      | left_op | right_op | expected |
      |    0    |   0      |    0  |
      |    1    |   1      |    1  |
      |    2    |   3      |    6  |
      |    3    |   5      |   15  |
