import pepino

suite "calculator scenarios":

  test "Add two numbers":
    check 50 + 70 == 120

  test "Subtract two numbers":
    check 100 - 40 == 60

  # Note: "Multiply two numbers" has no matching test below -- pepino will
  # report it as `undefined`, just like Cucumber reports a scenario with no
  # step definitions.
