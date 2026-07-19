import pepino

suite "calc with a failing scenario":

  test "Add two numbers":
    check 1 + 1 == 2

  test "Subtract two numbers":
    check 1 - 1 == 5   # deliberate failure

  test "Multiply two numbers":
    check 3 * 4 == 12
