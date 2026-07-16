import pepino

suite "calculator scenarios (all covered)":

  test "Add two numbers":
    check 50 + 70 == 120

  test "Subtract two numbers":
    check 100 - 40 == 60

  test "Multiply two numbers":
    check 3 * 4 == 12
