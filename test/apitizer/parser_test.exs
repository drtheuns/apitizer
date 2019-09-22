defmodule Apitizer.ParserTest do
  use ExUnit.Case, async: true
  doctest Apitizer.Parser, import: true

  defp filter(query) do
    Apitizer.Parser.parse_filter(query)
  end

  test "it should parse comparison expressions" do
    assert filter("and(student.eq.true, grade.gte.90)") ==
             [{:and, [{:eq, "student", true}, {:gte, "grade", 90}]}]

    assert filter("and(name.eq.john,grade.in.(1,2,3))") ==
             [and: [{:eq, "name", "john"}, {:in, "grade", [1, 2, 3]}]]
  end

  test "it should accept recursive and/or expressions" do
    assert filter("or(role.eq.student,and(course.eq.English Literature,name.eq.John))") ==
             [
               or: [
                 {:eq, "role", "student"},
                 {:and, [{:eq, "course", "English Literature"}, {:eq, "name", "John"}]}
               ]
             ]

    assert filter(
             "and(something.eq.wow, switch.eq.true, or(value.gte.5,value.lte.2), and(field.eq.true, name.eq.null))"
           ) ==
             [
               and: [
                 {:eq, "something", "wow"},
                 {:eq, "switch", true},
                 {:or, [{:gte, "value", 5}, {:lte, "value", 2}]},
                 {:and, [{:eq, "field", true}, {:eq, "name", nil}]}
               ]
             ]

    assert filter("and(or(grade.gte.9,and(grade.lte.3,name.eq.john)))") ==
             [
               and: [
                 {:or, [{:gte, "grade", 9}, {:and, [{:lte, "grade", 3}, {:eq, "name", "john"}]}]}
               ]
             ]
  end

  test "it should accept empty lists" do
    assert filter("and(id.in.())") == [and: [{:in, "id", []}]]
  end

  test "it should remove empty and/or expressions" do
    assert filter("and()") == []
    assert filter("or()") == []
    assert filter("and(id.eq.5,or())") == [and: [{:eq, "id", 5}]]
  end

  test "it should accept quoted expressions" do
    assert filter("and(field.in.(\"hello, world\", \"5\"))") == [
             and: [{:in, "field", ["hello, world", "5"]}]
           ]

    assert filter("and(name.eq.\"Doe, John\", id.eq.\"5\")") == [
             and: [{:eq, "name", "Doe, John"}, {:eq, "id", "5"}]
           ]
  end

  describe "casting" do
    test "integers should be cast to integers" do
      [and: [{:in, "id", values}]] = filter("and(id.in.(1,2,3))")

      Enum.each(values, fn value ->
        assert is_integer(value)
      end)
    end

    test "decimal numbers (with a .) should be cast to floats" do
      assert filter("and(grade.eq.4.5)") == [and: [{:eq, "grade", 4.5}]]

      assert filter("and(grade.in.(5.5, 6.5, 7.5, 8.5, 9.5))") == [
               and: [{:in, "grade", [5.5, 6.5, 7.5, 8.5, 9.5]}]
             ]
    end

    test "it should cast boolean expression for neq and eq" do
      assert filter("and(is_visible.eq.true,is_published.neq.false)") == [
               and: [{:eq, "is_visible", true}, {:neq, "is_published", false}]
             ]

      assert filter("and(updated_at.eq.null,published_at.neq.null)") == [
               and: [{:eq, "updated_at", nil}, {:neq, "published_at", nil}]
             ]
    end

    test "quoted expressions should not be cast" do
      assert filter("and(is_visible.eq.\"true\")") == [and: [{:eq, "is_visible", "true"}]]
      assert filter("and(is_visible.neq.\"false\")") == [and: [{:neq, "is_visible", "false"}]]

      assert filter("and(id.in.(\"1,2,3\", \"true\", \"null\"))") == [
               and: [{:in, "id", ["1,2,3", "true", "null"]}]
             ]
    end
  end
end
