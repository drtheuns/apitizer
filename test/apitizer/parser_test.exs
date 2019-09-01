defmodule Apitizer.ParserTest do
  use ExUnit.Case, async: true

  defp filter(query) do
    Apitizer.Parser.parse_filter(query)
  end

  # TODO: Quoted expressions (e.g. if it contains a comma).

  test "it should parse comparison expressions" do
    assert filter("and(student.is.true, grade.gte.90)") ==
             [{:and, [{:is, "student", true}, {:gte, "grade", 90}]}]

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
             "and(something.eq.wow, switch.is.true, or(value.gte.5,value.lte.2), and(field.is.true, name.is.null))"
           ) ==
             [
               and: [
                 {:eq, "something", "wow"},
                 {:is, "switch", true},
                 {:or, [{:gte, "value", 5}, {:lte, "value", 2}]},
                 {:and, [{:is, "field", true}, {:is, "name", nil}]}
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
end
