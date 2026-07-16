import pepino
import std/strutils

suite "calculator scenarios with examples":

  test "Add two numbers":
    check 50 + 70 == 120

  test "Subtract two numbers":
    check 100 - 40 == 60

  # The "Multiply two numbers" scenario has 4 Examples rows. Writing the `test`
  # once (no "[k]") makes pepino expand it into one run per example row, each
  # named "Multiply two numbers [k]". The row's cells (left_op, right_op,
  # expected) are injected as string variables, so the same body asserts against
  # every example -- producing 4 scenario lines in the summary from a single
  # `test` in the source.
  test "Multiply two numbers":
    check parseInt(left_op) * parseInt(right_op) == parseInt(expected)
